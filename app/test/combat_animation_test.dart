import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift_app/game/combat_animation.dart';

/// Анимация — след события, а не состояние «сейчас бьём». Проверяется, что
/// след появляется, гаснет сам и не остаётся на чужой волне.
void main() {
  test('попадание вспыхивает и гаснет само', () {
    final anims = BattleAnimations()
      ..apply(const [CombatBeat(BeatKind.enemyHit, index: 1, amount: 12.0)]);

    expect(anims.enemy(1).flash, 1.0);
    expect(anims.enemy(0).flash, 0.0, reason: 'соседа не задело');

    anims.tick(0.5);
    expect(anims.enemy(1).flash, 0.0, reason: 'вспышка обязана погаснуть сама');
  });

  test('крит отбрасывает сильнее обычного удара', () {
    final anims = BattleAnimations()
      ..apply(const [
        CombatBeat(BeatKind.enemyHit, index: 0),
        CombatBeat(BeatKind.enemyHit, index: 1, crit: true),
      ]);

    expect(anims.enemy(1).recoil, greaterThan(anims.enemy(0).recoil));
  });

  test('два попадания в один кадр — не одно', () {
    // Ровно то, чего не умела разница здоровья между кадрами.
    final anims = BattleAnimations()
      ..apply(const [
        CombatBeat(BeatKind.enemyHit, index: 0),
        CombatBeat(BeatKind.enemyHit, index: 2),
      ]);

    expect(anims.enemy(0).flash, 1.0);
    expect(anims.enemy(2).flash, 1.0);
    expect(anims.enemy(1).flash, 0.0);
  });

  group('падение', () {
    test('гибель на глазах — фигура заваливается за отведённое время', () {
      final anims = BattleAnimations()
        ..apply(const [CombatBeat(BeatKind.enemyDied, index: 0)]);

      expect(anims.enemy(0).falling, 0.0, reason: 'падение только началось');

      anims.tick(deathSeconds / 2);
      final half = anims.enemy(0).falling;
      expect(half, greaterThan(0.2));
      expect(half, lessThan(0.8));

      anims.tick(deathSeconds);
      expect(anims.enemy(0).falling, 1.0);
      expect(anims.enemy(0).fallen, isTrue);
    });

    test('повторная гибель не начинает падение заново', () {
      // Дот добивает уже мёртвого не чаще, чем событие теряется по дороге,
      // но фигура, вскакивающая обратно, — это то, что видно сразу.
      final anims = BattleAnimations()
        ..apply(const [CombatBeat(BeatKind.enemyDied, index: 0)])
        ..tick(deathSeconds * 0.9);

      final before = anims.enemy(0).falling;
      anims.apply(const [CombatBeat(BeatKind.enemyDied, index: 0)]);
      expect(anims.enemy(0).falling, before);
    });

    test('погибший за перемотку уже лежит', () {
      // Перемотка съедает события: наблюдатель догоняет спуск тысячами тиков,
      // и падать тем, кто умер десять минут назад, поздно.
      final anims = BattleAnimations()..syncDeaths([1.0, 0.0, 0.0]);

      expect(anims.enemy(0).falling, 0.0);
      expect(anims.enemy(1).falling, 1.0);
      expect(anims.enemy(2).fallen, isTrue);
    });

    test('падение живого не начинается от синхронизации', () {
      final anims = BattleAnimations()
        ..apply(const [CombatBeat(BeatKind.enemyDied, index: 0)])
        ..syncDeaths([0.0]);

      // Только что убитый обязан упасть анимацией, а не мгновенно лечь.
      expect(anims.enemy(0).falling, lessThan(1.0));
    });
  });

  test('новая волна не наследует чужие раны', () {
    final anims = BattleAnimations()
      ..apply(const [
        CombatBeat(BeatKind.enemyHit, index: 0),
        CombatBeat(BeatKind.enemyDied, index: 1),
        CombatBeat(BeatKind.heroCast, id: 'cleave'),
      ]);

    expect(anims.cast, 1.0);
    anims.apply(const [CombatBeat(BeatKind.waveStarted, amount: 3.0)]);

    expect(anims.length, 0, reason: 'состояние прошлой пачки сброшено');
    expect(anims.cast, 0.0);
    expect(anims.enemy(1).fallen, isFalse);
  });

  test('герой живёт своей анимацией', () {
    final anims = BattleAnimations()
      ..apply(const [
        CombatBeat(BeatKind.heroSwing, index: 0),
        CombatBeat(BeatKind.heroHurt, index: 2, amount: 40.0),
      ]);

    expect(anims.hero.swing, 1.0);
    expect(anims.hero.flash, 1.0, reason: 'видно, что бьют ТЕБЯ');
    expect(anims.enemy(2).flash, 0.0, reason: 'бил моб, а не по мобу');

    anims
      ..apply(const [CombatBeat(BeatKind.heroDied)])
      ..tick(deathSeconds * 2);
    expect(anims.hero.fallen, isTrue);
  });

  test('запись про фигуру вне волны не роняет сцену', () {
    // Индексы приходят из симуляции, а волна на экране — из снимка. Разойтись
    // они могут на одном кадре, и падать из-за этого экран не должен.
    final anims = BattleAnimations()
      ..apply(const [CombatBeat(BeatKind.enemyHit, index: 40)]);

    expect(anims.enemy(40).flash, 1.0);
    expect(anims.length, 41);
  });
}
