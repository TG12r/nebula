import 'dart:ui' as ui;
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
      ..strokeWidth = radius * 2
      ..strokeCap = StrokeCap.round;

    final points = <Offset>[];
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        points.add(Offset(x, y));
      }
    }

    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.step != step ||
      oldDelegate.radius != radius;
}
