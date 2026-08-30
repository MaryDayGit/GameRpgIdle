/// Назначение потока случайных чисел.
///
/// Разные назначения на одном (ран, этаж, волна) получают независимые потоки,
/// поэтому дроп нельзя переролльнуть, закрыв приложение: сид детерминирован
/// координатами события, а не порядком вызовов.
enum RngPurpose {
  combat,
  lootRoll,
  lootRarity,
  lootAffix,
  affixPercentile,
  enemyPack,
  floorModifier,
  fork,
  trigger,
  tavern,
  offline,
}

/// Детерминированный ГСЧ (SplitMix64).
///
/// Собственная реализация вместо `dart:math` Random: реализация Random не
/// гарантирована между версиями SDK, а нам нужна воспроизводимость сейва и
/// сверка офлайн-модели с полной симуляцией на одном сиде.
///
/// Замечание по платформам: рассчитан на 64-битный int (Dart VM / AOT, то есть
/// Android). Для web (int = double) потребуется 32-битный вариант.
class Rng {
  Rng(int seed) : _state = seed;

  /// Поток, детерминированный координатами события.
  factory Rng.stream(
    int runSeed,
    int depth,
    int wave,
    RngPurpose purpose,
  ) {
    var h = runSeed;
    h = _mix(h ^ 0x9E3779B97F4A7C15 * (depth + 1));
    h = _mix(h ^ 0xC2B2AE3D27D4EB4F * (wave + 1));
    h = _mix(h ^ 0x165667B19E3779F9 * (purpose.index + 1));
    return Rng(h);
  }

  int _state;

  static const int _gamma = 0x9E3779B97F4A7C15;

  static int _mix(int z) {
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Следующее сырое 64-битное значение.
  int nextRaw() {
    _state += _gamma;
    return _mix(_state);
  }

  /// Равномерно в [0, 1).
  double nextDouble() => (nextRaw() >>> 11) * (1.0 / 9007199254740992.0);

  /// Равномерно в [0, max).
  int nextInt(int max) {
    assert(max > 0);
    return (nextRaw() >>> 1) % max;
  }

  /// Равномерно в [min, max] включительно.
  int nextIntRange(int min, int max) =>
      min + (max > min ? nextInt(max - min + 1) : 0);

  /// Равномерно в [min, max).
  double nextRange(double min, double max) =>
      min + nextDouble() * (max - min);

  /// Испытание с вероятностью [p].
  bool chance(double p) {
    if (p <= 0.0) return false;
    if (p >= 1.0) return true;
    return nextDouble() < p;
  }

  /// Ответвление независимого потока — для вложенных подсистем,
  /// чтобы они не сдвигали основную последовательность.
  /// Индекс по весам. Веса не обязаны быть нормированными.
  ///
  /// Один вызов — один расход генератора, независимо от числа кандидатов:
  /// иначе добавление моба в бестиарий сдвигало бы все последующие роллы и
  /// один и тот же сид переставал бы означать один и тот же ран.
  int weightedIndex(List<double> weights) {
    assert(weights.isNotEmpty);
    var total = 0.0;
    for (final w in weights) {
      if (w > 0.0) total += w;
    }
    if (total <= 0.0) return 0;

    var roll = nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i];
      if (w <= 0.0) continue;
      roll -= w;
      if (roll < 0.0) return i;
    }
    return weights.length - 1;
  }

  Rng fork(int salt) => Rng(_mix(_state ^ (salt * _gamma)));
}
