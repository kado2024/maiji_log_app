// Renders App Store screenshots (6.9" iPhone, 1320x2868) into build/screenshots.
// Run: flutter test test_screenshots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maiji_log/main.dart';
import 'package:maiji_log/model.dart';
import 'package:maiji_log/notifications.dart';
import 'package:maiji_log/sample_scene.dart';
import 'package:maiji_log/screens/archive.dart';
import 'package:maiji_log/screens/compare.dart';
import 'package:maiji_log/screens/player.dart';
import 'package:maiji_log/sky.dart';
import 'package:maiji_log/store.dart';
import 'package:maiji_log/theme.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<String> assets) async {
    final l = FontLoader(family);
    for (final a in assets) {
      l.addFont(rootBundle.load(a));
    }
    await l.load();
  }

  await load(kDisplay, ['assets/fonts/DelaGothicOne-Regular.ttf']);
  await load(kBody, ['assets/fonts/ZenKakuGothicNew-Regular.ttf', 'assets/fonts/ZenKakuGothicNew-Bold.ttf']);
  await load(kMono, ['assets/fonts/IBMPlexMono-SemiBold.ttf']);
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await l.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final ro = tester.binding.renderViews.first.child!;
  final boundary = ro is RenderRepaintBoundary ? ro : tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 3);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screenshots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

final _now = DateTime(2026, 11, 9, 6, 38);

void main() {
  setUpAll(_fonts);

  void phone(WidgetTester t, Brightness b) {
    t.view.physicalSize = const Size(1320, 2868);
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    t.platformDispatcher.platformBrightnessTestValue = b;
  }

  /// Illustrated stand-in frames, one PNG per month.
  Future<Map<int, File>> frames(WidgetTester t, Directory dir) async {
    final out = <int, File>{};
    for (final m in [9, 10, 11]) {
      final key = GlobalKey();
      await t.pumpWidget(Center(
        child: RepaintBoundary(key: key, child: SizedBox(width: 270, height: 480, child: SampleScene(month: m))),
      ));
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await b.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        out[m] = File('${dir.path}/m$m.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    return out;
  }

  /// "06:30 窓の外" recorded most days since September, plus a second spot.
  Future<(SpotStore, Spot)> seeded(WidgetTester t) async {
    final dir = Directory.systemTemp.createTempSync('shots');
    final f = await frames(t, dir);
    final s = SpotStore(root: dir);
    late Spot window;
    await t.runAsync(() async {
      await s.load();
      window = await s.addSpot(name: '窓の外', minute: 6 * 60 + 30);
      await s.addSpot(name: '寝る前の机の上', minute: 22 * 60);
      var i = 0;
      for (var d = DateTime(2026, 9, 1); !d.isAfter(_now); d = DateTime(d.year, d.month, d.day + 1)) {
        i++;
        if (i % 9 == 4) continue; // a few missed days
        final v = File('${dir.path}/v$i.mov')..writeAsBytesSync([0]);
        final th = File('${dir.path}/t$i.png');
        f[d.month]!.copySync(th.path);
        await s.add(spotId: window.id, date: dateKey(d), video: v, thumb: th);
      }
    });
    return (s, window);
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 50));
    // File images decode on real async I/O; give them a few real turns.
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app(Widget home, Brightness b) => RepaintBoundary(
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home),
      );

  for (final b in [Brightness.light, Brightness.dark]) {
    final tag = b == Brightness.light ? 'light' : 'dark';
    testWidgets('home $tag', (t) async {
      phone(t, b);
      final (s, _) = await seeded(t);
      await t.pumpWidget(RepaintBoundary(child: OnajiApp(store: s, reminders: SpotReminders(), clock: () => _now)));
      await settle(t);
      await _shot(t, '1_home_$tag');
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('archive', (t) async {
    phone(t, Brightness.light);
    final (s, w) = await seeded(t);
    await t.pumpWidget(app(ArchiveScreen(store: s, spotId: w.id, clock: () => _now), Brightness.light));
    await settle(t);
    await _shot(t, '2_archive');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('player', (t) async {
    phone(t, Brightness.dark);
    final (s, w) = await seeded(t);
    final clips = s.clipsOf(w.id);
    await t.pumpWidget(app(PlayerScreen(store: s, spot: w, clips: clips, start: 33, autoplay: false), Brightness.dark));
    await settle(t);
    await _shot(t, '3_player');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('compare', (t) async {
    phone(t, Brightness.light);
    final (s, w) = await seeded(t);
    await t.pumpWidget(app(CompareScreen(store: s, spot: w, clips: s.clipsOf(w.id)), Brightness.light));
    await settle(t);
    await _shot(t, '4_compare');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sample year', (t) async {
    phone(t, Brightness.dark);
    final dir = Directory.systemTemp.createTempSync('shots');
    final s = SpotStore(root: dir);
    await t.runAsync(s.load);
    await t.pumpWidget(app(
        PlayerScreen(store: s, spot: kSampleSpot, clips: s.clipsOf(kSampleSpot.id), start: 3, autoplay: false),
        Brightness.dark));
    await settle(t);
    await _shot(t, '5_sample');
    await t.pumpWidget(const SizedBox());
  });
}
