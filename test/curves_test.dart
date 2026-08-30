import 'dart:math' as math;

import 'package:rift/core/balance/curves.dart';
import 'package:test/test.dart';

void main() {
  group('эффективная глубина', () {
    test('монотонна и не превышает сырую глубину', () {
      var prev = -1.0;
      for (var d = 0; d <= 500; d++) {
        final v = Curves.dEff(d);
        expect(v, greaterThanOrEqualTo(prev));
        expect(v, lessThanOrEqualTo(d.toDouble()));
        prev = v;
      }
    });

    test('на малых глубинах ведёт себя почти квадратично (мягкий разгон)', () {
      // d_eff ≈ d²/(2τ) при d << τ.
      for (final d in [2, 4, 6]) {
        final approx = d * d / (2 * Curves.tau);
        expect(Curves.dEff(d), closeTo(approx, approx * 0.15));
      }
    });

    test('глубоко вырождается в d − τ', () {
      expect(Curves.dEff(500), closeTo(500 - Curves.tau, 0.001));
    });

    test('таблица совпадает с закрытой формой за её пределами', () {
      // Граница таблицы не должна давать разрыв: офлайн-модель и симуляция
      // обязаны получать одно и то же число по обе стороны от неё.
      final inside = Curves.dEff(1999);
      final outside = Curves.dEff(2001);
      expect(outside - inside, closeTo(2.0, 1e-6));
    });
  });

  /// Три неравенства, на которых стоит вся прогрессия.
  ///
  /// Они выведены, а не назначены, и каждое ломает игру целиком, если
  /// перестаёт выполняться. Раньше здесь проверялась ДРУГАЯ формула — та, что
  /// выводила рост предметов из целевого удлинения спуска. Она держалась на
  /// том, что наёмник подбирает снаряжение прямо в спуске; наёмник перестал,
  /// и вывод сломался качественно: старая формула при любом положительном
  /// целевом удлинении даёт `g < sqrt(a·b)`, то есть добыча ВСЕГДА отстаёт от
  /// глубины и цикл «нашёл вещь — прошёл дальше» не может быть двигателем.
  group('формула стены', () {
    test('добыча двигает прогресс: g > sqrt(a·b)', () {
      // Снаряжение, добытое на глубине D, уводит следующий спуск на
      // D · 2·ln(g)/ln(a·b). Меньше единицы — игру вперёд тянут только
      // деревья, а поиск вещей становится украшением.
      final geometric =
          math.sqrt(Curves.mobHpGrowth * Curves.mobDpsGrowth);
      expect(Curves.itemGrowth, greaterThan(geometric));
      expect(Curves.lootLoopGain, greaterThan(1.0));
    });

    test('спуск обрывает смерть, а не бесконечно медленный этаж', () {
      // Порог ровно один: g < b. Если это перестанет выполняться, герой
      // станет относительно танковее с глубиной и вместо гибели упрётся в
      // непроходимый по времени этаж — тезис «смерть = прести́ж» сломается
      // молча.
      expect(Curves.deathEndsRuns, isTrue);
      expect(Curves.itemGrowth, lessThan(Curves.mobDpsGrowth));
    });

    test('оба условия выполнимы только при a < b', () {
      // sqrt(a·b) < b ⟺ a < b. HP мобов обязано расти медленнее их урона:
      // иначе этажи становятся долгими быстрее, чем опасными, и места для
      // роста предметов между двумя порогами просто не остаётся.
      expect(Curves.mobHpGrowth, lessThan(Curves.mobDpsGrowth));
    });

    test('удвоение сборки покупает этажи, и покупает заметно', () {
      // Сила внутри спуска заморожена, поэтому Δd = ln4/ln(a·b) и зависит
      // только от кривой мобов. Числа ниже — не догма, а границы здравого
      // смысла: меньше пяти этажей за удвоение — вложение не чувствуется,
      // больше тридцати — стены нет вовсе.
      expect(Curves.runExtensionPerDoubling, inInclusiveRange(5.0, 30.0));
    });

    test('замедление перед стеной заметно игроку', () {
      // За последние 40 этажей этаж обязан ощутимо замедлиться,
      // иначе смерть приходит без предупреждения (GDD §2.4).
      expect(Curves.slowdownOver(40), greaterThan(2.5));
    });
  });

  group('броня', () {
    test('митигация ограничена капом', () {
      expect(Curves.armorMitigation(1e12, 50), closeTo(Curves.armorDrCap, 1e-9));
    });

    test('нулевая и отрицательная броня не лечит', () {
      expect(Curves.armorMitigation(0.0, 50), 0.0);
      expect(Curves.armorMitigation(-100.0, 50), 0.0);
    });

    test('доля снижения не плывёт с глубиной при снаряжении в темп', () {
      // Броня растёт как снаряжение, знаменатель — тоже. Значит игрок,
      // держащий долю брони в билде постоянной, получает постоянную защиту.
      final shallow = Curves.armorMitigation(100 * Curves.itemScale(10), 10);
      final deep = Curves.armorMitigation(100 * Curves.itemScale(150), 150);
      expect(deep, closeTo(shallow, 1e-9));
    });
  });

  group('Эхо', () {
    test('строго растёт с глубиной', () {
      for (var d = 1; d < 200; d++) {
        expect(Curves.echo(d + 1), greaterThanOrEqualTo(Curves.echo(d)));
      }
    });

    test('экспоненциально по глубине, а не полиномиально', () {
      // Ключевое требование меты: глубина логарифмична по силе билда,
      // поэтому валюта обязана быть экспоненциальной по глубине —
      // иначе прести́ж затухает к десятому рану (docs/01-ANALYSIS.md §2).
      final ratio = Curves.echo(140) / Curves.echo(100);
      expect(ratio, closeTo(math.pow(Curves.echoGrowth, 40).toDouble(), 0.05));
    });

    test('Клеймо Бездны почти нейтрально по награде', () {
      // Ранг стоит ~1.7 этажа глубины и даёт +12 % Эха. Чистый выигрыш
      // должен быть небольшим плюсом за мастерство, а не налогом на казуала.
      const depth = 100;
      final plain = Curves.echo(depth);
      final branded = Curves.echo(depth - 9, brandRank: 5);
      final gain = branded / plain;
      expect(gain, greaterThan(0.95));
      expect(gain, lessThan(1.35));
    });

    test('нулевая глубина не даёт Эха', () {
      expect(Curves.echo(0), 0);
      expect(Curves.echo(-5), 0);
    });
  });
}
