import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maiji_log/exporter.dart';
import 'package:maiji_log/main.dart';
import 'package:maiji_log/model.dart';
import 'package:maiji_log/notifications.dart';
import 'package:maiji_log/sample_scene.dart';
import 'package:maiji_log/schedule.dart';
import 'package:maiji_log/screens/archive.dart';
import 'package:maiji_log/screens/player.dart';
import 'package:maiji_log/sky.dart';
import 'package:maiji_log/store.dart';

Future<SpotStore> _store(Directory root) async {
  final s = SpotStore(root: root);
  await s.load();
  return s;
}

int _n = 0;
Future<DayClip> _addClip(SpotStore s, Directory tmp, int spotId, String date, {bool thumb = true}) async {
  _n++;
  final v = File('${tmp.path}/v$_n.mov')..writeAsBytesSync([1, 2, 3]);
  final t = thumb ? (File('${tmp.path}/t$_n.jpg')..writeAsBytesSync([4, 5, 6])) : null;
  return s.add(spotId: spotId, date: date, video: v, thumb: t);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('onaji'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('schedule', () {
    const s = Spot(id: 1, name: '窓の外', minute: 7 * 60 + 30);

    test('window is open from 15 min before to 45 min after the time', () {
      expect(openWindow(s, DateTime(2026, 11, 9, 7, 14)), isNull);
      expect(openWindow(s, DateTime(2026, 11, 9, 7, 15))?.date, '2026-11-09');
      expect(openWindow(s, DateTime(2026, 11, 9, 8, 14))?.date, '2026-11-09');
      expect(openWindow(s, DateTime(2026, 11, 9, 8, 15)), isNull);
    });

    test('windows that cross midnight belong to the day of the time', () {
      const late = Spot(id: 2, name: '寝る前', minute: 23 * 60 + 50);
      expect(openWindow(late, DateTime(2026, 11, 10, 0, 20))?.date, '2026-11-09');
      const early = Spot(id: 3, name: '夜明け', minute: 5);
      expect(openWindow(early, DateTime(2026, 11, 9, 23, 55))?.date, '2026-11-10');
    });

    test('next window and countdown label', () {
      final now = DateTime(2026, 11, 9, 9, 0);
      final next = nextWindow(s, now);
      expect(next.date, '2026-11-10');
      expect(next.opens, DateTime(2026, 11, 10, 7, 15));
      expect(untilLabel(now, next.opens), 'あと22時間15分');
      expect(untilLabel(now, DateTime(2026, 11, 9, 9, 12)), 'あと12分');
      expect(untilLabel(now, DateTime(2026, 11, 9, 11, 0)), 'あと2時間');
    });

    test('streak: today does not break it until today\'s window closes', () {
      final dates = {'2026-11-06', '2026-11-07', '2026-11-08'};
      expect(streakOf(s, dates, DateTime(2026, 11, 9, 6, 0)), 3, reason: 'before the window');
      expect(streakOf(s, dates, DateTime(2026, 11, 9, 8, 0)), 3, reason: 'window still open');
      expect(streakOf(s, dates, DateTime(2026, 11, 9, 9, 0)), 0, reason: 'missed today');
      expect(streakOf(s, {...dates, '2026-11-09'}, DateTime(2026, 11, 9, 9, 0)), 4);
    });

    test('spans pick the most recent days', () {
      final clips = [
        for (final d in ['2026-08-01', '2026-10-20', '2026-11-03', '2026-11-09'])
          DayClip(spotId: 1, date: d, video: 'v', thumb: '', createdAt: 0),
      ];
      final now = DateTime(2026, 11, 9, 12);
      expect(clipsIn(clips, Span.week, now).map((c) => c.date), ['2026-11-03', '2026-11-09']);
      expect(clipsIn(clips, Span.month, now), hasLength(3));
      expect(clipsIn(clips, Span.all, now), hasLength(4));
    });

    test('labels', () {
      expect(clockLabel(7 * 60 + 5), '07:05');
      expect(dayLabel('2026-11-09'), '11/9(月)');
      expect(longDayLabel('2026-11-09'), '2026.11.09 (月)');
      expect(speedLabel(0.5), '1日0.5秒');
      expect(speedLabel(2), '1日2秒');
    });
  });

  group('store', () {
    test('spots: at most three, sorted by time, persisted', () async {
      final s = await _store(tmp);
      await s.addSpot(name: '夜の机', minute: 22 * 60);
      await s.addSpot(name: '  ', minute: 7 * 60);
      await s.addSpot(name: '昼', minute: 12 * 60);
      expect(s.canAddSpot, isFalse);
      expect(() => s.addSpot(name: 'x', minute: 0), throwsStateError);
      expect(s.spots.map((x) => x.minute), [420, 720, 1320]);
      expect(s.spots.first.name, '定点2', reason: 'blank name gets a default');

      final reloaded = await _store(tmp);
      expect(reloaded.spots.map((x) => x.name), s.spots.map((x) => x.name));
    });

    test('one clip per spot and day; retake replaces; reload keeps it', () async {
      final s = await _store(tmp);
      final spot = await s.addSpot(name: '窓', minute: 450);
      final first = await _addClip(s, tmp, spot.id, '2026-11-09');
      final second = await _addClip(s, tmp, spot.id, '2026-11-09');
      expect(s.clipsOf(spot.id), hasLength(1));
      expect(s.fileOf(first.video).existsSync(), isFalse, reason: 'retake deletes the old file');
      expect(s.fileOf(second.thumb).existsSync(), isTrue);

      final reloaded = await _store(tmp);
      expect(reloaded.at(spot.id, '2026-11-09')?.video, second.video);
    });

    test('previous frame is the latest earlier day with a still', () async {
      final s = await _store(tmp);
      final spot = await s.addSpot(name: '窓', minute: 450);
      await _addClip(s, tmp, spot.id, '2026-11-05');
      await _addClip(s, tmp, spot.id, '2026-11-07', thumb: false);
      await _addClip(s, tmp, spot.id, '2026-11-09');
      expect(s.previousFrame(spot.id, '2026-11-09')?.date, '2026-11-05');
      expect(s.previousFrame(spot.id, '2026-11-05'), isNull);
    });

    test('removing a spot deletes its clips only', () async {
      final s = await _store(tmp);
      final a = await s.addSpot(name: 'a', minute: 400);
      final b = await s.addSpot(name: 'b', minute: 800);
      final ca = await _addClip(s, tmp, a.id, '2026-11-09');
      final cb = await _addClip(s, tmp, b.id, '2026-11-09');
      await s.removeSpot(a.id);
      expect(s.spots.map((x) => x.id), [b.id]);
      expect(s.fileOf(ca.video).existsSync(), isFalse);
      expect(s.fileOf(cb.video).existsSync(), isTrue);
      await s.clear();
      expect(s.all, isEmpty);
      expect(s.spots, hasLength(1), reason: 'clear keeps spots');
    });

    test('hourly prototype data is dropped', () async {
      final legacy = Directory('${tmp.path}/clips')..createSync();
      File('${legacy.path}/index.json').writeAsStringSync('[]');
      final s = await _store(tmp);
      expect(legacy.existsSync(), isFalse);
      expect(s.spots, isEmpty);
    });

    test('sample is a year of the same 6:30 window', () async {
      final s = await _store(tmp);
      final sample = s.clipsOf(kSampleSpot.id);
      expect(sample, hasLength(12));
      expect(sample.every((c) => c.isSample), isTrue);
      expect(sunriseFor(1), greaterThan(sunriseFor(6)));
      expect(sampleSkyHour(6), greaterThan(sampleSkyHour(12)), reason: 'brighter at 6:30 in summer');
    });
  });

  group('export + reminders', () {
    test('export arguments carry each day\'s date label', () async {
      final s = await _store(tmp);
      final spot = await s.addSpot(name: '窓の外', minute: 450);
      final c1 = await _addClip(s, tmp, spot.id, '2026-11-08');
      final c2 = await _addClip(s, tmp, spot.id, '2026-11-09');
      final args = SequenceExporter.exportArgs(store: s, spot: spot, clips: [c1, c2], secondsPerClip: .5, outPath: '/o.mp4');
      expect(args['title'], '07:30  窓の外');
      expect(args['secondsPerClip'], .5);
      final list = args['clips'] as List;
      expect((list.last as Map)['label'], '2026.11.09 (月)');
      expect((list.first as Map)['path'], s.fileOf(c1.video).path);
      expect(exportFileName(spot, [c1, c2]), 'onaji_0730_20261108_20261109.mp4');
    });

    test('exporter talks to the native channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const ch = MethodChannel('teiten/media');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls.add(call);
        return switch (call.method) { 'export' => '/done.mp4', 'saveToPhotos' => true, _ => false };
      });
      final s = await _store(tmp);
      final spot = await s.addSpot(name: '窓', minute: 450);
      final c = await _addClip(s, tmp, spot.id, '2026-11-09');
      const ex = SequenceExporter();
      expect(await ex.export(store: s, spot: spot, clips: [c], secondsPerClip: 1, outPath: '/o.mp4'), '/done.mp4');
      expect(await ex.saveToPhotos('/done.mp4'), isTrue);
      expect(await ex.frame('/v.mov', '/v.jpg'), isFalse);
      expect(calls.map((c) => c.method), ['export', 'saveToPhotos', 'frame']);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
    });

    test('reminder text names the time and the subject', () {
      final t = reminderText(const Spot(id: 1, name: '窓の外', minute: 450));
      expect(t.title, '07:30「窓の外」の時間です');
      expect(t.body, contains('前回と同じ構図'));
    });
  });

  group('screens', () {
    Future<void> pumpApp(WidgetTester tester, SpotStore s, DateTime now) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(OnajiApp(store: s, reminders: SpotReminders(), clock: () => now));
      await tester.pump();
    }

    testWidgets('first launch: pick a time, see the sample', (tester) async {
      final s = (await tester.runAsync(() => _store(tmp)))!;
      await pumpApp(tester, s, DateTime(2026, 11, 9, 9));
      expect(find.text('おなじ時刻'), findsOneWidget);
      expect(find.text('最初の定点時刻を決める'), findsOneWidget);
      expect(find.text('毎朝 6:30 の窓・12か月'), findsOneWidget);
      expect(find.textContaining('Vlog'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('spot card: open window offers capture, closed shows countdown', (tester) async {
      final s = (await tester.runAsync(() async {
        final s = await _store(tmp);
        await s.addSpot(name: '窓の外', minute: 450);
        return s;
      }))!;
      await pumpApp(tester, s, DateTime(2026, 11, 9, 7, 40));
      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('いま撮る'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await pumpApp(tester, s, DateTime(2026, 11, 9, 9, 0));
      expect(find.text('いま撮る'), findsNothing);
      expect(find.textContaining('次は 11/10(火) 07:30'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('archive shows the calendar and play/export actions', (tester) async {
      final (s, spot) = (await tester.runAsync(() async {
        final s = await _store(tmp);
        final spot = await s.addSpot(name: '窓の外', minute: 450);
        for (final d in ['2026-11-07', '2026-11-08', '2026-11-09']) {
          await _addClip(s, tmp, spot.id, d, thumb: false);
        }
        return (s, spot);
      }))!;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: ArchiveScreen(store: s, spotId: spot.id, clock: () => DateTime(2026, 11, 9, 9))));
      await tester.pump();
      expect(find.text('3日分の変化を再生'), findsOneWidget);
      expect(find.text('日付入り動画に書き出す'), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      await tester.tap(find.text('1週間'));
      await tester.pump();
      expect(find.text('3日分の変化を再生'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('player steps through the sample year', (tester) async {
      final s = (await tester.runAsync(() => _store(tmp)))!;
      await tester.pumpWidget(MaterialApp(
          home: PlayerScreen(store: s, spot: kSampleSpot, clips: s.clipsOf(kSampleSpot.id), autoplay: false)));
      await tester.pump();
      expect(find.text('1 / 12'), findsOneWidget);
      expect(find.text('1月'), findsOneWidget);
      await tester.tapAt(const Offset(700, 300));
      await tester.pump();
      expect(find.text('2 / 12'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
