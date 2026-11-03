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

LinearGradient skyGradient(int hour) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: kSky[hour % 24],
    );

const Map<String, List<String>> _prompts = {
  'night': ['眠れない夜の天井', '枕元のスマホの明かり', '夜中の冷蔵庫', '窓の外の暗さ', '静かな部屋の音'],
  'morning': ['朝いちばんの光', '今朝の朝ごはん', '鏡の前の寝ぐせ', '玄関を出た瞬間', '通学路・通勤路の景色', '空の色'],
  'midday': ['いま見ている画面', '手元のノート', '今日のお昼ごはん', '友だちの笑い声', '足元の影', 'いま飲んでいるもの', '窓からの景色'],
  'afternoon': ['午後の眠気', 'おやつ', '帰り道', '空がオレンジになる瞬間', '今日いちばん歩いた場所', '好きな音楽を流してるところ'],
  'evening': ['晩ごはん', 'お風呂上がり', '今日の部屋の様子', '明日の準備', '最後に見た空', '布団に入る直前'],
};

String _bucket(int h) => h < 5
    ? 'night'
    : h < 10
        ? 'morning'
        : h < 14
            ? 'midday'
            : h < 18
                ? 'afternoon'
                : 'evening';

int _hash(String s) {
  var x = 2166136261;
  for (final c in s.codeUnits) {
    x ^= c;
    x = (x * 16777619) & 0xFFFFFFFF;
  }
  return x;
}

/// A stable prompt for a given day and hour; [offset] picks another one.
String promptFor(String dateKey, int hour, [int offset = 0]) {
  final list = _prompts[_bucket(hour)]!;
  return list[(_hash('$dateKey:$hour') + offset) % list.length];
}

String two(int n) => n.toString().padLeft(2, '0');

String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

const _wd = '月火水木金土日';
String dayLabel(String key) {
  final p = key.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return '${d.month}/${d.day}(${_wd[d.weekday - 1]})';
}
