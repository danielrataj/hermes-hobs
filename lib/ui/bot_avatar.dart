import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/models.dart';
import 'theme.dart';

/// Bot avatar in the dashboard's vocabulary: a colored shape with two eyes.
///
/// Shape and color come from `ui_meta['hermes-bots']` (`shape`, `color`).
/// Without them both are derived from the bot name, like the dashboard does,
/// so a bot keeps the same face on every device.
class BotAvatar extends StatelessWidget {
  const BotAvatar({
    super.key,
    required this.bot,
    this.size = 36,
    this.working = false,
  });

  final Bot bot;
  final double size;

  /// Shows the green presence dot.
  final bool working;

  static const _shapes = [
    'circle',
    'squircle',
    'pill',
    'triangle',
    'hexagon',
    'cloud',
    'drop',
  ];

  static const _palette = [
    Color(0xFFF0997B),
    Color(0xFF85B7EB),
    Color(0xFFE24B4A),
    Color(0xFF7F77DD),
    Color(0xFFEF9F27),
    Color(0xFF5DCAA5),
    Color(0xFFD4537E),
    Color(0xFF378ADD),
    Color(0xFF97C459),
    Color(0xFFFAC775),
    Color(0xFF534AB7),
    Color(0xFF9FE1CB),
  ];

  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static String shapeFor(Bot bot) {
    final s = bot.shape;
    if (s != null) {
      if (s == 'blob' || s.startsWith('blobatar')) return 'blob';
      if (_shapes.contains(s)) return s;
    }
    return _shapes[_hash(bot.name) % _shapes.length];
  }

  static Color colorFor(Bot bot) {
    final c = bot.color;
    if (c != null && RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(c)) {
      return Color(int.parse(c.replaceFirst('#', ''), radix: 16) | 0xFF000000);
    }
    return _palette[_hash('${bot.name}::color') % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(bot);
    final dot = size * 0.3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _AvatarPainter(
              shape: shapeFor(bot),
              color: color,
              seed: _hash(bot.name),
            ),
          ),
          if (working)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: HobsColors.of(context).working,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter({
    required this.shape,
    required this.color,
    required this.seed,
  });

  final String shape;
  final Color color;
  final int seed;

  Path _shapePath(Size s) {
    final w = s.width, h = s.height;
    final p = Path();
    switch (shape) {
      case 'squircle':
        p.addRRect(
          RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * 0.3)),
        );
      case 'pill':
        p.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, h * 0.18, w, h * 0.64),
            Radius.circular(h * 0.32),
          ),
        );
      case 'triangle':
        p
          ..moveTo(w / 2, h * 0.04)
          ..quadraticBezierTo(w * 0.56, h * 0.04, w * 0.98, h * 0.86)
          ..quadraticBezierTo(w, h * 0.94, w * 0.9, h * 0.94)
          ..lineTo(w * 0.1, h * 0.94)
          ..quadraticBezierTo(0, h * 0.94, w * 0.02, h * 0.86)
          ..quadraticBezierTo(w * 0.44, h * 0.04, w / 2, h * 0.04);
      case 'hexagon':
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 3 * i - math.pi / 2;
          final pt = Offset(
            w / 2 + w / 2 * math.cos(a),
            h / 2 + h / 2 * math.sin(a),
          );
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        p.close();
      case 'cloud':
        p
          ..addOval(
            Rect.fromCircle(
              center: Offset(w * 0.32, h * 0.58),
              radius: w * 0.26,
            ),
          )
          ..addOval(
            Rect.fromCircle(
              center: Offset(w * 0.68, h * 0.58),
              radius: w * 0.26,
            ),
          )
          ..addOval(
            Rect.fromCircle(center: Offset(w * 0.5, h * 0.4), radius: w * 0.3),
          )
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.1, h * 0.5, w * 0.8, h * 0.34),
              Radius.circular(h * 0.17),
            ),
          );
      case 'drop':
        p
          ..moveTo(w / 2, 0)
          ..cubicTo(w * 0.62, h * 0.22, w * 0.95, h * 0.45, w * 0.95, h * 0.64)
          ..arcToPoint(
            Offset(w * 0.05, h * 0.64),
            radius: Radius.circular(w * 0.45),
          )
          ..cubicTo(w * 0.05, h * 0.45, w * 0.38, h * 0.22, w / 2, 0)
          ..close();
      case 'blob':
        final rnd = math.Random(seed);
        const n = 7;
        final pts = <Offset>[];
        for (var i = 0; i < n; i++) {
          final a = 2 * math.pi * i / n;
          final r = w * (0.4 + rnd.nextDouble() * 0.1);
          pts.add(Offset(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a)));
        }
        Offset mid(Offset a, Offset b) =>
            Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final start = mid(pts.last, pts.first);
        p.moveTo(start.dx, start.dy);
        for (var i = 0; i < n; i++) {
          final c = pts[i];
          final next = mid(c, pts[(i + 1) % n]);
          p.quadraticBezierTo(c.dx, c.dy, next.dx, next.dy);
        }
        p.close();
      default:
        p.addOval(Offset.zero & s);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(_shapePath(size), Paint()..color = color);
    final dark = color.computeLuminance() < 0.25;
    final eye = Paint()..color = dark ? Colors.white : const Color(0xFF2C2C2A);
    final eyeY = shape == 'triangle' ? size.height * 0.62 : size.height * 0.5;
    final dx = size.width * 0.13;
    final r = size.width * 0.065;
    canvas.drawCircle(Offset(size.width / 2 - dx, eyeY), r, eye);
    canvas.drawCircle(Offset(size.width / 2 + dx, eyeY), r, eye);
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.shape != shape || old.color != color || old.seed != seed;
}
