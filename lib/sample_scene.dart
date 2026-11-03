import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sky.dart';

/// Illustrated stand-in frames for the built-in sample day.
class SampleScene extends StatelessWidget {
  const SampleScene({super.key, required this.hour, required this.kind});
  final int hour;
  final String kind;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScenePainter(hour, kind), child: const SizedBox.expand());
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.hour, this.kind);
  final int hour;
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = skyGradient(hour).createShader(rect));
    // Draw in a 360-wide coordinate space, like the prototype.
    final s = size.width / 360;
    final w = 360.0, h = size.height / s;
    canvas.save();
    canvas.scale(s);
    final white = Paint()..color = Colors.white.withValues(alpha: .9);
    void ground(Color c) => canvas.drawRect(Rect.fromLTWH(0, h * .72, w, h * .28), Paint()..color = c);
    switch (kind) {
      case 'sun':
        ground(const Color(0x591E1E3C));
        canvas.drawCircle(Offset(250, h * .68), 60, Paint()..color = const Color(0xFFFFE3A3));
      case 'sunset':
        canvas.drawCircle(Offset(180, h * .7), 80, Paint()..color = const Color(0xFFFFB36B));
        ground(const Color(0x8C28143C));
      case 'road':
        ground(const Color(0x6628283C));
        final path = Path()
          ..moveTo(150, h * .72)
          ..lineTo(210, h * .72)
          ..lineTo(330, h)
          ..lineTo(30, h)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0x993C3C50));
        final dash = Paint()
          ..color = Colors.white.withValues(alpha: .8)
          ..strokeWidth = 6;
        for (var y = h * .74; y < h; y += 44) {
          canvas.drawLine(Offset(180, y), Offset(180, math.min(y + 24, h)), dash);
        }
      case 'note':
        canvas.drawRect(Rect.fromLTWH(60, h * .3, 240, h * .45), white);
        final line = Paint()
          ..color = const Color(0x805078C8)
          ..strokeWidth = 2;
        for (var i = 1; i < 9; i++) {
          canvas.drawLine(Offset(70, h * .3 + i * h * .05), Offset(290, h * .3 + i * h * .05), line);
        }
      case 'bowl':
        canvas.drawOval(Rect.fromCenter(center: Offset(180, h * .62), width: 240, height: 60), white);
        final bowl = Path()
          ..moveTo(60, h * .6)
          ..quadraticBezierTo(180, h * .85, 300, h * .6)
          ..close();
        canvas.drawPath(bowl, white);
        canvas.drawOval(Rect.fromCenter(center: Offset(180, h * .6), width: 200, height: 44),
            Paint()..color = const Color(0xFFF3C06B));
      case 'window':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x73141428));
        final win = Rect.fromLTWH(60, h * .2, 240, h * .5);
        canvas.drawRect(win, Paint()..shader = skyGradient(hour).createShader(win));
        final frame = Paint()
          ..color = Colors.white.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8;
        canvas.drawRect(win, frame);
        canvas.drawLine(Offset(180, h * .2), Offset(180, h * .7), frame);
      case 'cup':
        ground(const Color(0x593C2828));
        canvas.drawRect(Rect.fromLTWH(130, h * .5, 100, 110), white);
        canvas.drawArc(Rect.fromCircle(center: Offset(230, h * .5 + 50), radius: 24), -1.4, 2.8, false,
            Paint()
              ..color = Colors.white.withValues(alpha: .9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6);
      case 'lamp':
        canvas.drawCircle(Offset(180, h * .45), 170, Paint()..color = const Color(0x40FFDC96));
        final shade = Path()
          ..moveTo(130, h * .4)
          ..lineTo(230, h * .4)
          ..lineTo(205, h * .3)
          ..lineTo(155, h * .3)
          ..close();
        final lamp = Paint()..color = const Color(0xFFFFD98A);
        canvas.drawPath(shade, lamp);
        canvas.drawRect(Rect.fromLTWH(175, h * .4, 10, h * .25), lamp);
      case 'moon':
        for (var i = 0; i < 40; i++) {
          canvas.drawRect(Rect.fromLTWH(((i * 83) % w), ((i * 151) % (h * .7)), 2, 2),
              Paint()..color = Colors.white.withValues(alpha: .3 + ((i * 37) % 7) / 10));
        }
        canvas.drawCircle(Offset(250, h * .25), 40, Paint()..color = const Color(0xFFFFF3C8));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.hour != hour || old.kind != kind;
}
