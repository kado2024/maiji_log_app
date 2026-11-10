import 'package:flutter/services.dart';

import 'model.dart';
import 'sky.dart';
import 'store.dart';

/// Talks to the native (AVFoundation) side in ios/Runner/AppDelegate.swift.
/// The native side concatenates the clips, burns the date of each day
/// into the frames, writes one H.264 .mp4, and can save it to Photos.
class SequenceExporter {
  const SequenceExporter([this.channel = const MethodChannel('teiten/media')]);
  final MethodChannel channel;

  /// Arguments for the native "export" call.
  static Map<String, Object> exportArgs({
    required SpotStore store,
    required Spot spot,
    required List<DayClip> clips,
    required double secondsPerClip,
    required String outPath,
  }) =>
      {
        'clips': [
          for (final c in clips) {'path': store.fileOf(c.video).path, 'label': longDayLabel(c.date)},
        ],
        'secondsPerClip': secondsPerClip,
        'title': '${spot.timeLabel}  ${spot.name}',
        'out': outPath,
      };

  /// Returns the path of the written .mp4.
  Future<String> export({
    required SpotStore store,
    required Spot spot,
    required List<DayClip> clips,
    required double secondsPerClip,
    required String outPath,
  }) async {
    final args = exportArgs(store: store, spot: spot, clips: clips, secondsPerClip: secondsPerClip, outPath: outPath);
    final path = await channel.invokeMethod<String>('export', args);
    return path ?? outPath;
  }

  /// Saves a video to the Photos library (add-only permission). Returns false if denied.
  Future<bool> saveToPhotos(String path) async =>
      await channel.invokeMethod<bool>('saveToPhotos', {'path': path}) ?? false;

  /// Writes a JPEG of the first frame of [videoPath] (orientation applied).
  /// Returns false if the platform could not make one.
  Future<bool> frame(String videoPath, String outPath) async {
    try {
      return await channel.invokeMethod<bool>('frame', {'path': videoPath, 'out': outPath}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

String exportFileName(Spot spot, List<DayClip> clips) {
  final first = clips.first.date.replaceAll('-', ''), last = clips.last.date.replaceAll('-', '');
  return 'onaji_${two(spot.hour)}${two(spot.minute % 60)}_${first}_$last.mp4';
}
