import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'sky.dart';

/// One 2-second clip recorded in a specific hour slot.
class HourClip {
  final String date; // yyyy-MM-dd
  final int hour;
  final String video; // file name inside the clips folder
  final String thumb; // file name inside the clips folder
  final String prompt;
  final int createdAt;
  final String? sampleScene; // set only for the built-in sample day

  const HourClip({
    required this.date,
    required this.hour,
    required this.video,
    required this.thumb,
    required this.prompt,
    required this.createdAt,
    this.sampleScene,
  });

  String get id => '${date}_${two(hour)}';
  bool get isSample => sampleScene != null;

  Map<String, dynamic> toJson() => {
        'date': date,
        'hour': hour,
        'video': video,
        'thumb': thumb,
        'prompt': prompt,
        'createdAt': createdAt,
      };

  factory HourClip.fromJson(Map<String, dynamic> j) => HourClip(
        date: j['date'] as String,
        hour: j['hour'] as int,
        video: j['video'] as String,
        thumb: j['thumb'] as String,
        prompt: (j['prompt'] as String?) ?? '',
        createdAt: (j['createdAt'] as int?) ?? 0,
      );
}

const kSampleKey = 'sample';
const kStreakMin = 3;

const _samplePlan = [
  (7, '朝いちばんの光', 'sun'),
  (8, '通学路の景色', 'road'),
  (10, '手元のノート', 'note'),
  (12, '今日のお昼ごはん', 'bowl'),
  (13, '窓からの景色', 'window'),
  (15, 'おやつ', 'cup'),
  (17, '空がオレンジになる瞬間', 'sunset'),
  (19, '晩ごはん', 'bowl'),
  (21, '今日の部屋の様子', 'lamp'),
  (23, '布団に入る直前', 'moon'),
];

final List<HourClip> sampleClips = [
  for (final (h, p, k) in _samplePlan)
    HourClip(date: kSampleKey, hour: h, video: '', thumb: '', prompt: p, createdAt: 0, sampleScene: k),
];

/// Keeps every clip on the device only (app Documents/clips + index.json).
/// File names are stored relative to the folder, because the absolute
/// container path on iOS changes between app updates.
class ClipStore extends ChangeNotifier {
  ClipStore({Directory? root}) : _rootOverride = root;
  final Directory? _rootOverride;
  late Directory _dir;
  final Map<String, HourClip> _clips = {};
  bool ready = false;

  Directory get dir => _dir;
  File fileOf(String name) => File('${_dir.path}/$name');
  File get _index => fileOf('index.json');

  Future<void> load() async {
    final root = _rootOverride ?? await getApplicationDocumentsDirectory();
    _dir = Directory('${root.path}/clips');
    await _dir.create(recursive: true);
    if (await _index.exists()) {
      try {
        final list = jsonDecode(await _index.readAsString()) as List;
        for (final j in list) {
          final c = HourClip.fromJson(Map<String, dynamic>.from(j as Map));
          if (await fileOf(c.video).exists()) _clips[c.id] = c;
        }
      } catch (e) {
        debugPrint('index read failed: $e');
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final tmp = fileOf('index.json.tmp');
    await tmp.writeAsString(jsonEncode(_clips.values.map((c) => c.toJson()).toList()));
    await tmp.rename(_index.path);
  }

  List<HourClip> get all => _clips.values.toList();

  List<HourClip> day(String key) {
    final list = key == kSampleKey
        ? List<HourClip>.of(sampleClips)
        : _clips.values.where((c) => c.date == key).toList();
    list.sort((a, b) => a.hour.compareTo(b.hour));
    return list;
  }

  HourClip? at(String date, int hour) => _clips['${date}_${two(hour)}'];

  /// Days that have clips, newest first, always including today.
  List<String> days(DateTime now) {
    final s = <String>{dateKey(now), ..._clips.values.map((c) => c.date)};
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Moves the recorded files into the store and replaces any clip in the slot.
  Future<HourClip> add({
    required DateTime slot,
    required File video,
    required File thumb,
    required String prompt,
  }) async {
    final date = dateKey(slot);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = '${date}_${two(slot.hour)}_$stamp';
    final vExt = video.path.contains('.') ? video.path.split('.').last : 'mov';
    final vName = '$base.$vExt';
    final tName = '$base.jpg';
    await _move(video, fileOf(vName));
    await _move(thumb, fileOf(tName));
    final old = at(date, slot.hour);
    final clip = HourClip(date: date, hour: slot.hour, video: vName, thumb: tName, prompt: prompt, createdAt: stamp);
    _clips[clip.id] = clip;
    await _save();
    if (old != null) await _deleteFiles(old);
    notifyListeners();
    return clip;
  }

  Future<void> remove(HourClip c) async {
    _clips.remove(c.id);
    await _save();
    await _deleteFiles(c);
    notifyListeners();
  }

  Future<void> clear() async {
    final list = _clips.values.toList();
    _clips.clear();
    await _save();
    for (final c in list) {
      await _deleteFiles(c);
    }
    notifyListeners();
  }

  Future<void> _deleteFiles(HourClip c) async {
    for (final n in [c.video, c.thumb]) {
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

  /// Consecutive days with at least [kStreakMin] clips, ending today
  /// (or yesterday, while today is still in progress).
  int streak(DateTime now) {
    final counts = <String, int>{};
    for (final c in _clips.values) {
      counts[c.date] = (counts[c.date] ?? 0) + 1;
    }
    var d = DateTime(now.year, now.month, now.day);
    if ((counts[dateKey(d)] ?? 0) < kStreakMin) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while ((counts[dateKey(d)] ?? 0) >= kStreakMin) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }
}
