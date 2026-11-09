import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../exporter.dart';
import '../model.dart';
import '../schedule.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare.dart';
import 'player.dart';
import 'spot_edit.dart';

/// Everything recorded for one spot: the same time, day after day.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.store, required this.spotId, required this.clock, this.exporter = const SequenceExporter()});
  final SpotStore store;
  final int spotId;
  final DateTime Function() clock;
  final SequenceExporter exporter;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  Span _span = Span.month;
  double _speed = 1.0;

  SpotStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  List<DayClip> _selected(DateTime now) => clipsIn(store.clipsOf(widget.spotId), _span, now);

  void _play(Spot s, List<DayClip> clips, [int start = 0]) {
    if (clips.isEmpty) return;
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, _, _) => PlayerScreen(store: store, spot: s, clips: clips, start: start, secondsPerClip: _speed),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  Future<void> _export(Spot s, List<DayClip> clips) async {
    if (clips.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final origin = _shareOrigin();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 18),
          Expanded(child: Text('動画を書き出しています…')),
        ]),
      ),
    );
    String? path;
    String? error;
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/exports');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      path = await widget.exporter.export(
        store: store,
        spot: s,
        clips: clips,
        secondsPerClip: _speed,
        outPath: '${dir.path}/${exportFileName(s, clips)}',
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (path == null) {
      messenger.showSnackBar(SnackBar(content: Text('書き出しに失敗しました（$error）')));
      return;
    }
    final done = path;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('${clips.length}日分の動画ができました'),
            subtitle: Text('${dayLabel(clips.first.date)} 〜 ${dayLabel(clips.last.date)}・${speedLabel(_speed)}・日付入り'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('「写真」に保存'),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await widget.exporter.saveToPhotos(done).catchError((_) => false);
              messenger.showSnackBar(SnackBar(
                  content: Text(ok ? '「写真」に保存しました' : '保存できませんでした。「設定」アプリで写真への追加を許可してください。')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('共有…'),
            onTap: () async {
              Navigator.pop(ctx);
              await SharePlus.instance.share(ShareParams(files: [XFile(done)], sharePositionOrigin: origin));
            },
          ),
        ]),
      ),
    );
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Rect.fromLTWH(0, 0, 1, 1);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _edit(Spot s) async {
    final saved = await editSpot(context, store: store, now: widget.clock(), existing: s);
    if (saved == null && store.spot(s.id) == null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = store.spot(widget.spotId);
    if (s == null) return const Scaffold();
    final now = widget.clock();
    final all = store.clipsOf(s.id);
    final sel = _selected(now);
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.timeLabel}  ${s.name}'),
        actions: [
          if (s.id != kSampleSpot.id) IconButton(tooltip: '編集', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(s)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _stats(p, s, all, now),
          const SizedBox(height: 16),
          Text('範囲', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<Span>(
            showSelectedIcon: false,
            segments: [for (final sp in Span.values) ButtonSegment(value: sp, label: Text(sp.label))],
            selected: {_span},
            onSelectionChanged: (v) => setState(() => _span = v.first),
          ),
          const SizedBox(height: 12),
          Text('速さ', style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: [for (final v in kSpeeds) ButtonSegment(value: v, label: Text(speedLabel(v)))],
            selected: {_speed},
            onSelectionChanged: (v) => setState(() => _speed = v.first),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: sel.isEmpty ? null : () => _play(s, sel),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: const StadiumBorder()),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('${sel.length}日分の変化を再生', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: sel.isEmpty || s.id == kSampleSpot.id ? null : () => _export(s, sel),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: const StadiumBorder()),
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('日付入り動画に書き出す'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: all.length < 2
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CompareScreen(store: store, spot: s, clips: all))),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: const StadiumBorder()),
                icon: const Icon(Icons.compare_rounded),
                label: const Text('2日を比べる'),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('まだ撮影がありません。\n毎日 ${s.timeLabel} の前後に、ホームの「いま撮る」から撮影できます。',
                  textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.6)),
            )
          else
            ..._months(p, s, all, now),
        ],
      ),
    );
  }

  Widget _stats(Palette p, Spot s, List<DayClip> all, DateTime now) {
    Widget cell(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: TextStyle(fontFamily: kMono, fontFamilyFallback: const [kBody], fontSize: 22, fontWeight: FontWeight.w600, color: p.ink)),
            Text(l, style: TextStyle(fontSize: 11, color: p.muted)),
          ]),
        );
    final isSample = s.id == kSampleSpot.id;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
      child: Row(children: [
        cell('${all.length}', '撮った日'),
        cell(isSample ? '-' : '${store.streak(s, now)}', '連続'),
        cell(all.isEmpty ? '-' : dayLabel(all.first.date).split('(').first, 'はじめた日'),
      ]),
    );
  }

  /// One calendar per month, newest first; tap a day to play from there.
  List<Widget> _months(Palette p, Spot s, List<DayClip> all, DateTime now) {
    final byDate = {for (final c in all) c.date: c};
    final first = parseDateKey(all.first.date);
    final lastClip = parseDateKey(all.last.date);
    final last = lastClip.isAfter(now) ? lastClip : now;
    final months = <DateTime>[];
    for (var m = DateTime(last.year, last.month); !m.isBefore(DateTime(first.year, first.month)); m = DateTime(m.year, m.month - 1)) {
      months.add(m);
    }
    return [
      for (final m in months) ...[
        Text('${m.year}年${m.month}月', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 8),
        _MonthGrid(
          month: m,
          builder: (d) {
            final c = byDate[dateKey(d)];
            if (c == null) {
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
                child: Text('${d.day}', style: TextStyle(fontSize: 11, color: p.muted)),
              );
            }
            return GestureDetector(
              onTap: () => _play(s, all, all.indexOf(c)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(fit: StackFit.expand, children: [
                  ClipStill(store: store, clip: c, spot: s),
                  Positioned(
                    left: 3,
                    top: 2,
                    child: Text('${d.day}',
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700,
                            shadows: [Shadow(blurRadius: 4, color: Color(0xA0000000))])),
                  ),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
      ],
    ];
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.builder});
  final DateTime month;
  final Widget Function(DateTime day) builder;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday - 1; // Monday first
    return Column(children: [
      Row(children: [
        for (final w in '月火水木金土日'.split(''))
          Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 10, color: p.muted)))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 3 / 4,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var d = 1; d <= days; d++) builder(DateTime(month.year, month.month, d)),
        ],
      ),
    ]);
  }
}
