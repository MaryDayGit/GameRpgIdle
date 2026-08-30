import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/forecast.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Прогноз — обещание игроку о будущем. Обещание, расходящееся с тем, что
/// потом случится, хуже отсутствия прогноза: по нему принимают решение
/// отзывать наёмника или нет.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  test('прогноз совпадает с тем, что случится на самом деле', () {
    // Единственная проверка, ради которой прогноз существует. Считается он
    // формулой, а спуск идёт симуляцией — разойтись им ничто не мешает.
    for (final policy in ForkPolicy.values) {
      final driver = DescentDriver(
        profile: HeroProfile(powerMultiplier: 3.0),
        seed: 4242,
        forkPolicy: policy,
        floorCap: 30,
      );

      final predicted = {
        for (final floor in Forecast.ahead(
          seed: 4242,
          fromDepth: 1,
          floors: 30,
          policy: policy,
        ))
          floor.depth: floor.modifier?.id,
      };

      while (!driver.finished) {
        driver.tick();
      }

      for (final floor in driver.result.floors) {
        expect(predicted[floor.depth], floor.modifierId,
            reason: 'этаж ${floor.depth}, политика ${policy.ru}');
      }
    }
  });

  test('модификатор держится до следующей развилки, а не до конца этажа', () {
    // Развилка выбирает ПУТЬ (раунд 6). Прогноз, показывающий модификатор
    // только на этаже развилки, врал бы про два этажа из трёх.
    final ahead = Forecast.ahead(
      seed: 7,
      fromDepth: 1,
      floors: Tuning.forkEveryFloors * 2 + 1,
      policy: ForkPolicy.loot,
    );

    final forkFloors = ahead.where((f) => f.forkHere).toList();
    expect(forkFloors, hasLength(2), reason: 'развилка каждые N этажей');

    for (final floor in ahead) {
      if (floor.depth < forkFloors.first.depth) {
        expect(floor.modifier, isNull,
            reason: 'до первой развилки пути ещё нет');
      } else {
        expect(floor.modifier, isNotNull, reason: 'этаж ${floor.depth}');
      }
    }

    // Между развилками путь один и тот же.
    final between = ahead
        .where((f) =>
            f.depth >= forkFloors.first.depth &&
            f.depth < forkFloors.last.depth)
        .map((f) => f.modifier?.id)
        .toSet();
    expect(between, hasLength(1));
  });

  test('на развилке видно оба пути, а не только выбранный', () {
    // Иначе прогноз показывает решение наёмника, но не показывает, из чего
    // он выбирал, — а это и есть содержание приказа.
    final ahead = Forecast.ahead(
      seed: 99,
      fromDepth: 1,
      floors: Tuning.forkEveryFloors + 1,
      policy: ForkPolicy.safety,
    );

    final fork = ahead.firstWhere((f) => f.forkHere);
    expect(fork.options, hasLength(2));
    expect(fork.options.map((o) => o.id).toSet(), hasLength(2),
        reason: 'развилка из двух одинаковых — не выбор');
    expect(fork.options.map((o) => o.id), contains(fork.modifier!.id));
  });

  test('прогноз показывает путь, выбранный ИГРОКОМ, а не приказом', () {
    // Третий путь берётся только вручную, и после нажатия прогноз обязан
    // говорить про него. Иначе экран продолжает описывать спуск приказа —
    // тот самый, от которого игрок только что отказался.
    final forkDepth = Tuning.forkEveryFloors;
    final fork = ForkChooser.roll(21, forkDepth, ForkPolicy.loot);

    final auto = Forecast.ahead(
        seed: 21, fromDepth: 1, floors: forkDepth, policy: ForkPolicy.loot);
    final bold = Forecast.ahead(
      seed: 21,
      fromDepth: 1,
      floors: forkDepth,
      policy: ForkPolicy.loot,
      choices: const [Fork.boldIndex],
    );

    expect(auto.last.modifier!.id, fork.chosen.id);
    expect(bold.last.modifier!.id, fork.bold.id);
    expect(bold.last.modifier!.id, isNot(fork.chosen.id));
  });

  test('номер развилки считается от этажа, с которого начался спуск', () {
    // «Верёвка» Заставы опускает наёмника сразу на глубину. Счёт развилок от
    // первого этажа сдвинул бы решения игрока на все пропущенные развилки —
    // прогноз показывал бы чужой выбор.
    final start = Tuning.forkEveryFloors * 3;
    final fork = ForkChooser.roll(33, start, ForkPolicy.safety);

    final ahead = Forecast.ahead(
      seed: 33,
      fromDepth: start,
      floors: 1,
      policy: ForkPolicy.safety,
      choices: const [Fork.boldIndex],
      startDepth: start,
    );

    expect(ahead.single.modifier!.id, fork.bold.id,
        reason: 'первое решение игрока — первая развилка ЕГО спуска');
  });

  test('боссы телеграфируются заранее', () {
    final ahead =
        Forecast.ahead(seed: 1, fromDepth: 1, floors: 21, policy: ForkPolicy.loot);

    final bossFloors =
        ahead.where((f) => f.boss != null).map((f) => f.depth).toList();
    expect(bossFloors, isNotEmpty);
    expect(bossFloors, contains(10));
    expect(bossFloors, contains(20));

    // Тип урона — то, ради чего прогноз вообще смотрят перед боссом.
    final big = ahead.firstWhere((f) => f.depth == 20);
    expect(big.boss!.damageType, isNotNull);
  });

  test('прогноз ни на что не влияет', () {
    // Он обязан быть чистым расчётом: если бы он трогал ГСЧ или бестиарий,
    // сам факт открытия экрана менял бы ран.
    final before = DescentSimulator(
      profile: HeroProfile(),
      seed: 555,
    ).run(floorCap: 40);

    Forecast.ahead(
        seed: 555, fromDepth: 1, floors: 40, policy: ForkPolicy.random);

    final after = DescentSimulator(
      profile: HeroProfile(),
      seed: 555,
    ).run(floorCap: 40);

    expect(after.maxDepth, before.maxDepth);
    expect(after.totalSeconds, before.totalSeconds);
    expect(after.gold, before.gold);
  });

  group('отзыв контракта', () {
    PlayerProfile player() {
      final p = PlayerProfile.newGame(seed: 3);
      return p;
    }

    test('отзыв закрывает контракт живым наёмником', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 31);
      final full = contract.result!;

      // Половина пути вниз.
      final half = contract.startedAtUtc
          .add(Duration(milliseconds: (full.totalSeconds * 500).round()));

      expect(p.recall(contract, half), isTrue);
      expect(contract.awaitingCollection, isTrue);
      expect(contract.result!.ending, RunEnding.recalled);
      expect(contract.result!.maxDepth, lessThan(full.maxDepth),
          reason: 'отозвали на полпути — глубина меньше');
      expect(contract.result!.killedBy, isNull, reason: 'наёмник жив');
    });

    test('отозванный ран совпадает с тем, что показывал экран', () {
      // Игрок смотрел бой и нажал «Отозвать». Если пересчёт даст другую
      // глубину, чем была на экране, это выглядит как обман.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 77);
      final at = contract.startedAtUtc.add(const Duration(minutes: 4));

      final watched = DescentDriver(
        profile: contract.replayProfile(),
        seed: contract.seed,
        brandRank: contract.brandRank,
        backpackCapacityOverride: contract.mercenary.backpackSlots,
        salvageRate: p.outpost.salvageRate,
        forkPolicy: contract.forkPolicy,
      );
      while (!watched.finished && watched.elapsedSeconds < 240.0) {
        watched.tick();
      }

      p.recall(contract, at);
      expect(contract.result!.maxDepth, watched.result.maxDepth);
      expect(contract.result!.gold, watched.result.gold);
      expect(contract.result!.haul.itemCount, watched.result.haul.itemCount);
    });

    test('добыча забирается обычным путём и Эхо не урезано', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 12);
      p.recall(contract,
          contract.startedAtUtc.add(const Duration(minutes: 5)));

      final depth = contract.result!.maxDepth;
      final haul = p.collect(contract);

      expect(haul.collected, isTrue);
      expect(p.maxDepthEver, depth);
      // Штрафа за отзыв нет: Эхо считается по достигнутой глубине, как всегда.
      // Награды закрытых заданий — сверх того, и они не имеют отношения к
      // отзыву: их дало бы и обычное возвращение.
      final questEcho = p.lastClosedQuests
          .fold<int>(0, (sum, q) => sum + q.rewardEcho);
      expect(p.echo, contract.result!.echo + questEcho);
    });

    test('стоящего на развилке отозвать МОЖНО', () {
      // Иначе игрок, которому спуск разонравился, обязан сперва выбрать
      // путь — сделать ход, которого он делать не хотел, — и только потом
      // разворачивать наёмника.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 41);
      p.refreshContracts(contract.segmentEndsAtUtc!);
      expect(contract.atFork, isTrue);

      final standing = contract.result!.maxDepth;
      expect(p.recall(contract, contract.segmentEndsAtUtc!), isTrue);

      expect(contract.result!.ending, RunEnding.recalled);
      expect(contract.result!.maxDepth, standing,
          reason: 'спуск кончается там, где наёмник стоит');
      expect(contract.awaitingCollection, isTrue);
    });

    test('погибшего отозвать нельзя — его контракт закрыт смертью', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 5);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      expect(contract.awaitingCollection, isTrue);
      expect(p.recall(contract, DateTime.now().toUtc()), isFalse);
      expect(contract.result!.ending, RunEnding.death);
    });

    test('отзыв сразу после отправки возвращает наёмника ни с чем', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 9);

      expect(p.recall(contract, contract.startedAtUtc), isTrue);
      expect(contract.result!.ending, RunEnding.recalled);
      expect(contract.result!.haul.itemCount, 0);
      expect(p.roster.reserve, isEmpty, reason: 'наёмник ещё в спуске');

      p.collect(contract);
      expect(p.roster.fallen, contains(contract.mercenary),
          reason: 'контракт — это ран: наёмник уходит после него в любом '
              'случае');
    });
  });
}
