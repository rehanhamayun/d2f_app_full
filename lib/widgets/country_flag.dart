import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small vector flags stay sharp and render consistently without emoji fonts.
class CountryFlag extends StatelessWidget {
  final String country;
  const CountryFlag({super.key, required this.country});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: CustomPaint(
      size: const Size(21, 14),
      painter: _FlagPainter(country),
    ),
  );
}

class _FlagPainter extends CustomPainter {
  final String country;
  _FlagPainter(this.country);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 30, size.height / 20);
    const green = Color(0xFF008A4A),
        yellow = Color(0xFFFFCE29),
        red = Color(0xFFD92937);
    void rect(double x, double y, double w, double h, Color c) =>
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = c);
    void star(
      double x,
      double y,
      double radius,
      Color color, {
      double angle = -math.pi / 2,
    }) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? radius : radius * .4, a = angle + i * math.pi / 5;
        if (i == 0) {
          path.moveTo(x + math.cos(a) * r, y + math.sin(a) * r);
        } else {
          path.lineTo(x + math.cos(a) * r, y + math.sin(a) * r);
        }
      }
      canvas.drawPath(path..close(), Paint()..color = color);
    }

    rect(0, 0, 30, 20, Colors.white);
    switch (country) {
      case 'Togo':
        for (var i = 0; i < 5; i++) {
          rect(0, i * 4, 30, 4, i.isEven ? green : yellow);
        }
        rect(0, 0, 12, 12, red);
        star(6, 6, 4, Colors.white);
      case 'Ghana':
        rect(0, 0, 30, 7, red);
        rect(0, 7, 30, 6, yellow);
        rect(0, 13, 30, 7, green);
        star(15, 10, 3.2, Colors.black);
      case 'Benin':
        rect(0, 0, 12, 20, green);
        rect(12, 0, 18, 10, yellow);
        rect(12, 10, 18, 10, red);
      case 'Burkina Faso':
        rect(0, 0, 30, 10, red);
        rect(0, 10, 30, 10, green);
        star(15, 10, 3.2, yellow);
      case 'Gabon':
        rect(0, 0, 30, 7, green);
        rect(0, 7, 30, 6, yellow);
        rect(0, 13, 30, 7, const Color(0xFF3568B8));
      case 'Senegal':
        rect(0, 0, 10, 20, green);
        rect(10, 0, 10, 20, yellow);
        rect(20, 0, 10, 20, red);
        star(15, 10, 3.2, green);
      case 'Belgium':
        rect(0, 0, 10, 20, Colors.black);
        rect(10, 0, 10, 20, yellow);
        rect(20, 0, 10, 20, red);
      case 'Nigeria':
        rect(0, 0, 10, 20, green);
        rect(20, 0, 10, 20, green);
      case 'Côte d’Ivoire':
        rect(0, 0, 10, 20, const Color(0xFFF78B27));
        rect(20, 0, 10, 20, green);
      case 'United States':
        for (var i = 0; i < 13; i++) {
          if (i.isEven) rect(0, i * 20 / 13, 30, 20 / 13, red);
        }
        rect(0, 0, 13, 11, const Color(0xFF20356A));
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 5; x++) {
            star(1.5 + x * 2.5, 1.5 + y * 2.5, .6, Colors.white);
          }
        }
      case 'Canada':
        rect(0, 0, 7, 20, red);
        rect(23, 0, 7, 20, red);
        final leaf = Path()
          ..moveTo(15, 3)
          ..lineTo(17, 7)
          ..lineTo(19, 5)
          ..lineTo(18, 10)
          ..lineTo(22, 9)
          ..lineTo(20, 14)
          ..lineTo(16, 15)
          ..lineTo(16, 18)
          ..lineTo(14, 18)
          ..lineTo(14, 15)
          ..lineTo(10, 14)
          ..lineTo(8, 9)
          ..lineTo(12, 10)
          ..lineTo(11, 5)
          ..lineTo(13, 7)
          ..close();
        canvas.drawPath(leaf, Paint()..color = red);
      case 'France':
        rect(0, 0, 10, 20, const Color(0xFF18388A));
        rect(20, 0, 10, 20, red);
      case 'United Kingdom':
        rect(0, 0, 30, 20, const Color(0xFF1D3467));
        final p = Paint()
          ..color = Colors.white
          ..strokeWidth = 5;
        canvas.drawLine(Offset.zero, const Offset(30, 20), p);
        canvas.drawLine(const Offset(0, 20), const Offset(30, 0), p);
        p
          ..color = red
          ..strokeWidth = 1.7;
        canvas.drawLine(Offset.zero, const Offset(30, 20), p);
        canvas.drawLine(const Offset(0, 20), const Offset(30, 0), p);
        rect(0, 7, 30, 6, Colors.white);
        rect(12, 0, 6, 20, Colors.white);
        rect(0, 8, 30, 4, red);
        rect(13, 0, 4, 20, red);
      case 'Pakistan':
        rect(7, 0, 23, 20, const Color(0xFF005A33));
        canvas.drawCircle(
          const Offset(19, 10),
          6,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          const Offset(21, 8.5),
          5.3,
          Paint()..color = const Color(0xFF005A33),
        );
        star(23, 6, 2, Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) =>
      country != oldDelegate.country;
}
