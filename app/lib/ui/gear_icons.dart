import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:rift/core/model/gear.dart';

/// Иконки снаряжения, нарисованные кодом.
///
/// Системный набор Material сюда не годился: в бою фигуры — плоские силуэты
/// с одной заливкой и акцентом, а рядом в сетке стояли тонкие контурные
/// глифы из другой игры. Одна и та же вещь выглядела двумя разными способами
/// на соседних экранах.
///
/// Рисование в единичных координатах, как у силуэтов бестиария: `0..1` по
/// обеим осям, начало — левый верхний угол клетки. Значит одна и та же форма
/// одинаково собрана и в списке на 18 пикселей, и в сетке на 24.
class GearIcon extends StatelessWidget {
  const GearIcon({
    super.key,
    required this.kind,
    required this.size,
    required this.color,
    this.accent,
  });

  final GearKind kind;
  final double size;

  /// Основной цвет — обычно цвет редкости предмета.
  final Color color;

  /// Второй цвет: рукоять, ремни, прорезь шлема. По умолчанию — ЗАТЕМНЁННЫЙ
  /// основной, а не полупрозрачный: прозрачный акцент поверх заливки того же
  /// цвета даёт ровно тот же цвет, и вся внутренняя деталировка пропадала —
  /// щит выходил однотонным пятном, а шлем терял прорезь.
  final Color? accent;

  static Color darken(Color color) =>
      Color.lerp(color, const Color(0xFF120D0B), 0.55)!;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GearPainter(
            kind: kind,
            color: color,
            accent: accent ?? GearIcon.darken(color),
          ),
        ),
      );
}

/// Рисовальщик одной иконки. Отдельно от виджета, чтобы форму можно было
/// проверить тестом, не собирая дерево.
class _GearPainter extends CustomPainter {
  _GearPainter({
    required this.kind,
    required this.color,
    required this.accent,
  });

  final GearKind kind;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    paintGearIcon(
      canvas: canvas,
      kind: kind,
      size: size.shortestSide,
      color: color,
      accent: accent,
    );
  }

  @override
  bool shouldRepaint(_GearPainter old) =>
      old.kind != kind || old.color != color || old.accent != accent;
}

/// Рисует иконку снаряжения в квадрат со стороной [size] от начала координат.
void paintGearIcon({
  required Canvas canvas,
  required GearKind kind,
  required double size,
  required Color color,
  required Color accent,
}) {
  final pen = _Pen(canvas, size, color, accent);
  switch (kind) {
    case GearKind.weapon:
      _weapon(pen);
    case GearKind.offhand:
      _shield(pen);
    case GearKind.helmet:
      _helmet(pen);
    case GearKind.armor:
      _armor(pen);
    case GearKind.gloves:
      _glove(pen);
    case GearKind.boots:
      _boot(pen);
    case GearKind.ring:
      _ring(pen);
    case GearKind.amulet:
      _amulet(pen);
  }
}

/// Тот же словарь фигур, что у силуэтов бестиария: заливка, линия с круглыми
/// торцами и кольцо. Больше примитивов не нужно — а меньше уже не хватает.
class _Pen {
  _Pen(this.canvas, this.size, Color body, Color accent)
      : _body = Paint()..color = body,
        _accent = Paint()..color = accent;

  final Canvas canvas;
  final double size;
  final Paint _body;
  final Paint _accent;

  Paint _paint(bool accent) => accent ? _accent : _body;

  Offset at(double x, double y) => Offset(x * size, y * size);

  void poly(List<Offset> points, {bool accent = false}) {
    final first = at(points.first.dx, points.first.dy);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = at(p.dx, p.dy);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path..close(), _paint(accent));
  }

  void line(double x1, double y1, double x2, double y2, double w,
          {bool accent = false}) =>
      canvas.drawLine(
        at(x1, y1),
        at(x2, y2),
        _paint(accent)
          ..strokeWidth = w * size
          ..strokeCap = StrokeCap.round,
      );

  void circle(double x, double y, double r, {bool accent = false}) =>
      canvas.drawCircle(at(x, y), r * size, _paint(accent));

  void oval(double x, double y, double w, double h, {bool accent = false}) =>
      canvas.drawOval(
        Rect.fromCenter(
            center: at(x, y), width: w * size, height: h * size),
        _paint(accent),
      );

  void ring(double x, double y, double outer, double inner,
      {bool accent = false}) {
    final c = at(x, y);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: outer * size))
        ..addOval(Rect.fromCircle(center: c, radius: inner * size)),
      _paint(accent),
    );
  }
}

// --- Формы -------------------------------------------------------------------
//
// У каждой вещи один узнаваемый признак, а не подробный рисунок: на 18
// пикселях подробности превращаются в грязь. Меч — клинок и крестовина,
// шлем — купол и прорезь, сапог — подошва.

void _weapon(_Pen p) {
  // Клинок острием вверх: по нему оружие отличается от щита даже в углу
  // строки списка.
  p.poly(const [
    Offset(0.50, 0.06),
    Offset(0.62, 0.26),
    Offset(0.58, 0.66),
    Offset(0.42, 0.66),
    Offset(0.38, 0.26),
  ]);
  p.line(0.28, 0.68, 0.72, 0.68, 0.09, accent: true);
  p.line(0.50, 0.72, 0.50, 0.92, 0.07, accent: true);
  p.circle(0.50, 0.94, 0.055, accent: true);
}

