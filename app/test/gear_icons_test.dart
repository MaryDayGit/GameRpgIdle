import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift_app/ui/gear_icons.dart';

/// Иконки рисуются кодом, значит их форму можно проверить числами — как и
/// силуэты бестиария. Проверяется не красота, а два обещания: иконка есть у
/// каждого типа предмета и она помещается в свою клетку.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('у каждого типа предмета своя иконка', () {
    // Форма сравнивается по границам нарисованного: две одинаковые иконки
    // означают, что игрок не отличит кольцо от амулета в сетке.
    final shapes = <GearKind, String>{};
    for (final kind in GearKind.values) {
      shapes[kind] = _fingerprint(kind);
    }

    expect(shapes.values.toSet(), hasLength(GearKind.values.length),
        reason: 'нашлись одинаковые иконки: $shapes');
  });

  test('иконка не вылезает за свою клетку', () {
    // Иначе в сетке снаряжения фигуры налезут на рамку слота.
    for (final kind in GearKind.values) {
      final bounds = _boundsOf(kind);
      expect(bounds.left, greaterThanOrEqualTo(-0.01), reason: '$kind слева');
      expect(bounds.top, greaterThanOrEqualTo(-0.01), reason: '$kind сверху');
      expect(bounds.right, lessThanOrEqualTo(100.01), reason: '$kind справа');
      expect(bounds.bottom, lessThanOrEqualTo(100.01), reason: '$kind снизу');
    }
  });

  test('иконка занимает клетку, а не теряется в ней', () {
    for (final kind in GearKind.values) {
      final bounds = _boundsOf(kind);
      expect(bounds.width, greaterThan(30.0), reason: '$kind слишком узкая');
      expect(bounds.height, greaterThan(50.0), reason: '$kind слишком низкая');
    }
  });

  test('заглушка занятого слота рисуется', () {
    final probe = _Bounds();
    expect(
      () => paintBlockedSlot(
          canvas: probe, size: 100, color: const Color(0xFFFFFFFF)),
      returnsNormally,
    );
    expect(probe.bounds.width, greaterThan(30.0));
  });
}

String _fingerprint(GearKind kind) {
  final probe = _Bounds();
  paintGearIcon(
    canvas: probe,
    kind: kind,
    size: 100,
    color: const Color(0xFFFFFFFF),
    accent: const Color(0xFF888888),
  );
  final b = probe.bounds;
  return '${probe.calls}:${b.left.toStringAsFixed(1)},'
      '${b.top.toStringAsFixed(1)},${b.width.toStringAsFixed(1)},'
      '${b.height.toStringAsFixed(1)}';
}

Rect _boundsOf(GearKind kind) {
  final probe = _Bounds();
  paintGearIcon(
    canvas: probe,
    kind: kind,
    size: 100,
    color: const Color(0xFFFFFFFF),
    accent: const Color(0xFF888888),
  );
  return probe.bounds;
}

/// Холст, который ничего не рисует, а запоминает, куда просили рисовать.
class _Bounds implements Canvas {
  Rect bounds = Rect.zero;
  int calls = 0;
  var _empty = true;

  void _add(Rect r) {
    bounds = _empty ? r : bounds.expandToInclude(r);
    _empty = false;
    calls++;
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      _add(Rect.fromCircle(center: c, radius: radius));

  @override
  void drawOval(Rect rect, Paint paint) => _add(rect);

  @override
  void drawRect(Rect rect, Paint paint) => _add(rect);

  @override
  void drawPath(Path path, Paint paint) => _add(path.getBounds());

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      _add(Rect.fromPoints(p1, p2).inflate(paint.strokeWidth / 2));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
