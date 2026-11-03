// Renders App Store screenshots (6.9" iPhone, 1320x2868) into build/screenshots.
// Run: flutter test test_screenshots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maiji_log/main.dart';
import 'package:maiji_log/notifications.dart';
import 'package:maiji_log/screens/player.dart';
import 'package:maiji_log/screens/settings.dart';
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

void main() {
  setUpAll(_fonts);

  Future<ClipStore> store(WidgetTester t) async {
    final dir = Directory.systemTemp.createTempSync('shots');
    final s = ClipStore(root: dir);
    await t.runAsync(s.load);
    return s;
  }

  void phone(WidgetTester t, Brightness b) {
    t.view.physicalSize = const Size(1320, 2868);
    t.view.devicePixelRatio = 3;
    t.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    t.platformDispatcher.platformBrightnessTestValue = b;
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    final tag = b == Brightness.light ? 'light' : 'dark';
    testWidgets('home $tag', (t) async {
      phone(t, b);
      final s = await store(t);
      await t.pumpWidget(RepaintBoundary(
        child: MaijiLogApp(store: s, reminders: HourlyReminders(), clock: () => DateTime(2026, 11, 3, 17, 24, 10)),
      ));
      await t.pump(const Duration(milliseconds: 100));
      await _shot(t, '1_home_$tag');
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('player', (t) async {
    phone(t, Brightness.dark);
    final s = await store(t);
    await t.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        home: PlayerScreen(store: s, clips: s.day(kSampleKey), start: 6, autoplay: false),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await _shot(t, '2_player');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('settings', (t) async {
    phone(t, Brightness.light);
    final s = await store(t);
    final r = HourlyReminders()..enabled = true;
    await t.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: SettingsScreen(store: s, reminders: r),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await _shot(t, '3_settings');
    await t.pumpWidget(const SizedBox());
  });
}
