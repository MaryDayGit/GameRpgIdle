import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Иконки узлов дерева пассивок — кодом, а не картинками.
///
/// Та же причина, что у силуэтов мобов и иконок вещей: лицензии, вес пакета и
/// второй источник истины. Триста узлов дерева — это триста PNG, которые
/// кто-то должен нарисовать, положить в три разрешения и не забыть обновить
/// вместе с контентом.
///
/// Рисунок здесь — не иллюстрация, а ОПОЗНАВАТЕЛЬНЫЙ ЗНАК. Игрок ведёт палец
/// по лучу и должен видеть, что узлы разные, не читая подписи: сердце — это
/// здоровье, щит — броня, клык — урон. Поэтому фигуры простые и различимые
/// на девяти пикселях, а не подробные.
void paintPassiveIcon(
  Canvas canvas,
  String icon,
  Offset center,
  double radius,
  Color color,
) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, radius * 0.16)
    ..strokeCap = StrokeCap.round;

  final r = radius;
  Offset at(double x, double y) => center + Offset(x * r, y * r);

  switch (icon) {
    // --- плоть ---------------------------------------------------------------
    case 'heart':
      final path = Path()
        ..moveTo(center.dx, center.dy + r * 0.75)
        ..cubicTo(center.dx - r * 1.5, center.dy - r * 0.2,
            center.dx - r * 0.5, center.dy - r * 1.1, center.dx, center.dy - r * 0.3)
        ..cubicTo(center.dx + r * 0.5, center.dy - r * 1.1,
            center.dx + r * 1.5, center.dy - r * 0.2, center.dx,
            center.dy + r * 0.75);
      canvas.drawPath(path, paint);

    case 'hide':
      // Шкура: скруглённый четырёхугольник с прорезью.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: r * 1.6, height: r * 1.4),
          Radius.circular(r * 0.5),
        ),
        paint,
      );

    case 'breath':
      // Дыхание: три дуги, расходящиеся вверх.
      for (var i = 0; i < 3; i++) {
        final y = -0.7 + i * 0.55;
        canvas.drawArc(
          Rect.fromCenter(
              center: at(0, y), width: r * 1.6, height: r * 0.9),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          line,
        );
      }

    case 'bone':
      canvas.drawLine(at(-0.7, 0.7), at(0.7, -0.7), line);
      canvas.drawCircle(at(-0.8, 0.8), r * 0.32, paint);
      canvas.drawCircle(at(0.8, -0.8), r * 0.32, paint);

    case 'drop':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..quadraticBezierTo(
            center.dx + r, center.dy + r * 0.35, center.dx, center.dy + r * 0.9)
        ..quadraticBezierTo(
            center.dx - r, center.dy + r * 0.35, center.dx, center.dy - r);
      canvas.drawPath(path, paint);

    // --- камень --------------------------------------------------------------
    case 'shield':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r * 0.85, center.dy - r * 0.45)
        ..lineTo(center.dx + r * 0.6, center.dy + r * 0.7)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r * 0.6, center.dy + r * 0.7)
        ..lineTo(center.dx - r * 0.85, center.dy - r * 0.45)
        ..close();
      canvas.drawPath(path, paint);

    case 'plate':
      canvas.drawRect(
          Rect.fromCenter(center: center, width: r * 1.5, height: r * 1.5),
          paint);
      canvas.drawLine(at(-0.75, 0), at(0.75, 0),
          Paint()..color = Colors.black.withValues(alpha: 0.35)
            ..strokeWidth = math.max(1.0, r * 0.2));

    case 'ward':
      canvas.drawCircle(center, r * 0.9, line);
      canvas.drawCircle(center, r * 0.35, paint);

    // --- клык ----------------------------------------------------------------
    case 'fang':
      final path = Path()
        ..moveTo(center.dx - r * 0.7, center.dy - r * 0.8)
        ..lineTo(center.dx + r * 0.7, center.dy - r * 0.8)
        ..lineTo(center.dx, center.dy + r)
        ..close();
      canvas.drawPath(path, paint);

    case 'blade':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r * 0.4, center.dy + r * 0.4)
        ..lineTo(center.dx, center.dy + r * 0.75)
        ..lineTo(center.dx - r * 0.4, center.dy + r * 0.4)
        ..close();
      canvas.drawPath(path, paint);

    case 'claw':
      for (var i = -1; i <= 1; i++) {
        canvas.drawLine(
            at(i * 0.55, -0.85), at(i * 0.75, 0.85), line);
      }

    // --- искра ---------------------------------------------------------------
    case 'spark':
      for (var i = 0; i < 4; i++) {
        final angle = math.pi * i / 4;
        canvas.drawLine(
          center + Offset(math.cos(angle), math.sin(angle)) * r,
          center - Offset(math.cos(angle), math.sin(angle)) * r,
          line,
        );
      }

    case 'eye':
      final path = Path()
        ..moveTo(center.dx - r, center.dy)
        ..quadraticBezierTo(center.dx, center.dy - r * 1.1, center.dx + r, center.dy)
        ..quadraticBezierTo(center.dx, center.dy + r * 1.1, center.dx - r, center.dy)
        ..close();
      canvas.drawPath(path, line);
      canvas.drawCircle(center, r * 0.35, paint);

    // --- ветер ---------------------------------------------------------------
    case 'wind':
      for (var i = 0; i < 3; i++) {
        final y = -0.6 + i * 0.6;
        canvas.drawLine(at(-0.9, y), at(0.5 + i * 0.15, y), line);
      }

    case 'feather':
      canvas.drawLine(at(-0.7, 0.9), at(0.7, -0.9), line);
      for (var i = 1; i <= 3; i++) {
        final t = i / 4;
        final base = Offset.lerp(at(-0.7, 0.9), at(0.7, -0.9), t)!;
        canvas.drawLine(base, base + Offset(r * 0.45, r * 0.25), line);
      }

    // --- разум ---------------------------------------------------------------
    case 'mana':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r * 0.75, center.dy)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r * 0.75, center.dy)
        ..close();
      canvas.drawPath(path, paint);

    case 'spiral':
      final path = Path();
      for (var i = 0; i <= 24; i++) {
        final t = i / 24;
        final angle = t * math.pi * 3;
        final radius = r * (0.15 + 0.85 * t);
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * radius;
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, line);

    // --- добытчик ------------------------------------------------------------
    case 'coin':
      canvas.drawCircle(center, r * 0.9, line);
      canvas.drawCircle(center, r * 0.45, paint);

    case 'purse':
      canvas.drawArc(
        Rect.fromCenter(center: at(0, 0.15), width: r * 1.7, height: r * 1.7),
        0,
        math.pi,
        false,
        paint,
      );
      canvas.drawLine(at(-0.45, -0.4), at(0.45, -0.4), line);

    case 'gem':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r * 0.9, center.dy - r * 0.1)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r * 0.9, center.dy - r * 0.1)
        ..close();
      canvas.drawPath(path, line);

    // --- пиявка --------------------------------------------------------------
    case 'leech':
      final path = Path()..moveTo(center.dx - r, center.dy + r * 0.4);
      for (var i = 1; i <= 8; i++) {
        final t = i / 8;
        final x = center.dx - r + 2 * r * t;
        final y = center.dy + math.sin(t * math.pi * 2) * r * 0.5;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, line);

    case 'chalice':
      canvas.drawArc(
        Rect.fromCenter(center: at(0, -0.2), width: r * 1.5, height: r * 1.4),
        0,
        math.pi,
        false,
        paint,
      );
      canvas.drawLine(at(0, 0.5), at(0, 0.9), line);
      canvas.drawLine(at(-0.5, 0.9), at(0.5, 0.9), line);


    // --- стихии --------------------------------------------------------------
    case 'flame':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..cubicTo(center.dx + r * 0.9, center.dy - r * 0.1,
            center.dx + r * 0.55, center.dy + r, center.dx, center.dy + r)
        ..cubicTo(center.dx - r * 0.55, center.dy + r,
            center.dx - r * 0.9, center.dy - r * 0.1, center.dx,
            center.dy - r);
      canvas.drawPath(path, paint);

    case 'ember':
      canvas.drawCircle(center + Offset(0, r * 0.25), r * 0.5, paint);
      for (var i = 0; i < 3; i++) {
        final a = -math.pi / 2 + (i - 1) * 0.7;
        canvas.drawLine(
          center + Offset(math.cos(a) * r * 0.55, math.sin(a) * r * 0.55),
          center + Offset(math.cos(a) * r, math.sin(a) * r),
          line,
        );
      }

    case 'snowflake':
      for (var i = 0; i < 3; i++) {
        final a = i * math.pi / 3;
        canvas.drawLine(
          center - Offset(math.cos(a) * r, math.sin(a) * r),
          center + Offset(math.cos(a) * r, math.sin(a) * r),
          line,
        );
      }
      canvas.drawCircle(center, r * 0.22, paint);

    case 'icicle':
      final path = Path()
        ..moveTo(center.dx - r * 0.55, center.dy - r * 0.8)
        ..lineTo(center.dx + r * 0.55, center.dy - r * 0.8)
        ..lineTo(center.dx, center.dy + r)
        ..close();
      canvas.drawPath(path, paint);

    case 'bolt':
      final path = Path()
        ..moveTo(center.dx + r * 0.35, center.dy - r)
        ..lineTo(center.dx - r * 0.5, center.dy + r * 0.15)
        ..lineTo(center.dx + r * 0.08, center.dy + r * 0.15)
        ..lineTo(center.dx - r * 0.3, center.dy + r)
        ..lineTo(center.dx + r * 0.6, center.dy - r * 0.2)
        ..lineTo(center.dx, center.dy - r * 0.2)
        ..close();
      canvas.drawPath(path, paint);

    case 'cloud':
      canvas.drawCircle(at(-0.4, -0.1), r * 0.45, paint);
      canvas.drawCircle(at(0.35, -0.15), r * 0.4, paint);
      canvas.drawCircle(at(0, -0.4), r * 0.5, paint);
      canvas.drawLine(at(-0.15, 0.35), at(-0.35, 0.95), line);
      canvas.drawLine(at(0.35, 0.3), at(0.15, 0.9), line);

    case 'rift':
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..quadraticBezierTo(
            center.dx + r * 0.75, center.dy, center.dx, center.dy + r)
        ..quadraticBezierTo(
            center.dx - r * 0.75, center.dy, center.dx, center.dy - r);
      canvas.drawPath(path, line);
      canvas.drawCircle(center, r * 0.2, paint);

    case 'skull':
      canvas.drawCircle(at(0, -0.15), r * 0.72, paint);
      final jaw = Rect.fromCenter(
          center: at(0, 0.6), width: r * 0.9, height: r * 0.55);
      canvas.drawRect(jaw, paint);

    case 'rune':
      canvas.drawLine(at(0, -1), at(0, 1), line);
      canvas.drawLine(at(0, -0.5), at(0.7, -1), line);
      canvas.drawLine(at(0, 0.2), at(-0.7, -0.3), line);

    case 'orb':
      canvas.drawCircle(center, r * 0.85, line);
      canvas.drawCircle(at(-0.25, -0.3), r * 0.28, paint);

    // --- дорога и всё, чего нет в списке -------------------------------------
    default:
      canvas.drawCircle(center, r * 0.55, paint);
  }
}
