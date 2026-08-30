import 'dart:math' as math;

import 'package:rift/core/sim/combat_feed.dart';

/// Сколько длится падение. Короче — смерть незаметна, длиннее — труп ещё
/// заваливается, когда волна уже кончилась.
const deathSeconds = 0.45;

/// Анимационное состояние одной фигуры.
///
/// Всё затухает само: анимация — это след события, и держать её должно само
/// событие, а не флаг «сейчас бьём». Иначе замах, начатый в одном кадре,
/// придётся кому-то гасить в другом, и однажды его не погасит никто.
class FigureAnim {
  /// Замах: 1 — только что ударил.
  double swing = 0.0;

  /// Вспышка попадания.
  double flash = 0.0;

  /// Отдача от удара — фигуру отбрасывает назад.
  double recoil = 0.0;

  double _dying = 0.0;
  bool _fallen = false;

  /// Прогресс падения от 0 (стоит) до 1 (лежит).
  double get falling => _fallen
      ? 1.0
      : (_dying <= 0.0 ? 0.0 : 1.0 - (_dying / deathSeconds).clamp(0.0, 1.0));

  bool get fallen => _fallen;

  /// Фигура погибла на глазах — начинает падать.
  void die() {
    if (_fallen || _dying > 0.0) return;
    _dying = deathSeconds;
  }

  /// Фигура погибла за перемотку: падать ей поздно, она уже лежит.
  void fallenAlready() {
    if (_dying <= 0.0) _fallen = true;
  }

  void tick(double dt) {
    if (swing > 0) swing = math.max(0.0, swing - dt * 5.0);
    if (flash > 0) flash = math.max(0.0, flash - dt * 4.0);
    if (recoil > 0) recoil = math.max(0.0, recoil - dt * 6.0);
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

  int get length => _enemies.length;

  FigureAnim enemy(int index) {
    if (index < 0) return hero;
    while (_enemies.length <= index) {
      _enemies.add(FigureAnim());
    }
    return _enemies[index];
  }

  void apply(List<CombatBeat> beats) {
    for (final beat in beats) {
      switch (beat.kind) {
        case BeatKind.waveStarted:
          // Индексы относятся к текущей волне: не сбросить состояние значит
          // оставить на новой пачке чужие раны и чужие смерти.
          _enemies.clear();
          cast = 0.0;
        case BeatKind.heroSwing:
          hero.swing = 1.0;
        case BeatKind.heroCast:
          cast = 1.0;
        case BeatKind.enemyHit:
          enemy(beat.index)
            ..flash = 1.0
            ..recoil = beat.crit ? 1.0 : 0.6;
        case BeatKind.enemyDied:
          enemy(beat.index).die();
        case BeatKind.heroHurt:
          hero
            ..flash = 1.0
            ..recoil = 0.6;
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
  }
}
