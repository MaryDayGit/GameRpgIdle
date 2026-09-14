import 'dart:math' as math;

import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/combat_feed.dart';

/// Сколько длится падение. Короче — смерть незаметна, длиннее — труп ещё
/// заваливается, когда волна уже кончилась.
const deathSeconds = 0.45;

/// Сколько длится удар от замаха до возврата в стойку.
///
/// Треть секунды — не вкус, а требование читаемости: удары идут по нескольку
/// раз в секунду, и анимация длиннее промежутка между ними не успевает
/// закончиться. Начатая заново, она обрубает предыдущую, и бой превращается в
/// дрожь.
const swingSeconds = 0.32;

/// Анимационное состояние одной фигуры.
///
/// Всё затухает само: анимация — это след события, и держать её должно само
/// событие, а не флаг «сейчас бьём». Иначе замах, начатый в одном кадре,
/// придётся кому-то гасить в другом, и однажды его не погасит никто.
class FigureAnim {
  /// Время, прошедшее с начала удара. Ноль — фигура в стойке.
  double _swing = 0.0;

  /// Вспышка попадания и стихия, которой ударили.
  double flash = 0.0;
  DamageType flashType = DamageType.physical;

  /// Отдача от удара — фигуру отбрасывает назад.
  double recoil = 0.0;

  /// Сжатие от удара: фигуру приминает и она распрямляется обратно.
  ///
  /// Отдельно от отдачи, потому что это разные вещи: отдача говорит «толкнули»,
  /// сжатие — «приняли удар». Вместе они и читаются как попадание, а не как
  /// сдвиг картинки.
  double squash = 0.0;

  double _dying = 0.0;
  bool _fallen = false;

  /// Прогресс падения от 0 (стоит) до 1 (лежит).
  double get falling => _fallen
      ? 1.0
      : (_dying <= 0.0 ? 0.0 : 1.0 - (_dying / deathSeconds).clamp(0.0, 1.0));

  bool get fallen => _fallen;

  /// Идёт ли удар прямо сейчас.
  bool get swinging => _swing > 0.0;

  /// Насколько фигура подалась к противнику, в долях своего роста.
  ///
  /// Отрицательное — замах НАЗАД. В этом вся разница между ударом и рывком:
  /// глаз читает движение по подготовке к нему. Фигура, которая просто
  /// прыгает вперёд, выглядит сдвинутой картинкой; фигура, которая сперва
  /// отвела оружие, выглядит ударившей — и это стоит двадцати миллисекунд.
  ///
  /// Три части, как в любой ударной анимации: замах (медленно назад), выпад
  /// (быстро вперёд), возврат (мягко в стойку).
  double get lunge {
    if (_swing <= 0.0) return 0.0;
    final t = (1.0 - _swing / swingSeconds).clamp(0.0, 1.0);

    const windUp = 0.34;
    const strike = 0.52;
    const back = -0.42;

    if (t < windUp) {
      // Замах: чем ближе к выпаду, тем медленнее — пружина сжимается.
      final k = t / windUp;
      return back * (1.0 - (1.0 - k) * (1.0 - k));
    }
    if (t < strike) {
      // Выпад: самый быстрый кусок. Разгон, а не равномерность.
      final k = (t - windUp) / (strike - windUp);
      return back + (1.0 - back) * k * k;
    }
    // Возврат: мягко и дольше всех остальных частей вместе.
    final k = (t - strike) / (1.0 - strike);
    return 1.0 * (1.0 - k) * (1.0 - k);
  }

  /// Фигура погибла на глазах — начинает падать.
  void die() {
    if (_fallen || _dying > 0.0) return;
    _dying = deathSeconds;
  }

  /// Фигура погибла за перемотку: падать ей поздно, она уже лежит.
  void fallenAlready() {
    if (_dying <= 0.0) _fallen = true;
  }

  void strike() => _swing = swingSeconds;

  void hurt(DamageType type, {required bool crit}) {
    flash = 1.0;
    flashType = type;
    recoil = crit ? 1.0 : 0.6;
    squash = crit ? 1.0 : 0.55;
  }

  void tick(double dt) {
    if (_swing > 0) _swing = math.max(0.0, _swing - dt);
    if (flash > 0) flash = math.max(0.0, flash - dt * 4.0);
    if (recoil > 0) recoil = math.max(0.0, recoil - dt * 6.0);
    if (squash > 0) squash = math.max(0.0, squash - dt * 5.0);
    if (_dying > 0) {
      _dying -= dt;
      if (_dying <= 0.0) {
        _dying = 0.0;
        _fallen = true;
      }
    }
  }
}

/// Что показывает бой сверх полосок: замах, попадание, падение.
///
/// Ведётся по СОБЫТИЯМ из [CombatFeed], а не по разнице здоровья между
/// кадрами. Разница показывает, что здоровье упало, но не показывает удара:
/// два попадания в один кадр читались бы как одно, а лечение цели гасило бы
/// их оба. Отделено от сцены по той же причине, что и раскладка волны, —
/// рисование не возвращает чисел, а это состояние проверяемо.
class BattleAnimations {
  final List<FigureAnim> _enemies = [];

  /// Герой — такая же фигура, только одна.
  final FigureAnim hero = FigureAnim();

  /// Расходящееся кольцо от применённой способности, от 1 до 0.
  double cast = 0.0;

  /// Вход босса: волна началась с тем, кто крупнее всех. Отдельная встряска,
  /// потому что это единственное событие боя, которое игрок обязан заметить
  /// ДО того, как по нему ударят.
  double entrance = 0.0;

  int get length => _enemies.length;

  FigureAnim enemy(int index) {
    if (index < 0) return hero;
    while (_enemies.length <= index) {
      _enemies.add(FigureAnim());
    }
    return _enemies[index];
  }

  void apply(List<CombatBeat> beats, {bool bossWave = false}) {
    for (final beat in beats) {
      switch (beat.kind) {
        case BeatKind.waveStarted:
          // Индексы относятся к текущей волне: не сбросить состояние значит
          // оставить на новой пачке чужие раны и чужие смерти.
          _enemies.clear();
          cast = 0.0;
          if (bossWave) entrance = 1.0;
        case BeatKind.heroSwing:
          hero.strike();
        case BeatKind.heroCast:
          cast = 1.0;
        case BeatKind.enemyHit:
          enemy(beat.index).hurt(beat.type, crit: beat.crit);
        case BeatKind.enemyDied:
          enemy(beat.index).die();
        case BeatKind.heroHurt:
          // Моб, ударивший героя, тоже замахивается: без этого удары по
          // наёмнику прилетают из ниоткуда, и волна выглядит неподвижной.
          if (beat.index >= 0) enemy(beat.index).strike();
          hero.hurt(beat.type, crit: false);
        case BeatKind.heroDied:
          hero.die();
      }
    }
  }

  /// Мобы, погибшие за перемотку, событий уже не принесут: их смерть видна
  /// только по нулевому здоровью, и падать им поздно.
  void syncDeaths(List<double> hpFractions) {
    for (var i = 0; i < hpFractions.length; i++) {
      if (hpFractions[i] <= 0.0) enemy(i).fallenAlready();
    }
  }

  void tick(double dt) {
    for (final anim in _enemies) {
      anim.tick(dt);
    }
    hero.tick(dt);
    if (cast > 0) cast = math.max(0.0, cast - dt * 1.6);
    if (entrance > 0) entrance = math.max(0.0, entrance - dt * 1.1);
  }
}
