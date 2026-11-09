import 'package:flutter/material.dart';

import '../model.dart';
import '../notifications.dart';
import '../schedule.dart';
import '../store.dart';
import '../theme.dart';
import 'spot_edit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.reminders, required this.clock});
  final SpotStore store;
  final SpotReminders reminders;
  final DateTime Function() clock;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SpotReminders get r => widget.reminders;
  SpotStore get store => widget.store;

  Future<void> _toggle(bool on) async {
    if (on) {
      final ok = await r.enable(store.spots);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('通知が許可されていません。「設定」アプリ → おなじ時刻 → 通知 でオンにしてください。'),
        ));
      }
    } else {
      await r.disable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit(Spot s) async {
    await editSpot(context, store: store, now: widget.clock(), existing: s);
    if (mounted) setState(() {});
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = Palette.of(ctx);
        return AlertDialog(
          title: const Text('撮影した動画をすべて削除'),
          content: Text('撮影した ${store.all.length} 日分の動画をこの端末から削除します。定点時刻の設定は残ります。元に戻せません。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('削除する', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await store.clear();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('撮影した動画をすべて削除しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final head = TextStyle(fontSize: 12, letterSpacing: 1.2, color: p.muted, fontWeight: FontWeight.w700);
    Widget card({required Widget child, EdgeInsets? padding}) => Material(
          color: p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
          child: padding == null ? child : Padding(padding: padding, child: child),
        );
    final spots = store.spots;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text('定点時刻', style: head),
          const SizedBox(height: 8),
          card(
            child: Column(children: [
              if (spots.isEmpty)
                ListTile(title: Text('まだありません。ホームの「定点時刻を決める」から追加できます。', style: TextStyle(color: p.muted, fontSize: 13))),
              for (final s in spots) ...[
                if (s != spots.first) Divider(height: 1, color: p.line),
                ListTile(
                  title: Text('${s.timeLabel}  ${s.name}'),
                  subtitle: Text('${store.clipsOf(s.id).length} 日分', style: TextStyle(color: p.muted, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _edit(s),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          Text('通知', style: head),
          const SizedBox(height: 8),
          card(
            child: SwitchListTile(
              value: r.enabled,
              onChanged: _toggle,
              activeThumbColor: p.accent,
              title: const Text('定点時刻に知らせる'),
              subtitle: Text(
                  spots.isEmpty ? '定点時刻を追加すると、その時刻に通知します' : '毎日 ${spots.map((s) => s.timeLabel).join('・')} に通知します',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 24),
          Text('データ', style: head),
          const SizedBox(height: 8),
          card(
            child: ListTile(
              title: Text('撮影した動画をすべて削除', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
              subtitle: Text('いま ${store.all.length} 日分保存されています', style: TextStyle(color: p.muted, fontSize: 12)),
              onTap: store.all.isEmpty ? null : _confirmClear,
            ),
          ),
          const SizedBox(height: 24),
          Text('プライバシー', style: head),
          const SizedBox(height: 8),
          card(
            padding: const EdgeInsets.all(16),
            child: Text(
              '撮影した動画はこの iPhone の中だけに保存されます。'
              'サーバーへの送信、アカウント登録、広告、行動の追跡は一切ありません。'
              '書き出した動画は、あなたが「写真に保存」や「共有」を選んだときだけアプリの外に出ます。'
              'アプリを削除すると、撮影した動画もすべて削除されます。',
              style: TextStyle(color: p.ink, height: 1.7),
            ),
          ),
          const SizedBox(height: 24),
          Text('使い方', style: head),
          const SizedBox(height: 8),
          card(
            padding: const EdgeInsets.all(16),
            child: Text(
              '・毎日撮る「定点時刻」を最大$kMaxSpotsつ決めます（例：7:30 窓の外）。\n'
              '・撮影できるのは、その時刻の${kOpenBefore.inMinutes}分前から${kOpenAfter.inMinutes}分後まで。1日1回、2秒です。\n'
              '・撮影画面の「前回と重ねる」で、前回の構図を半透明で重ねて同じ構図に合わせられます。\n'
              '・定点時刻をタップすると、カレンダーで日ごとに見返せます。「変化を再生」で日付順につながって流れます。\n'
              '・「日付入り動画に書き出す」で、日付を焼き込んだ1本の動画を作り、写真に保存・共有できます。',
              style: TextStyle(color: p.ink, height: 1.8),
            ),
          ),
        ],
      ),
    );
  }
}
