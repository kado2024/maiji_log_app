import 'dart:async';

import 'package:flutter/material.dart';

import '../model.dart';
import '../notifications.dart';
import '../schedule.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'archive.dart';
import 'capture.dart';
import 'player.dart';
import 'settings.dart';
import 'spot_edit.dart';

const kAppName = 'おなじ時刻';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.reminders, required this.clock});
  final SpotStore store;
  final SpotReminders reminders;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late DateTime now = widget.clock();
  Timer? _tick;

  SpotStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => now = widget.clock()));
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

  Future<void> _capture(Spot s, SlotWindow w) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CaptureScreen(store: store, spot: s, date: w.date),
    ));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${dayLabel(w.date)} ${s.timeLabel} の「${s.name}」を保存しました')),
      );
    }
  }

  void _open(Spot s) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArchiveScreen(store: store, spotId: s.id, clock: widget.clock)));

  Future<void> _add() async {
    await editSpot(context, store: store, now: now);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final spots = store.spots;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _header(p),
            const SizedBox(height: 6),
            Text('毎日おなじ時刻に、おなじ場所を2秒だけ。\n並べると、季節と暮らしの変化が見えてきます。',
                style: TextStyle(fontSize: 13, height: 1.6, color: p.muted)),
            const SizedBox(height: 16),
            for (final s in spots) ...[_SpotCard(store: store, spot: s, now: now, onCapture: _capture, onOpen: _open), const SizedBox(height: 14)],
            if (store.canAddSpot) _addButton(p, spots.isEmpty),
            const SizedBox(height: 22),
            Text('見本', style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: p.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _sampleCard(p),
          ],
        ),
      ),
    );
  }

  Widget _header(Palette p) => Row(children: [
        Text(kAppName, style: TextStyle(fontFamily: kDisplay, fontSize: 26, color: p.ink)),
        const Spacer(),
        IconButton(
          tooltip: '設定',
          icon: Icon(Icons.tune_rounded, color: p.ink),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(store: store, reminders: widget.reminders, clock: widget.clock))),
        ),
      ]);

  Widget _addButton(Palette p, bool first) => Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _add,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              CircleAvatar(backgroundColor: p.accent, foregroundColor: p.accentInk, child: const Icon(Icons.add_rounded)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(first ? '最初の定点時刻を決める' : '定点時刻を追加',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.ink)),
                  Text(first ? '例：毎朝 7:30 の窓の外、毎晩 22:00 の机の上' : 'あと${kMaxSpots - store.spots.length}つまで（最大$kMaxSpots つ）',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _sampleCard(Palette p) {
    final clips = store.clipsOf(kSampleSpot.id);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: p.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(PageRouteBuilder(
          pageBuilder: (_, _, _) => PlayerScreen(store: store, spot: kSampleSpot, clips: clips),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 64,
              child: Row(children: [
                for (final c in clips) ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ClipStill(store: store, clip: c, spot: kSampleSpot),
                    ),
                  ),
                  if (c != clips.last) const SizedBox(width: 3),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('毎朝 6:30 の窓・12か月', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
              ),
              Icon(Icons.play_circle_fill_rounded, color: p.accent),
              const SizedBox(width: 4),
              Text('再生', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
            ]),
            Text('おなじ時刻でも、季節で空の明るさや木の色が変わっていきます。', style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.store, required this.spot, required this.now, required this.onCapture, required this.onOpen});
  final SpotStore store;
  final Spot spot;
  final DateTime now;
  final void Function(Spot, SlotWindow) onCapture;
  final void Function(Spot) onOpen;

  @override
  Widget build(BuildContext context) {
    final open = openWindow(spot, now);
    final taken = open == null ? null : store.at(spot.id, open.date);
    final next = nextWindow(spot, now);
    final clips = store.clipsOf(spot.id);
    final recent = clips.length > 7 ? clips.sublist(clips.length - 7) : clips;
    final streak = store.streak(spot, now);
    const white = Colors.white;
    const shadow = [Shadow(blurRadius: 14, color: Color(0x40000000))];
    return Container(
      decoration: BoxDecoration(gradient: skyGradient(spot.skyHour), borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onOpen(spot),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [.3, 1],
                  colors: [Color(0x00000000), Color(0x66000000)]),
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(spot.timeLabel,
                        style: const TextStyle(fontFamily: kDisplay, fontSize: 56, height: .95, color: white, shadows: shadow)),
                  ),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('連続 $streak 日', style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('${clips.length} 日分', style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12)),
                ]),
              ]),
              const SizedBox(height: 4),
              Text(spot.name, style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w700, shadows: shadow)),
              const SizedBox(height: 12),
              SizedBox(
                height: 46,
                child: Row(children: [
                  for (var i = 0; i < 7; i++) ...[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: i < recent.length
                            ? ClipStill(store: store, clip: recent[i], spot: spot)
                            : const ColoredBox(color: Color(0x26FFFFFF)),
                      ),
                    ),
                    if (i < 6) const SizedBox(width: 3),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text(
                    open == null
                        ? '次は ${dayLabel(next.date)} ${spot.timeLabel}（${untilLabel(now, next.opens)}で開きます）'
                        : taken == null
                            ? '撮影できます（${clockLabel(open.closes.hour * 60 + open.closes.minute)} まで）'
                            : '今日のぶんは撮影済み',
                    style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                if (open != null)
                  FilledButton(
                    onPressed: () => onCapture(spot, open),
                    style: FilledButton.styleFrom(
                      backgroundColor: white,
                      foregroundColor: const Color(0xFF1B1830),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(taken == null ? 'いま撮る' : '撮り直す', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
