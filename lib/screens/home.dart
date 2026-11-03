import 'dart:async';

import 'package:flutter/material.dart';

import '../notifications.dart';
import '../sample_scene.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import 'capture.dart';
import 'player.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.reminders, required this.clock});
  final ClipStore store;
  final HourlyReminders reminders;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late DateTime now = widget.clock();
  Timer? _tick;
  String? selected;
  int promptOffset = 0;

  ClipStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_changed);
    selected = store.all.isEmpty ? kSampleKey : dateKey(now);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = widget.clock();
      if (n.hour != now.hour) promptOffset = 0;
      if (dateKey(n) != dateKey(now) && selected == dateKey(now)) selected = dateKey(n);
      setState(() => now = n);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() => now = widget.clock());
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _tick?.cancel();
    store.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String get today => dateKey(now);
  String get prompt => promptFor(today, now.hour, promptOffset);

  Future<void> _capture() async {
    final slot = DateTime(now.year, now.month, now.day, now.hour);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CaptureScreen(store: store, slot: slot, prompt: prompt),
    ));
    if (saved == true && mounted) {
      setState(() => selected = dateKey(slot));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${two(slot.hour)}:00 のコマを保存しました')),
      );
    }
  }

  void _play(List<HourClip> list, [int start = 0]) {
    if (list.isEmpty) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => PlayerScreen(store: store, clips: list, start: start),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final key = selected ?? today;
    final list = store.day(key);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _header(p),
            const SizedBox(height: 16),
            _hero(),
            const SizedBox(height: 18),
            _days(p),
            if (key == kSampleKey) ...[const SizedBox(height: 14), _sampleBanner(p)],
            const SizedBox(height: 18),
            _dayHead(p, key, list),
            const SizedBox(height: 12),
            _grid(p, key, list),
            const SizedBox(height: 10),
            Text('枠が光っている時間だけ撮れます。過ぎた枠はもう撮れません。',
                style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ),
      ),
    );
  }

  Widget _header(Palette p) => Row(
        children: [
          Text('毎時ログ', style: TextStyle(fontFamily: kDisplay, fontSize: 26, color: p.ink)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.line),
            ),
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: '連続 '),
              TextSpan(
                  text: '${store.streak(now)}',
                  style: TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], color: p.accent, fontWeight: FontWeight.w600)),
              const TextSpan(text: ' 日'),
            ]), style: TextStyle(fontSize: 13, color: p.ink)),
          ),
          IconButton(
            tooltip: '設定',
            icon: Icon(Icons.tune_rounded, color: p.ink),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(store: store, reminders: widget.reminders))),
          ),
        ],
      );

  Widget _hero() {
    final left = 3600 - (now.minute * 60 + now.second);
    final mine = store.at(today, now.hour);
    const white = Colors.white;
    return Container(
      decoration: BoxDecoration(gradient: skyGradient(now.hour), borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [.3, 1],
            colors: [Color(0x00000000), Color(0x59000000)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('${two(now.hour)}:00',
                        style: const TextStyle(fontFamily: kDisplay, fontSize: 84, height: .95, color: white, shadows: [
                          Shadow(blurRadius: 18, color: Color(0x40000000)),
                        ])),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('この枠の残り', style: TextStyle(color: white, fontSize: 12)),
                    Text('${two(left ~/ 60)}:${two(left % 60)}',
                        style: const TextStyle(
                            fontFamily: kMono, fontFamilyFallback: [kBody], color: white, fontSize: 22, fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(color: const Color(0x47000000), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('この1時間のお題',
                        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 11, letterSpacing: 1.2)),
                    Text(prompt, style: const TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                ),
                TextButton(
                  onPressed: () => setState(() => promptOffset++),
                  style: TextButton.styleFrom(
                      foregroundColor: white, backgroundColor: const Color(0x2EFFFFFF), shape: const StadiumBorder()),
                  child: const Text('別のお題', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (mine == null)
              FilledButton.icon(
                onPressed: _capture,
                style: FilledButton.styleFrom(
                  backgroundColor: white,
                  foregroundColor: const Color(0xFF1B1830),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: const StadiumBorder(),
                ),
                icon: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Color(0x40FF3B30), spreadRadius: 4)],
                  ),
                ),
                label: const Text('いまの1コマを撮る', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              )
            else
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 54, height: 54, child: _thumb(mine)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('この枠は撮影済み\n次の枠は ${two((now.hour + 1) % 24)}:00 に開きます',
                      style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                TextButton(
                  onPressed: _capture,
                  style: TextButton.styleFrom(
                      foregroundColor: white, backgroundColor: const Color(0x2EFFFFFF), shape: const StadiumBorder()),
                  child: const Text('撮り直す', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _thumb(HourClip c) => c.isSample
      ? SampleScene(hour: c.hour, kind: c.sampleScene!)
      : Image.file(store.fileOf(c.thumb), fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, _, _) => DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(c.hour))));

  Widget _days(Palette p) {
    final keys = [...store.days(now), kSampleKey];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final k = keys[i];
          final on = k == (selected ?? today);
          final n = store.day(k).length;
          final label = k == kSampleKey ? '見本' : k == today ? '今日' : dayLabel(k);
          return Semantics(
            selected: on,
            button: true,
            child: GestureDetector(
              onTap: () => setState(() => selected = k),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: on ? p.ink : p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? p.ink : p.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: TextStyle(fontSize: 13, color: on ? p.bg : p.ink)),
                  Text('$n コマ',
                      style: TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], fontSize: 11, color: (on ? p.bg : p.muted).withValues(alpha: .8))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sampleBanner(Palette p) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'これは見本の1日です。', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                const TextSpan(text: '撮ったコマは「今日」に入ります。'),
              ]),
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => selected = today),
            child: Text('今日を開く', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _dayHead(Palette p, String key, List<HourClip> list) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(key == kSampleKey ? '見本の1日' : key == today ? '今日' : dayLabel(key),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink)),
            Text('${list.length} / 24 コマ ・ 約${list.length * 2}秒のVlog',
                style: TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], fontSize: 12, color: p.muted)),
          ]),
        ),
        FilledButton.icon(
          onPressed: list.isEmpty ? null : () => _play(list),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.accentInk,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Vlogを再生', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);

  Widget _grid(Palette p, String key, List<HourClip> list) {
    final byHour = {for (final c in list) c.hour: c};
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3 / 4,
      children: [
        for (var h = 0; h < 24; h++) _cell(p, key, h, byHour[h], list),
      ],
    );
  }

  Widget _cell(Palette p, String key, int h, HourClip? c, List<HourClip> list) {
    final isToday = key == today;
    final isNow = isToday && h == now.hour;
    final future = isToday && h > now.hour;
    final label = Positioned(
      left: 7,
      top: 5,
      child: Text(two(h),
          style: const TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white,
              shadows: [Shadow(blurRadius: 4, color: Color(0x66000000))])),
    );
    Widget body;
    VoidCallback? onTap;
    String semantics;
    if (c != null) {
      onTap = () => _play(list, list.indexOf(c));
      semantics = '${two(h)}時のコマ：${c.prompt}';
      body = Stack(fit: StackFit.expand, children: [
        _thumb(c),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [.6, 1],
                colors: [Color(0x00000000), Color(0x73000000)]),
          ),
        ),
        label,
        const Positioned(
          right: 5,
          bottom: 4,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
            Text('2s', style: TextStyle(fontFamily: kMono, fontSize: 10, color: Colors.white)),
          ]),
        ),
      ]);
    } else {
      semantics = isNow ? 'いまの枠で撮る' : '${two(h)}時 ${future ? 'まだ' : '撮影なし'}';
      onTap = isNow ? _capture : null;
      body = Opacity(
        opacity: isNow ? 1 : (future ? .13 : .32),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: skyGradient(h)),
          child: Stack(fit: StackFit.expand, children: [
            label,
            if (isNow) const Center(child: Icon(Icons.add_rounded, color: Colors.white, size: 30)),
          ]),
        ),
      );
    }
    return Semantics(
      label: semantics,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isNow ? Border.all(color: p.accent, width: 2.5) : null,
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(isNow ? 10 : 12), child: body),
        ),
      ),
    );
  }
}
