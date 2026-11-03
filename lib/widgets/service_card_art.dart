import 'package:flutter/material.dart';

/// Small, rounded illustration accents, like the supplied Send Package card.
/// All marks stay beside the icon; titles and the card background stay clear.
class ServiceCardLineArt extends CustomPainter {
  final int pattern;
  final Color color;
  const ServiceCardLineArt({required this.pattern, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final x = size.width / 2;
    void stroke(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x + x1, y1), Offset(x + x2, y2), paint);
    void sparkle(double dx, double y) {
      stroke(dx - 3, y, dx + 3, y);
      stroke(dx, y - 3, dx, y + 3);
    }

    switch (pattern) {
      case 0: // Shipping: three lively marks, echoing the parcel reference.
        stroke(-28, 17, -33, 12);
        stroke(-29, 27, -36, 27);
        stroke(-27, 37, -32, 42);
      case 1: // Local delivery: compact forward-motion strokes.
        stroke(-27, 20, -34, 20);
        stroke(-27, 28, -38, 28);
        stroke(-27, 36, -32, 36);
      case 2: // Buy For Me: the reference's short shopping-bag rays.
        stroke(27, 15, 30, 9);
        stroke(30, 25, 37, 22);
        stroke(30, 35, 36, 36);
      case 3: // Marketplace: a small discovery sparkle and a single tick.
        sparkle(29, 17);
        stroke(28, 37, 33, 40);
      case 4: // Connect: two small paired connection marks.
        stroke(-27, 18, -31, 13);
        stroke(-29, 28, -35, 28);
        stroke(27, 32, 32, 35);
      case 5: // Africa delivery: short road-motion accents beside the scooter.
        stroke(-27, 22, -34, 22);
        stroke(-28, 31, -38, 31);
        stroke(28, 16, 32, 12);
      case 6: // Business Ads: tiny announcement rays.
        stroke(27, 15, 31, 10);
        stroke(30, 26, 37, 26);
        stroke(27, 37, 32, 41);
      case 7: // Load Board: simple transport-motion strokes.
        stroke(-27, 20, -34, 20);
        stroke(-29, 29, -38, 29);
        stroke(-27, 38, -32, 38);
    }
  }

  @override
  bool shouldRepaint(covariant ServiceCardLineArt oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}
