// On-device check of the native video work (export / frame).
// Needs real clips; run on a simulator or device:
//   flutter test integration_test -d <device> --dart-define=CLIPS=/abs/a.mp4,/abs/b.mp4
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _clips = String.fromEnvironment('CLIPS');
const _out = String.fromEnvironment('OUT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('teiten/media');

  testWidgets('exports one mp4 with dates, and grabs a first frame', (t) async {
    final paths = _clips.split(',').where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) {
      markTestSkipped('pass --dart-define=CLIPS=...');
      return;
    }
    final dir = _out.isNotEmpty ? Directory(_out) : Directory.systemTemp.createTempSync('exp');
    dir.createSync(recursive: true);
    final out = '${dir.path}/export_test.mp4';
    final res = await ch.invokeMethod<String>('export', {
      'clips': [
        for (var i = 0; i < paths.length; i++) {'path': paths[i], 'label': '2026.11.${(i + 1).toString().padLeft(2, '0')} (月)'},
      ],
      'secondsPerClip': 1.0,
      'title': '07:30  窓の外',
      'out': out,
    });
    expect(res, out);
    expect(File(out).lengthSync(), greaterThan(10000));

    final jpg = '${dir.path}/frame_test.jpg';
    expect(await ch.invokeMethod<bool>('frame', {'path': paths.first, 'out': jpg}), isTrue);
    expect(File(jpg).lengthSync(), greaterThan(1000));
  });
}
