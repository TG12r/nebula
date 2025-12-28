import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final Color color;
  final double step;
  final double radius;

  GridPainter({required this.color, this.step = 20.0, this.radius = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
