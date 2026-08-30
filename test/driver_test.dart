import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Пошаговый прогон и батч обязаны совпадать побитово.
///
/// Если разойдутся — на экране игрок увидит один бой, а офлайн-догонялка
/// посчитает другой. Это ровно тот отказ, ради которого симуляция вообще
/// вынесена в отдельное ядро (`docs/01-ANALYSIS.md` §3).

RunResult _batch(int seed, {double power = 1.0}) => DescentSimulator(
      profile: HeroProfile(powerMultiplier: power),
      seed: seed,
    ).run(floorCap: 2000);

DescentDriver _driver(int seed, {double power = 1.0}) => DescentDriver(
      profile: HeroProfile(powerMultiplier: power),
      seed: seed,
      floorCap: 2000,
    );

void _same(RunResult a, RunResult b, {String reason = ''}) {
  expect(a.maxDepth, b.maxDepth, reason: 'maxDepth $reason');
  expect(a.ending, b.ending, reason: 'ending $reason');
  expect(a.totalSeconds, b.totalSeconds, reason: 'totalSeconds $reason');
  expect(a.echo, b.echo, reason: 'echo $reason');
  expect(a.gold, b.gold, reason: 'gold $reason');
  expect(a.itemsFound, b.itemsFound, reason: 'itemsFound $reason');
  expect(a.haul.itemCount, b.haul.itemCount, reason: 'haul $reason');
  expect(a.floors.length, b.floors.length, reason: 'floors $reason');
  for (var i = 0; i < a.floors.length; i++) {
    expect(a.floors[i].seconds, b.floors[i].seconds, reason: 'floor $i $reason');
    expect(a.floors[i].damageTaken, b.floors[i].damageTaken,
        reason: 'floor $i урон $reason');
  }
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  test('пошагово по одному тику — тот же ран, что и батчем', () {
    final driver = _driver(42);
    var guard = 0;
    while (!driver.finished) {
      driver.tick();
      if (++guard > 5000000) fail('ран не заканчивается');
    }
    _same(driver.result, _batch(42));
  });

  test('размер шага не влияет на результат', () {
    // Шаги нарочно не кратны тику: остаток обязан копиться, а не теряться.
    for (final step in [0.1, 1.0, 7.3, 60.0, 3600.0]) {
      final driver = _driver(1234, power: 2.0);
      while (!driver.finished) {
        driver.advance(step);
      }
      _same(driver.result, _batch(1234, power: 2.0), reason: 'шаг $step');
    }
  });

  test('один вызов на всю длину рана — это офлайн-догонялка', () {
    final driver = _driver(77);
    final ticks = driver.advance(365 * 24 * 3600.0);

    expect(driver.finished, isTrue);
    expect(ticks, greaterThan(0));
    _same(driver.result, _batch(77));
  });

  test('снимок состояния осмыслен по ходу спуска', () {
    final driver = _driver(9);
    final depths = <int>{};
    var rested = false;

    var guard = 0;
    while (!driver.finished && guard < 200000) {
      driver.tick();
      guard++;

      final s = driver.snapshot;
      if (s.finished) break;

      depths.add(s.depth);
      if (s.resting) rested = true;
      expect(s.heroHpFraction, inInclusiveRange(0.0, 1.0));
      expect(s.waveProgress, inInclusiveRange(0.0, 1.0));
      expect(s.waveIndex, inInclusiveRange(1, s.waveCount));
      expect(s.enemiesAlive, greaterThanOrEqualTo(0));

      // На отдыхе врага нет, и это состояние: наёмник идёт между этажами.
      // Пустое имя тут честнее выдуманного.
      if (!s.resting) expect(s.enemyName, isNotEmpty);
    }

    expect(depths.length, greaterThan(3), reason: 'герой должен спускаться');
    expect(rested, isTrue,
        reason: 'переход между этажами обязан занимать время');
  });

  test('после конца рана шаги ничего не меняют', () {
    final driver = _driver(5);
    driver.advance(1e9);
    expect(driver.finished, isTrue);

    final before = driver.result;
    driver.tick();
    expect(driver.advance(1000.0), 0);
    expect(driver.result.totalSeconds, before.totalSeconds);
    expect(driver.result.maxDepth, before.maxDepth);
  });

  test('нулевой потолок этажей заканчивает ран сразу', () {
    final driver = DescentDriver(
      profile: HeroProfile(),
      seed: 1,
      floorCap: 0,
    );
    expect(driver.finished, isTrue);
    expect(driver.result.ending, RunEnding.floorCap);
    expect(driver.result.floors, isEmpty);
    expect(driver.wave, isNull);
  });

  test('часы идут внутри этажа, а не скачками между ними', () {
    // От этого зависит всё, что показывает бой: перемотка по времени
    // завершённых этажей всегда попадала бы на их границы.
    final driver = _driver(42);

    var previous = 0.0;
    var grewInsideFloor = false;
    final floorBoundaries = <double>{};

    for (var i = 0; i < 3000 && !driver.finished; i++) {
      driver.tick();
      final elapsed = driver.elapsedSeconds;

      expect(elapsed, greaterThanOrEqualTo(previous),
          reason: 'время не может идти назад');
      if (elapsed > previous && driver.totalSeconds == previous) {
        // Ничего не изменилось в закрытых этажах, а время выросло.
      }
      if (driver.totalSeconds < elapsed) grewInsideFloor = true;
      floorBoundaries.add(driver.totalSeconds);
      previous = elapsed;
    }

    expect(grewInsideFloor, isTrue,
        reason: 'внутри этажа время обязано идти');
    expect(floorBoundaries.length, greaterThan(1));
  });

  test('в конце рана обе шкалы времени сходятся', () {
    final driver = _driver(9);
    driver.advance(1e9);

    expect(driver.finished, isTrue);
    expect(driver.elapsedSeconds, closeTo(driver.totalSeconds, 1e-9));
    expect(driver.result.totalSeconds, closeTo(driver.totalSeconds, 1e-9));
  });
}