void _shield(_Pen p) {
  p.poly(const [
    Offset(0.50, 0.06),
    Offset(0.88, 0.20),
    Offset(0.82, 0.60),
    Offset(0.50, 0.94),
    Offset(0.18, 0.60),
    Offset(0.12, 0.20),
  ]);
  p.line(0.50, 0.24, 0.50, 0.74, 0.07, accent: true);
  p.line(0.28, 0.40, 0.72, 0.40, 0.07, accent: true);
}

void _helmet(_Pen p) {
  // Купол собран по дуге, а не прямой крышей: угловатый верх читался
  // коробкой. Прорезь — вырез в силуэте, а не линия поверх: линия того же
  // цвета не видна, а вырез виден всегда.
  p.poly(const [
    Offset(0.18, 0.52),
    Offset(0.20, 0.37),
    Offset(0.27, 0.24),
    Offset(0.38, 0.15),
    Offset(0.50, 0.12),
    Offset(0.62, 0.15),
    Offset(0.73, 0.24),
    Offset(0.80, 0.37),
    Offset(0.82, 0.52),
    Offset(0.82, 0.88),
    Offset(0.18, 0.88),
  ]);
  p.poly(const [
    Offset(0.24, 0.44),
    Offset(0.76, 0.44),
    Offset(0.76, 0.58),
    Offset(0.24, 0.58),
  ], accent: true);
  p.poly(const [
    Offset(0.45, 0.58),
    Offset(0.55, 0.58),
    Offset(0.55, 0.88),
    Offset(0.45, 0.88),
  ], accent: true);
}

void _armor(_Pen p) {
  // Кираса: широкие плечи с вырезом под шею и сужение к поясу. Наплечники
  // отдельными овалами читались ушами, а тонкий торс между ними — зверьком.
  p.poly(const [
    Offset(0.16, 0.34),
    Offset(0.24, 0.24),
    Offset(0.40, 0.20),
    Offset(0.50, 0.30),
    Offset(0.60, 0.20),
    Offset(0.76, 0.24),
    Offset(0.84, 0.34),
    Offset(0.76, 0.44),
    Offset(0.72, 0.66),
    Offset(0.50, 0.90),
    Offset(0.28, 0.66),
    Offset(0.24, 0.44),
  ]);
  p.line(0.30, 0.62, 0.70, 0.62, 0.08, accent: true);
  p.line(0.50, 0.36, 0.50, 0.58, 0.05, accent: true);
}

void _glove(_Pen p) {
  // Латная перчатка: пальцы, отставленный большой и широкий раструб.
  for (var i = 0; i < 3; i++) {
    final x = 0.38 + i * 0.13;
    p.line(x, 0.34, x, 0.12, 0.085);
  }
  p.line(0.28, 0.46, 0.13, 0.58, 0.10);
  p.poly(const [
    Offset(0.30, 0.32),
    Offset(0.70, 0.32),
    Offset(0.74, 0.66),
    Offset(0.50, 0.82),
    Offset(0.26, 0.66),
  ]);
  p.poly(const [
    Offset(0.26, 0.70),
    Offset(0.74, 0.70),
    Offset(0.68, 0.92),
    Offset(0.32, 0.92),
  ], accent: true);
}

void _boot(_Pen p) {
  // Голенище и подошва: угол внизу — то, чем сапог отличается от перчатки.
  p.poly(const [
    Offset(0.32, 0.10),
    Offset(0.60, 0.10),
    Offset(0.60, 0.58),
    Offset(0.88, 0.70),
    Offset(0.88, 0.86),
    Offset(0.32, 0.86),
  ]);
  p.line(0.28, 0.90, 0.90, 0.90, 0.075, accent: true);
}

void _ring(_Pen p) {
  p.ring(0.50, 0.60, 0.30, 0.17);
  p.poly(const [
    Offset(0.50, 0.06),
    Offset(0.64, 0.20),
    Offset(0.50, 0.34),
    Offset(0.36, 0.20),
  ], accent: true);
}

void _amulet(_Pen p) {
  // Цепь дугой и подвеска: без цепи это просто камень.
  final chain = Path()
    ..moveTo(p.at(0.16, 0.16).dx, p.at(0.16, 0.16).dy)
    ..quadraticBezierTo(
      p.at(0.50, 0.66).dx,
      p.at(0.50, 0.66).dy,
      p.at(0.84, 0.16).dx,
      p.at(0.84, 0.16).dy,
    );
  p.canvas.drawPath(
    chain,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.075 * p.size
      ..strokeCap = StrokeCap.round
      ..color = p._accent.color,
  );

  p.poly(const [
    Offset(0.50, 0.50),
    Offset(0.70, 0.70),
    Offset(0.50, 0.94),
    Offset(0.30, 0.70),
  ]);
}

/// Заглушка для слота, который занят двуручником: рисуется вместо иконки
/// левой руки. Своя форма, а не системный «запрет»: перечёркнутый круг из
/// другого набора выбивался сильнее всего.
void paintBlockedSlot({
  required Canvas canvas,
  required double size,
  required Color color,
}) {
  final pen = _Pen(canvas, size, color, color);
  pen.ring(0.5, 0.5, 0.34, 0.26);
  pen.line(0.28, 0.28, 0.72, 0.72, 0.08);
}

/// Угол наклона, под которым иконка выглядит «лежащей в слоте», а не
/// приклеенной к сетке. Нужен только сетке — в списках иконки стоят ровно.
const double gearIconTilt = -math.pi / 24;
