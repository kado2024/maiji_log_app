import 'package:flutter/material.dart';

import '../notifications.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.reminders});
  final ClipStore store;
  final HourlyReminders reminders;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  HourlyReminders get r => widget.reminders;
  late RangeValues _range = RangeValues(r.startHour.toDouble(), r.endHour.toDouble());

  Future<void> _toggle(bool on) async {
    if (on) {
      final ok = await r.enable();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('通知が許可されていません。「設定」アプリ → 毎時ログ → 通知 でオンにしてください。'),
        ));
      }
    } else {
      await r.disable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmClear() async {
    final p = Palette.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('すべてのコマを削除'),
        content: Text('撮影した ${widget.store.all.length} コマをこの端末から削除します。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('削除する', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.store.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('すべてのコマを削除しました')));
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final head = TextStyle(fontSize: 12, letterSpacing: 1.2, color: p.muted, fontWeight: FontWeight.w700);
    // Cards are Material so list tiles can paint their ink on them.
    Widget card({required Widget child, EdgeInsets? padding}) => Material(
          color: p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
          child: padding == null ? child : Padding(padding: padding, child: child),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text('通知', style: head),
          const SizedBox(height: 8),
          card(
            child: Column(children: [
              SwitchListTile(
                value: r.enabled,
                onChanged: _toggle,
                activeThumbColor: p.accent,
                title: const Text('毎時00分に知らせる'),
                subtitle: Text('新しい枠が開いたら通知します', style: TextStyle(color: p.muted, fontSize: 12)),
              ),
              if (r.enabled) ...[
                Divider(height: 1, color: p.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    const Text('通知する時間帯'),
                    const Spacer(),
                    Text('${two(_range.start.round())}:00 〜 ${two(_range.end.round())}:00',
                        style: TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], color: p.ink)),
                  ]),
                ),
                RangeSlider(
                  values: _range,
                  min: 0,
                  max: 23,
                  divisions: 23,
                  activeColor: p.accent,
                  onChanged: (v) => setState(() => _range = v),
                  onChangeEnd: (v) => r.setRange(v.start.round(), v.end.round()),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          Text('データ', style: head),
          const SizedBox(height: 8),
          card(
            child: ListTile(
              title: Text('すべてのコマを削除', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
              subtitle: Text('いま ${widget.store.all.length} コマ保存されています',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              onTap: widget.store.all.isEmpty ? null : _confirmClear,
            ),
          ),
          const SizedBox(height: 24),
          Text('プライバシー', style: head),
          const SizedBox(height: 8),
          card(
            padding: const EdgeInsets.all(16),
            child: Text(
              '撮影したコマはこの iPhone の中だけに保存されます。'
              'サーバーへの送信、アカウント登録、広告、行動の追跡は一切ありません。'
              'アプリを削除すると、コマもすべて削除されます。',
              style: TextStyle(color: p.ink, height: 1.7),
            ),
          ),
          const SizedBox(height: 24),
          Text('使い方', style: head),
          const SizedBox(height: 8),
          card(
            padding: const EdgeInsets.all(16),
            child: Text(
              '・毎時00分に新しい枠が開きます。その1時間に撮れるのは1コマ（2秒）だけです。\n'
              '・過ぎた枠はあとから撮れません。\n'
              '・「Vlogを再生」で、その日のコマが時刻順につながって流れます。\n'
              '・1日に$kStreakMinコマ以上撮った日が続くと「連続」日数が伸びます。',
              style: TextStyle(color: p.ink, height: 1.8),
            ),
          ),
        ],
      ),
    );
  }
}
