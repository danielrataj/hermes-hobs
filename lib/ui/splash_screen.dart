import 'package:flutter/material.dart';

/// Shown while the stored session is being restored. Matches the native launch
/// screens (the Hobs glyph on ink) so startup reads as one continuous splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const ink = Color(0xFF2C2C2A);
  static const amber = Color(0xFFFFAC02);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ink,
      body: Center(
        child: CustomPaint(size: Size.square(160), painter: HobGlyphPainter()),
      ),
    );
  }
}

/// The hob: an amber sprite with two ears and two eyes, drawn on a 100x100
/// grid. Keep in sync with the glyph in tool/generate_icons.sh.
class HobGlyphPainter extends CustomPainter {
  const HobGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final fill = Paint()..color = SplashScreen.amber;
    final outline = Paint()
      ..color = SplashScreen.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round;
    for (final ear in const [
      [Offset(25, 52), Offset(20, 23), Offset(45, 37)],
      [Offset(75, 52), Offset(80, 23), Offset(55, 37)],
    ]) {
      final path = Path()..addPolygon(ear, true);
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, outline);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 34, 56, 46),
        const Radius.circular(22),
      ),
      fill,
    );
    final eye = Paint()..color = SplashScreen.ink;
    canvas
      ..drawCircle(const Offset(41, 58), 4.2, eye)
      ..drawCircle(const Offset(59, 58), 4.2, eye);
  }

  @override
  bool shouldRepaint(HobGlyphPainter oldDelegate) => false;
}
