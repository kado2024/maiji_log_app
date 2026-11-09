import 'model.dart';
import 'sky.dart';

/// A spot can be recorded from [kOpenBefore] before its time
/// until [kOpenAfter] after it. Outside that window it is closed,
/// so every frame in the archive really is "the same time".
const kOpenBefore = Duration(minutes: 15);
const kOpenAfter = Duration(minutes: 45);

DateTime spotTimeOn(Spot s, DateTime day) => DateTime(day.year, day.month, day.day, s.hour, s.minute % 60);

/// The capture window that [now] falls into, if any.
class SlotWindow {
  final String date; // the day this window belongs to
  final DateTime opens, at, closes;
  const SlotWindow(this.date, this.opens, this.at, this.closes);

  bool contains(DateTime t) => !t.isBefore(opens) && t.isBefore(closes);
}

SlotWindow windowOn(Spot s, DateTime day) {
  final at = spotTimeOn(s, day);
  return SlotWindow(dateKey(day), at.subtract(kOpenBefore), at, at.add(kOpenAfter));
}

/// The open window for [s] at [now], checking yesterday/today/tomorrow so
/// windows that cross midnight (e.g. 23:50 → 00:35) still work.
SlotWindow? openWindow(Spot s, DateTime now) {
  for (final d in [-1, 0, 1]) {
    final w = windowOn(s, DateTime(now.year, now.month, now.day + d));
    if (w.contains(now)) return w;
  }
  return null;
}

/// The next time the window opens after [now].
SlotWindow nextWindow(Spot s, DateTime now) {
  for (final d in [0, 1, 2]) {
    final w = windowOn(s, DateTime(now.year, now.month, now.day + d));
    if (w.opens.isAfter(now)) return w;
  }
  throw StateError('unreachable');
}

/// "あと2時間5分" / "あと12分"
String untilLabel(DateTime now, DateTime t) {
  final m = (t.difference(now).inSeconds / 60).ceil();
  if (m >= 60) return 'あと${m ~/ 60}時間${m % 60 == 0 ? '' : '${m % 60}分'}';
  return 'あと$m分';
}

/// Consecutive days with a clip, ending at the latest day whose window has
/// already started (today if it is open/past, otherwise yesterday).
int streakOf(Spot s, Set<String> dates, DateTime now) {
  var d = DateTime(now.year, now.month, now.day);
  if (!dates.contains(dateKey(d))) {
    // Today does not count against the streak until today's window closes.
    if (now.isBefore(windowOn(s, d).closes)) d = DateTime(d.year, d.month, d.day - 1);
  }
  var n = 0;
  while (dates.contains(dateKey(d))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// Archive ranges for playback and export.
enum Span {
  week('1週間', 7),
  month('1か月', 31),
  quarter('3か月', 92),
  all('すべて', 0);

  const Span(this.label, this.days);
  final String label;
  final int days;
}

/// Clips (sorted by date) that fall into [span], counted back from [now].
List<DayClip> clipsIn(List<DayClip> sorted, Span span, DateTime now) {
  if (span == Span.all) return sorted;
  final from = dateKey(DateTime(now.year, now.month, now.day - span.days + 1));
  return sorted.where((c) => c.date.compareTo(from) >= 0).toList();
}

/// Seconds each day is shown for in playback/export.
const kSpeeds = [2.0, 1.0, 0.5];
String speedLabel(double s) => s >= 1 ? '1日${s.toStringAsFixed(0)}秒' : '1日$s秒';
