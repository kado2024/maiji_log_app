import 'package:flutter/material.dart';

import '../model.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';

/// Adds a new spot, or edits [existing]. Returns the saved spot,
/// or null if cancelled / deleted.
Future<Spot?> editSpot(BuildContext context, {required SpotStore store, required DateTime now, Spot? existing}) =>
    showModalBottomSheet<Spot>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SpotSheet(store: store, now: now, existing: existing),
    );

class _SpotSheet extends StatefulWidget {
  const _SpotSheet({required this.store, required this.now, this.existing});
  final SpotStore store;
  final DateTime now;
  final Spot? existing;

  @override
  State<_SpotSheet> createState() => _SpotSheetState();
}

class _SpotSheetState extends State<_SpotSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _minute = widget.existing?.minute ?? 7 * 60 + 30;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
      helpText: '毎日撮る時刻',
    );
    if (t != null) setState(() => _minute = t.hour * 60 + t.minute);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ex = widget.existing;
    final Spot s;
    if (ex == null) {
      s = await widget.store.addSpot(name: _name.text, minute: _minute);
    } else {
      s = ex.copyWith(name: _name.text.trim().isEmpty ? ex.name : _name.text.trim(), minute: _minute);
      await widget.store.updateSpot(s);
    }
    if (mounted) Navigator.of(context).pop(s);
  }

  Future<void> _delete() async {
    final ex = widget.existing!;
    final n = widget.store.clipsOf(ex.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${ex.name}」を削除'),
        content: Text('この定点時刻と、撮影した $n 日分の動画をこの端末から削除します。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除する')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.removeSpot(ex.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final nowMinute = widget.now.hour * 60 + widget.now.minute;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.existing == null ? '定点時刻を追加' : '定点時刻を編集',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 4),
        Text('毎日この時刻の前後（15分前〜45分後）だけ撮影できます。', style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(gradient: skyGradient(_minute / 60), borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          child: Row(children: [
            Text(clockLabel(_minute),
                style: const TextStyle(fontFamily: kDisplay, fontSize: 44, color: Colors.white, height: 1)),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FilledButton.tonal(onPressed: _pickTime, child: const Text('時刻を選ぶ')),
              TextButton(
                onPressed: () => setState(() => _minute = nowMinute),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text('いまの時刻（${clockLabel(nowMinute)}）にする'),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 16,
          decoration: const InputDecoration(labelText: '撮るもの・場所', hintText: '例：窓の外', border: OutlineInputBorder()),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in kSpotNameIdeas)
            ActionChip(label: Text(n), onPressed: () => setState(() => _name.text = n)),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          if (widget.existing != null)
            TextButton(onPressed: _busy ? null : _delete, child: Text('削除', style: TextStyle(color: p.accent))),
          const Spacer(),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}
