import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'model.dart';
import 'schedule.dart';

/// Keeps spots and clips on the device only (app Documents/teiten + index.json).
/// File names are stored relative to the folder, because the absolute
/// container path on iOS changes between app updates.
class SpotStore extends ChangeNotifier {
  SpotStore({Directory? root}) : _rootOverride = root;
  final Directory? _rootOverride;
  late Directory _dir;
  final List<Spot> _spots = [];
  final Map<String, DayClip> _clips = {};
  bool ready = false;

  static const _version = 2;

  Directory get dir => _dir;
  File fileOf(String name) => File('${_dir.path}/$name');
  File get _index => fileOf('index.json');

  Future<void> load() async {
    final root = _rootOverride ?? await getApplicationDocumentsDirectory();
    _dir = Directory('${root.path}/teiten');
    await _dir.create(recursive: true);
    // The hourly prototype (unreleased, TestFlight only) kept clips in
    // Documents/clips. That format has no notion of spots, so drop it.
    final legacy = Directory('${root.path}/clips');
    if (await legacy.exists()) {
      try {
        await legacy.delete(recursive: true);
      } catch (e) {
        debugPrint('legacy cleanup failed: $e');
      }
    }
    if (await _index.exists()) {
      try {
        final j = jsonDecode(await _index.readAsString());
        if (j is Map && j['version'] == _version) {
          for (final s in (j['spots'] as List)) {
            _spots.add(Spot.fromJson(Map<String, dynamic>.from(s as Map)));
          }
          for (final c in (j['clips'] as List)) {
            final clip = DayClip.fromJson(Map<String, dynamic>.from(c as Map));
            if (await fileOf(clip.video).exists()) _clips[clip.id] = clip;
          }
        }
      } catch (e) {
        debugPrint('index read failed: $e');
      }
    }
    _spots.sort((a, b) => a.minute.compareTo(b.minute));
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final tmp = fileOf('index.json.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': _version,
      'spots': _spots.map((s) => s.toJson()).toList(),
      'clips': _clips.values.map((c) => c.toJson()).toList(),
    }));
    await tmp.rename(_index.path);
  }

  // ---- spots ----

  List<Spot> get spots => List.unmodifiable(_spots);
  bool get canAddSpot => _spots.length < kMaxSpots;
  Spot? spot(int id) => id == kSampleSpot.id ? kSampleSpot : _spots.where((s) => s.id == id).firstOrNull;

  Future<Spot> addSpot({required String name, required int minute}) async {
    if (!canAddSpot) throw StateError('max $kMaxSpots spots');
    final id = _spots.fold(0, (m, s) => s.id > m ? s.id : m) + 1;
    final s = Spot(id: id, name: name.trim().isEmpty ? '定点${_spots.length + 1}' : name.trim(), minute: minute % 1440);
    _spots
      ..add(s)
      ..sort((a, b) => a.minute.compareTo(b.minute));
    await _save();
    notifyListeners();
    return s;
  }

  Future<void> updateSpot(Spot s) async {
    final i = _spots.indexWhere((x) => x.id == s.id);
    if (i < 0) return;
    _spots[i] = s;
    _spots.sort((a, b) => a.minute.compareTo(b.minute));
    await _save();
    notifyListeners();
  }

  /// Removes the spot and every clip recorded for it.
  Future<void> removeSpot(int id) async {
    _spots.removeWhere((s) => s.id == id);
    final gone = _clips.values.where((c) => c.spotId == id).toList();
    for (final c in gone) {
      _clips.remove(c.id);
    }
    await _save();
    for (final c in gone) {
      await _deleteFiles(c);
    }
    notifyListeners();
  }

  // ---- clips ----

  List<DayClip> get all => _clips.values.toList();

  /// All clips of a spot, oldest first.
  List<DayClip> clipsOf(int spotId) {
    if (spotId == kSampleSpot.id) return List.of(sampleClips);
    return _clips.values.where((c) => c.spotId == spotId).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Set<String> datesOf(int spotId) => {for (final c in _clips.values) if (c.spotId == spotId) c.date};

  DayClip? at(int spotId, String date) => _clips['${spotId}_$date'];

  /// The latest clip before [date] that has a still frame (for the framing guide).
  DayClip? previousFrame(int spotId, String date) {
    final list = clipsOf(spotId).where((c) => c.date.compareTo(date) < 0 && c.thumb.isNotEmpty).toList();
    return list.isEmpty ? null : list.last;
  }

  int streak(Spot s, DateTime now) => streakOf(s, datesOf(s.id), now);

  /// Moves the recorded files into the store and replaces any clip of that day.
  Future<DayClip> add({required int spotId, required String date, required File video, File? thumb}) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = '${spotId}_${date}_$stamp';
    final vExt = video.path.contains('.') ? video.path.split('.').last : 'mov';
    final vName = '$base.$vExt';
    await _move(video, fileOf(vName));
    var tName = '';
    if (thumb != null && await thumb.exists()) {
      tName = '$base.jpg';
      await _move(thumb, fileOf(tName));
    }
    final old = at(spotId, date);
    final clip = DayClip(spotId: spotId, date: date, video: vName, thumb: tName, createdAt: stamp);
    _clips[clip.id] = clip;
    await _save();
    if (old != null) await _deleteFiles(old);
    notifyListeners();
    return clip;
  }

  Future<void> remove(DayClip c) async {
    _clips.remove(c.id);
    await _save();
    await _deleteFiles(c);
    notifyListeners();
  }

  /// Deletes every clip (spots stay).
  Future<void> clear() async {
    final list = _clips.values.toList();
    _clips.clear();
    await _save();
    for (final c in list) {
      await _deleteFiles(c);
    }
    notifyListeners();
  }

  Future<void> _deleteFiles(DayClip c) async {
    for (final n in [c.video, c.thumb]) {
      if (n.isEmpty) continue;
      final f = fileOf(n);
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> _move(File from, File to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await from.copy(to.path);
      await from.delete();
    }
  }
}
