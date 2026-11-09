import 'package:flutter/material.dart';

import '../model.dart';
import '../sky.dart';
import '../store.dart';
import '../widgets.dart';

/// Two days of the same spot on top of each other, with a draggable divider.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.store, required this.spot, required this.clips});
  final SpotStore store;
  final Spot spot;
  final List<DayClip> clips; // oldest first, at least 2

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late int _a = 0; // older
  late int _b = widget.clips.length - 1; // newer
  double _split = .5;

  Widget _picker(String label, int value, ValueChanged<int> onChanged) => DropdownButton<int>(
        value: value,
        isExpanded: true,
        items: [
          for (var i = 0; i < widget.clips.length; i++)
            DropdownMenuItem(value: i, child: Text('$label  ${dayLabel(widget.clips[i].date)}')),
        ],
        onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.clips[_a], b = widget.clips[_b];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.spot.timeLabel} を比べる')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _picker('左', _a, (v) => _a = v)),
              const SizedBox(width: 12),
              Expanded(child: _picker('右', _b, (v) => _b = v)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                return GestureDetector(
                  onHorizontalDragUpdate: (d) => setState(() => _split = (_split + d.delta.dx / w).clamp(0.0, 1.0)),
                  onTapDown: (d) => setState(() => _split = (d.localPosition.dx / w).clamp(0.0, 1.0)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipStill(store: widget.store, clip: b, spot: widget.spot),
                      ClipRect(
                        clipper: _LeftClipper(_split),
                        child: ClipStill(store: widget.store, clip: a, spot: widget.spot),
                      ),
                      Positioned(
                        left: w * _split - 1.5,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 3, color: Colors.white),
                      ),
                      Positioned(left: 12, bottom: 12, child: _tag(dayLabel(a.date))),
                      Positioned(right: 12, bottom: 12, child: _tag(dayLabel(b.date))),
                    ]),
                  ),
                );
              }),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('左右にドラッグして、おなじ時刻の違いを見比べられます', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.f);
  final double f;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(_LeftClipper old) => old.f != f;
}
