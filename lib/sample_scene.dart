import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sky.dart';

/// Approximate Tokyo sunrise (hours) for a month, 1..12.
double sunriseFor(int month) => 5.6 - 1.2 * math.cos(2 * math.pi * (month - 6.5) / 12);

/// How bright the sky looks at 6:30 in [month], as an hour on the sky table.
double sampleSkyHour(int month) => 6.5 + (6.0 - sunriseFor(month));

/// Illustrated stand-in frames for the built-in sample:
/// the same window at 6:30, once a month for a year.
class SampleScene extends StatelessWidget {
  const SampleScene({super.key, required this.month});
  final int month;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _WindowPainter(month), child: const SizedBox.expand());
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.month);
  final int month;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 360;
    final w = 360.0, h = size.height / s;
    canvas.save();
    canvas.scale(s);
    final sky = Offset.zero & Size(w, h);
    final skyH = sampleSkyHour(month);
    canvas.drawRect(sky, Paint()..shader = skyGradient(skyH).createShader(sky));

    // Sun: rises higher in summer at the same clock time.
    final sunUp = ((skyH - 5.5) / 3).clamp(0.0, 1.0);
    canvas.drawCircle(Offset(250, h * (.62 - .3 * sunUp)), 26,
        Paint()..color = Color.lerp(const Color(0xFFFF9A62), const Color(0xFFFFF1C4), sunUp)!.withValues(alpha: .35 + .6 * sunUp));

    // Distant hills.
    final hills = Path()
      ..moveTo(0, h * .66)
      ..quadraticBezierTo(90, h * .58, 180, h * .65)
      ..quadraticBezierTo(270, h * .7, 360, h * .6)
      ..lineTo(360, h)
      ..lineTo(0, h)
      ..close();
    final dark = 1 - sunUp;
    canvas.drawPath(hills, Paint()..color = Color.lerp(const Color(0xFF6E8F7A), const Color(0xFF26304A), dark)!);
    final snow = month == 1 || month == 2 || month == 12;
    canvas.drawRect(Rect.fromLTWH(0, h * .74, w, h * .26),
        Paint()..color = snow ? const Color(0xFFE8EEF6) : Color.lerp(const Color(0xFF8DAA6B), const Color(0xFF2E3A35), dark)!);

    _tree(canvas, Offset(110, h * .74), h);

    // Window frame and sill (the "same composition").
    final frame = Paint()..color = const Color(0xFFF4EFE6);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, 26), frame);
    canvas.drawRect(Rect.fromLTWH(0, 0, 22, h), frame);
    canvas.drawRect(Rect.fromLTWH(w - 22, 0, 22, h), frame);
    canvas.drawRect(Rect.fromLTWH(w / 2 - 6, 0, 12, h * .8), frame);
    canvas.drawRect(Rect.fromLTWH(0, h * .8, w, h * .2), Paint()..color = const Color(0xFFE6DCCB));
    // A small pot on the sill.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(262, h * .8 - 40, 46, 40), const Radius.circular(6)),
        Paint()..color = const Color(0xFFC97B4A));
    final leaf = Paint()..color = const Color(0xFF4F8A4A);
    final grow = 10 + 3.0 * month;
    canvas.drawOval(Rect.fromCenter(center: Offset(278, h * .8 - 40 - grow / 2), width: 18, height: grow), leaf);
    canvas.drawOval(Rect.fromCenter(center: Offset(294, h * .8 - 40 - grow / 2.6), width: 16, height: grow * .8), leaf);
    canvas.restore();
  }

  void _tree(Canvas canvas, Offset base, double h) {
    canvas.drawRect(Rect.fromLTWH(base.dx - 6, base.dy - 90, 12, 90), Paint()..color = const Color(0xFF5B4636));
    final Color? crown = switch (month) {
      3 || 4 => const Color(0xFFF6B9C9),
      5 || 6 || 7 || 8 => const Color(0xFF4E9A52),
      9 => const Color(0xFF8DA548),
      10 || 11 => const Color(0xFFE0743A),
      _ => null,
    };
    final branch = Paint()
      ..color = const Color(0xFF5B4636)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(base.translate(0, -70), base.translate(-34, -118), branch);
    canvas.drawLine(base.translate(0, -80), base.translate(30, -126), branch);
    canvas.drawLine(base.translate(0, -88), base.translate(0, -140), branch);
    if (crown != null) {
      final p = Paint()..color = crown;
      for (final o in const [Offset(-34, -120), Offset(30, -128), Offset(0, -146), Offset(-12, -110), Offset(16, -104)]) {
        canvas.drawCircle(base + o, 30, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) => old.month != month;
}
