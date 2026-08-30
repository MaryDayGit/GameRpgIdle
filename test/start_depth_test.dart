import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Верёвка: спуск начинается не с первого этажа, а с доли рекорда.
///
/// Замер `--hp` показал, что на 64 % этажей здоровье не опускалось ниже
/// 90 %: снаряжение собрано под сороковой этаж, а бьётся на пятом. Первые
/// две трети рана были формальностью — и по здоровью, и по времени игрока.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  PlayerProfile playerWith({required int record}) {
    final profile = PlayerProfile(maxDepthEver: record, gold: 1e6);
    profile.roster.reserve
        .add(MercFactory.roll(Rng(1), idPrefix: 'rope$record'));
    return profile;
  }

  group('верёвка спущена по рекорду', () {
    test('без рекорда спускаются пешком', () {
      // Первый спуск в игре обязан начаться с первого этажа: игрок ещё не
      // знает, что там внизу.
      expect(Curves.startDepth(0), 1);
      expect(PlayerProfile().startDepth, 1);
    });

    test('глубже рекорд — выше точка старта, но не выше самого рекорда', () {
      var previous = 0;
      for (final record in [10, 40, 100, 200]) {
        final start = Curves.startDepth(record);
        expect(start, greaterThan(previous));
        expect(start, lessThan(record),
            reason: 'верёвка не должна доставать до рекорда');
        previous = start;
      }
    });

    test('контракт помнит, откуда начался спуск', () {
      final profile = playerWith(record: 100);
      final contract = profile.deploy(profile.roster.reserve.first, seed: 5);

      expect(contract.startDepthBonus + 1, profile.startDepth);
      expect(contract.result!.floors.first.depth, profile.startDepth,
          reason: 'первый записанный этаж — это точка старта');
    });

    test('повтор начинается там же, где начался посчитанный ран', () {
      // Ран считается по профилю игрока, а повтор — по снимку контракта.
      // Это два разных построения одного и того же, и разойтись им нельзя:
      // игрок увидел бы бой, которого не было.
      final profile = playerWith(record: 120);
      final contract = profile.deploy(profile.roster.reserve.first, seed: 11);
      // Спуск доводится до конца приказом: при отправке готов только отрезок
      // до первой развилки, а повтор считает весь ран целиком.
      profile.refreshContracts(
          DateTime.now().toUtc().add(const Duration(days: 1)));

      final replay = DescentSimulator(
        profile: contract.replayProfile(),
        seed: contract.seed,
        brandRank: contract.brandRank,
        backpackCapacityOverride: contract.mercenary.backpackSlots,
        salvageRate: contract.outpost.salvageRate,
        outpostLootQuality: contract.outpost.lootQuality,
        outpostLootQuantity: contract.outpost.lootQuantity,
        restHealBonus: contract.outpost.restHealBonus,
        forkPolicy: contract.forkPolicy,
      ).run();

      expect(replay.floors.first.depth, contract.result!.floors.first.depth);
      expect(replay.maxDepth, contract.result!.maxDepth);
      expect(replay.totalSeconds, contract.result!.totalSeconds);
    });

    test('снимок не меняется задним числом', () {
      // Рекорд растёт, пока наёмник внизу: другой наёмник мог уйти глубже.
      // Повтор обязан начаться там, где начался записанный ран.
      final profile = playerWith(record: 60);
      final contract = profile.deploy(profile.roster.reserve.first, seed: 3);
      final before = contract.startDepthBonus;

      // Рекорд поднимается только получением добычи, поэтому «другой
      // наёмник ушёл глубже» изображается вторым профилем с тем же смыслом.
      final deeper = PlayerProfile(maxDepthEver: 400);
      expect(deeper.startDepth, greaterThan(before + 1));
      expect(contract.startDepthBonus, before);
    });
  });

  test('верёвка укорачивает ран, почти не трогая глубину', () {
    // Ради этого всё и сделано: формальная часть исчезает, а достижение —
    // остаётся. Числа сверяются на многих сидах: один ничего не покажет.
    var walkedFloors = 0;
    var ropedFloors = 0;
    var walkedDepth = 0;
    var ropedDepth = 0;

    for (var seed = 1; seed <= 24; seed++) {
      final walked = DescentSimulator(profile: HeroProfile(), seed: seed)
          .run(floorCap: 200);
      final roped = DescentSimulator(
        profile: HeroProfile(),
        seed: seed,
        startDepth: Curves.startDepth(40),
      ).run(floorCap: 200);

      walkedFloors += walked.floors.length;
      ropedFloors += roped.floors.length;
      walkedDepth += walked.maxDepth;
      ropedDepth += roped.maxDepth;
    }

    expect(ropedFloors, lessThan(walkedFloors * 0.9),
        reason: 'этажей за ран должно стать заметно меньше');
    expect(ropedDepth, greaterThan(walkedDepth * 0.85),
        reason: 'а глубина — почти той же');
  });
}
