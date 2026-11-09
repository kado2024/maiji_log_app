import 'package:flutter/material.dart';

/// Sky colors for each hour of the day (top-left, bottom-right).
const List<List<Color>> kSky = [
  [Color(0xFF0B1033), Color(0xFF28245A)],
  [Color(0xFF0A0E2C), Color(0xFF231F52)],
  [Color(0xFF0A0D29), Color(0xFF1F1C4B)],
  [Color(0xFF0C1030), Color(0xFF2A2457)],
  [Color(0xFF1A1B45), Color(0xFF4B3A6E)],
  [Color(0xFF3B3F7A), Color(0xFFD97B6C)],
  [Color(0xFF5B6FB0), Color(0xFFF4A27A)],
  [Color(0xFF6F9FD8), Color(0xFFF7C58F)],
  [Color(0xFF78B4E6), Color(0xFFCFE6F2)],
  [Color(0xFF5AA8E8), Color(0xFFBFE3F7)],
  [Color(0xFF4AA0E6), Color(0xFFA9DCF7)],
  [Color(0xFF3F98E3), Color(0xFF9FD6F5)],
  [Color(0xFF3A93E0), Color(0xFF99D2F3)],
  [Color(0xFF3F96DE), Color(0xFFA2D3F1)],
  [Color(0xFF4A9AD9), Color(0xFFB3D6EA)],
  [Color(0xFF5A98CF), Color(0xFFE3CFA2)],
  [Color(0xFF6D8CC0), Color(0xFFF2B277)],
  [Color(0xFF6B6AA8), Color(0xFFF48A5C)],
  [Color(0xFF4A3F86), Color(0xFFE8684F)],
  [Color(0xFF2D2A68), Color(0xFFA54B6B)],
  [Color(0xFF1D1D52), Color(0xFF5B3A72)],
  [Color(0xFF15164A), Color(0xFF3D2E66)],
  [Color(0xFF10123D), Color(0xFF30275E)],
  [Color(0xFF0C0F35), Color(0xFF2A245A)],
];

/// Sky colors at a fractional hour (e.g. 7.5 = 7:30), blended between hours.
List<Color> skyAt(double hour) {
  final h = hour % 24;
  final a = h.floor() % 24, b = (a + 1) % 24;
  final t = h - h.floor();
  return [Color.lerp(kSky[a][0], kSky[b][0], t)!, Color.lerp(kSky[a][1], kSky[b][1], t)!];
}

LinearGradient skyGradient(num hour) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: skyAt(hour.toDouble()),
    );

String two(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

const _wd = '月火水木金土日';
String weekdayOf(DateTime d) => _wd[d.weekday - 1];

/// "11/9(月)"
String dayLabel(String key) {
  final d = parseDateKey(key);
  return '${d.month}/${d.day}(${weekdayOf(d)})';
}

/// "2026.11.09 (月)" — the label burned into exported videos.
String longDayLabel(String key) {
  final d = parseDateKey(key);
  return '${d.year}.${two(d.month)}.${two(d.day)} (${weekdayOf(d)})';
}

/// "08:05" for minutes since midnight.
String clockLabel(int minuteOfDay) => '${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
