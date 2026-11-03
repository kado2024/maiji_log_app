import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maiji_log/main.dart';
import 'package:maiji_log/notifications.dart';
import 'package:maiji_log/sky.dart';
import 'package:maiji_log/store.dart';

Future<ClipStore> _store(Directory root) async {
  final s = ClipStore(root: root);
  await s.load();
  return s;
}

Future<HourClip> _addClip(ClipStore s, Directory tmp, DateTime slot) async {
  final v = File('${tmp.path}/v${slot.millisecondsSinceEpoch}.mov')..writeAsBytesSync([1, 2, 3]);
  final t = File('${tmp.path}/t${slot.millisecondsSinceEpoch}.jpg')..writeAsBytesSync([4, 5, 6]);
  return s.add(slot: slot, video: v, thumb: t, prompt: 'test');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('maiji'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('prompts are stable per day and hour', () {
    expect(promptFor('2026-11-03', 9), promptFor('2026-11-03', 9));
    expect(promptFor('2026-11-03', 9, 1), isNot(promptFor('2026-11-03', 9)));
  });

  test('clips persist, replace their slot, and survive reload', () async {
    final s = await _store(tmp);
    final slot = DateTime(2026, 11, 3, 9);
    final first = await _addClip(s, tmp, slot);
    final second = await _addClip(s, tmp, slot);
    expect(s.day('2026-11-03'), hasLength(1));
    expect(s.fileOf(first.video).existsSync(), isFalse, reason: 'retake deletes the old file');
    expect(s.fileOf(second.video).existsSync(), isTrue);

    final reloaded = await _store(tmp);
    expect(reloaded.at('2026-11-03', 9)?.video, second.video);

    await reloaded.clear();
    expect(reloaded.all, isEmpty);
    expect(reloaded.fileOf(second.video).existsSync(), isFalse);
  });

  test('streak counts days with 3+ clips, today still in progress', () async {
    final s = await _store(tmp);
    for (final day in [1, 2]) {
      for (final h in [8, 12, 20]) {
        await _addClip(s, tmp, DateTime(2026, 11, day, h));
      }
    }
    await _addClip(s, tmp, DateTime(2026, 11, 3, 9)); // today: only 1 so far
    expect(s.streak(DateTime(2026, 11, 3, 10)), 2);
    for (final h in [10, 11]) {
      await _addClip(s, tmp, DateTime(2026, 11, 3, h));
    }
    expect(s.streak(DateTime(2026, 11, 3, 12)), 3);
    expect(s.streak(DateTime(2026, 11, 5, 12)), 0, reason: 'a missed day breaks the streak');
  });

  testWidgets('first launch shows the sample day and the current slot', (tester) async {
    final s = await tester.runAsync(() => _store(tmp));
    await tester.pumpWidget(MaijiLogApp(
      store: s!,
      reminders: HourlyReminders(),
      clock: () => DateTime(2026, 11, 3, 14, 20),
    ));
    await tester.pump();
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('見本の1日'), findsOneWidget);
    expect(find.text('いまの1コマを撮る'), findsOneWidget);
    expect(find.text('10 / 24 コマ ・ 約20秒のVlog'), findsOneWidget);

    await tester.tap(find.text('今日を開く'));
    await tester.pump();
    expect(find.text('0 / 24 コマ ・ 約0秒のVlog'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
