import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rift_app/game/battle_scene.dart';
import 'package:rift_app/game/silhouettes.dart';

/// Волна уже однажды вылезала за край экрана: размер фигур считался от высоты
/// телефона, а не от полосы, в которую они обязаны поместиться. Ошибку нашёл
/// эмулятор, потому что проверить её было нечем — рисование не возвращает
/// чисел. Теперь геометрия отделена от рисования и проверяется числами.
void main() {
  const screens = [
    (360.0, 640.0), // тесный экран
    (411.0, 914.0), // высокий телефон, на котором и вылезло
    (800.0, 1280.0), // планшет
  ];

  test('пачка любого размера помещается в свою полосу', () {
    for (final (width, height) in screens) {
      for (final id in [...knownSilhouetteIds, '']) {
        final look = silhouetteFor(id);
        for (var count = 1; count <= 8; count++) {
          for (final scale in [1.0, 1.7]) {
            final left = width * 0.36;
            final right = width * 0.95;
            final layout = WaveLayout.compute(
              count: count,
              left: left,
              right: right,
              screenHeight: height,
              aspect: look.aspect,
              scale: scale,
            );

            final where = '$id x$count на ${width}x$height (масштаб $scale)';
            expect(layout.positions.first - layout.figureWidth / 2,
                greaterThanOrEqualTo(left - 0.01),
                reason: '$where: левый край');
            expect(layout.positions.last + layout.figureWidth / 2,
                lessThanOrEqualTo(right + 0.01),
                reason: '$where: правый край');
          }
        }
      }
    }
  });

  test('соседи не налезают друг на друга', () {
    // Четверо — предел одного ряда: пятеро уже встают двумя, и соседние
    // индексы там принадлежат разным рядам.
    final layout = WaveLayout.compute(
      count: 4,
      left: 140,
      right: 390,
      screenHeight: 914,
      aspect: 1.0,
    );

    for (var i = 1; i < layout.positions.length; i++) {
      final space = layout.positions[i] - layout.positions[i - 1];
      expect(space, greaterThan(layout.figureWidth),
          reason: 'между фигурами должен остаться зазор');
    }
  });

  test('волна из одного и волна из пяти стоят по одному центру', () {
    // Иначе бой прыгает по экрану на каждой смене врага. Считается по
    // среднему: с двумя рядами крайние фигуры принадлежат разным рядам,
    // и «первая плюс последняя» центром больше не является.
    double centerOf(int count) {
      final l = WaveLayout.compute(
          count: count, left: 140, right: 390, screenHeight: 914, aspect: 0.9);
      return l.positions.reduce((a, b) => a + b) / l.positions.length;
    }

    expect(centerOf(1), closeTo(265.0, 0.01));
    expect(centerOf(5), closeTo(265.0, 12.0),
        reason: 'пачка держится центра полосы');
  });

  test('пустая волна не роняет раскладку', () {
    final layout = WaveLayout.compute(
        count: 0, left: 140, right: 390, screenHeight: 914, aspect: 0.9);
    expect(layout.positions, isEmpty);
    expect(layout.height, greaterThan(0));
  });

  group('линия земли', () {
    test('композиция стоит по центру полосы, а не на её доле', () {
      // На высоком телефоне линия на 74 % высоты оставляла над бойцами
      // пустое поле в половину экрана — это и увидел эмулятор.
      final ground = groundLineFor(fieldHeight: 580, tallest: 120);

      final above = ground - 120;
      final below = 580 - ground;
      expect((above - below).abs(), lessThan(30),
          reason: 'сверху и снизу должно остаться поровну');
    });

    test('над фигурой всегда есть место на полоску', () {
      final ground = groundLineFor(fieldHeight: 300, tallest: 150);
      expect(ground, greaterThanOrEqualTo(150 * 1.25 - 0.01));
    });

    test('низкая полоса не роняет расчёт', () {
      // Границы сходятся, и «просто clamp» здесь падает.
      for (final height in [0.0, 10.0, 60.0, 100.0]) {
        final ground = groundLineFor(fieldHeight: height, tallest: 120);
        expect(ground, greaterThanOrEqualTo(0.0));
        expect(ground, lessThanOrEqualTo(math.max(0.0, height)));
      }
    });
  });

  group('большая пачка встаёт двумя рядами', () {
    test('шестеро крупнее, чем если бы стояли в одну строку', () {
      // В одну строку шесть мобов делят полосу на шесть и превращаются
      // в точки, хотя над ними пустует половина арены.
      final four = WaveLayout.compute(
          count: 4, left: 148, right: 390, screenHeight: 336, aspect: 0.85);
      final six = WaveLayout.compute(
          count: 6, left: 148, right: 390, screenHeight: 336, aspect: 0.85);

      expect(six.height, greaterThan(four.height * 0.7),
          reason: 'шестеро всего на ряд больше, а не вдвое мельче');
      expect(six.positions, hasLength(6));
      expect(six.lifts.where((l) => l > 0), hasLength(3),
          reason: 'половина ушла в задний ряд');
    });

    test('до четверых ряд один', () {
      for (var count = 1; count <= 4; count++) {
        final layout = WaveLayout.compute(
            count: count, left: 148, right: 390, screenHeight: 336,
            aspect: 0.85);
        expect(layout.lifts.every((l) => l == 0.0), isTrue,
            reason: 'пачка из $count не нуждается во втором ряде');
      }
    });

    test('задний ряд смещён, а не спрятан за передним', () {
      final layout = WaveLayout.compute(
          count: 6, left: 148, right: 390, screenHeight: 336, aspect: 0.85);

      final front = [
        for (var i = 0; i < layout.positions.length; i++)
          if (layout.lifts[i] == 0.0) layout.positions[i],
      ];
      final back = [
        for (var i = 0; i < layout.positions.length; i++)
          if (layout.lifts[i] > 0.0) layout.positions[i],
      ];

      for (final x in back) {
        for (final f in front) {
          expect((x - f).abs(), greaterThan(layout.figureWidth * 0.3),
              reason: 'фигура заднего ряда прячется ровно за передней');
        }
      }
    });

    test('оба ряда помещаются в полосу', () {
      for (var count = 5; count <= 10; count++) {
        final layout = WaveLayout.compute(
            count: count, left: 148, right: 390, screenHeight: 336,
            aspect: 1.05);

        for (final x in layout.positions) {
          expect(x - layout.figureWidth / 2, greaterThanOrEqualTo(148 - 0.01),
              reason: 'пачка из $count вылезла слева');
          expect(x + layout.figureWidth / 2, lessThanOrEqualTo(390 + 0.01),
              reason: 'пачка из $count вылезла справа');
        }
      }
    });
  });
}
