import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

void main() {
  group('детерминизм', () {
    test('одинаковый сид даёт одинаковую последовательность', () {
      final a = Rng(12345);
      final b = Rng(12345);
      for (var i = 0; i < 1000; i++) {
        expect(a.nextRaw(), b.nextRaw());
      }
    });

    test('поток определяется координатами события, а не порядком вызовов', () {
      // Дроп нельзя переролльнуть, закрыв приложение: сид зависит от
      // (ран, глубина, волна, назначение), а не от того, сколько раз
      // ГСЧ уже дёргали до этого.
      final first = Rng.stream(7, 42, 1, RngPurpose.lootRoll);
      final scrambler = Rng.stream(7, 42, 1, RngPurpose.combat);
      for (var i = 0; i < 100; i++) {
        scrambler.nextRaw();
      }
      final second = Rng.stream(7, 42, 1, RngPurpose.lootRoll);
      expect(second.nextDouble(), first.nextDouble());
    });

    test('разные назначения дают независимые потоки', () {
      final loot = Rng.stream(7, 42, 1, RngPurpose.lootRoll);
      final combat = Rng.stream(7, 42, 1, RngPurpose.combat);
      expect(loot.nextRaw(), isNot(combat.nextRaw()));
    });

    test('соседние этажи не коррелируют', () {
      final values = <double>{};
      for (var d = 1; d <= 200; d++) {
        values.add(Rng.stream(7, d, 0, RngPurpose.lootRoll).nextDouble());
      }
      expect(values.length, 200);
    });
  });

  group('распределение', () {
    test('nextDouble лежит в [0,1)', () {
      final r = Rng(999);
      for (var i = 0; i < 20000; i++) {
        final v = r.nextDouble();
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThan(1.0));
      }
    });

    test('среднее близко к 0.5', () {
      final r = Rng(1);
      var sum = 0.0;
      const n = 200000;
      for (var i = 0; i < n; i++) {
        sum += r.nextDouble();
      }
      expect(sum / n, closeTo(0.5, 0.01));
    });

    test('nextInt покрывает диапазон и не выходит за него', () {
      final r = Rng(5);
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        final v = r.nextInt(9);
        expect(v, inInclusiveRange(0, 8));
        seen.add(v);
      }
      expect(seen.length, 9);
    });

    test('chance выдаёт заявленную частоту', () {
      final r = Rng(77);
      var hits = 0;
      const n = 100000;
      for (var i = 0; i < n; i++) {
        if (r.chance(0.25)) hits++;
      }
      expect(hits / n, closeTo(0.25, 0.01));
    });

    test('граничные вероятности не требуют вызова ГСЧ', () {
      final r = Rng(3);
      final before = r.nextRaw();
      expect(r.chance(0.0), isFalse);
      expect(r.chance(1.0), isTrue);
      final after = Rng(3)..nextRaw();
      expect(r.nextRaw(), after.nextRaw());
      expect(before, isNotNull);
    });
  });

  test('fork даёт независимый поток, не сдвигая основной', () {
    final main = Rng(31337);
    final reference = Rng(31337);
    final branch = main.fork(1);
    branch.nextRaw();
    // fork читает состояние, но не двигает его: основной поток обязан
    // выдать ровно то же, что и нетронутый ГСЧ с тем же сидом.
    expect(main.nextRaw(), reference.nextRaw());
    expect(main.fork(1).nextRaw(), isNot(main.fork(2).nextRaw()));
  });
}
