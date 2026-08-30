import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Каждая постройка обещает игроку эффект — и берёт за него золото.
///
/// Тест на то, что ЧИСЛА растут с уровнем, уже был, и он был зелёным всё
/// время, пока Оружейная не делала ничего: её `lootQuality` и `lootQuantity`
/// не читал никто. Число, которое некому прочитать, — это не эффект.
///
/// Поэтому здесь сравниваются РАНЫ: та же посадка, тот же сид, разная
/// Застава. Если строки сходятся, постройка берёт золото за воздух.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  RunResult run({
    Outpost? outpost,
    int seed = 4242,
    int floorCap = 30,
  }) {
    final o = outpost ?? Outpost();
    return DescentSimulator(
      profile: HeroProfile(powerMultiplier: 2.0),
      seed: seed,
      salvageRate: o.salvageRate,
      outpostLootQuality: o.lootQuality,
      outpostLootQuantity: o.lootQuantity,
      restHealBonus: o.restHealBonus,
    ).run(floorCap: floorCap);
  }

  Outpost maxed(Building building) =>
      Outpost({building: Building.maxLevel});

  group('эффект постройки виден в спуске', () {
    test('Оружейная: добычи больше', () {
      // Обе половины постройки: количество проверяется числом находок,
      // качество — тем, что при том же сиде добыча другая.
      var plain = 0;
      var armed = 0;
      for (var seed = 1; seed <= 12; seed++) {
        plain += run(seed: seed).itemsFound;
        armed += run(seed: seed, outpost: maxed(Building.armory)).itemsFound;
      }

      expect(armed, greaterThan(plain),
          reason: 'Оружейная обещает количество лута');
    });

    test('Костёр: наёмник живее между этажами', () {
      // Отдых лечит долю максимума, поэтому разница видна только там, где
      // наёмник кончает этаж потрёпанным, — то есть у стены, а не на пятом
      // этаже с двойной силой. Мерить приходится глубиной по многим сидам:
      // один сид ничего не доказывает.
      var plain = 0;
      var rested = 0;
      for (var seed = 1; seed <= 12; seed++) {
        plain += DescentSimulator(profile: HeroProfile(), seed: seed)
            .run(floorCap: 100)
            .maxDepth;
        rested += DescentSimulator(
          profile: HeroProfile(),
          seed: seed,
          restHealBonus: maxed(Building.campfire).restHealBonus,
        ).run(floorCap: 100).maxDepth;
      }

      expect(rested, greaterThan(plain),
          reason: 'Костёр обещает восстановление между этажами');
    });

    test('Алтарь: за переплавленное дают больше золота', () {
      // Рюкзак больше ничего не распыляет сам, поэтому курс Алтаря
      // проверяется на самой переплавке — там, где он теперь и работает.
      final plain = run().haul;
      final altar = run(outpost: maxed(Building.altar)).haul;

      final sample = plain.items.first;
      plain.salvage(sample);
      altar.salvage(sample);

      expect(altar.salvagedGold, greaterThan(plain.salvagedGold));
    });

    test('Картограф: прогноз растёт с каждым уровнем', () {
      // Раньше эффект был только на первом уровне, а платили за восемь.
      var previous = Outpost().forecastFloors;
      for (var level = 1; level <= Building.maxLevel; level++) {
        final current = Outpost({Building.cartographer: level}).forecastFloors;
        expect(current, greaterThan(previous),
            reason: 'уровень $level ничего не добавил');
        previous = current;
      }
    });

    test('Хранилище: сундук вмещает больше', () {
      final profile = PlayerProfile();
      final wide = PlayerProfile(
          outpost: Outpost({Building.vault: Building.maxLevel}));

      expect(wide.outpost.stashSlots, greaterThan(profile.outpost.stashSlots));
    });

    test('Верстак: осколков помещается больше', () {
      final plain = Outpost();
      final bench = maxed(Building.shardBench);

      expect(bench.shardCapacity, greaterThan(plain.shardCapacity));
      expect(bench.shardSalvageOnOverwrite,
          greaterThan(plain.shardSalvageOnOverwrite));
    });

    test('Таверна: кандидатов больше', () {
      final profile = PlayerProfile(
          outpost: Outpost({Building.tavern: Building.maxLevel}));
      profile.refreshTavern(Rng(1));

      final plain = PlayerProfile()..refreshTavern(Rng(1));
      expect(profile.roster.candidates.length,
          greaterThan(plain.roster.candidates.length));
    });
  });

  group('вклад Заставы — часть снимка контракта', () {
    test('улучшение Заставы не меняет уже идущий спуск', () {
      // Постройки улучшаются, пока наёмник внизу. Повтор по СЕГОДНЯШНЕЙ
      // Заставе показал бы не тот бой, результат которого уже записан.
      // Рекорд нужен не для красоты: уровень постройки теперь открывает
      // глубина, и без него Алтарь не улучшить ни за какие деньги.
      final profile = _veteranProfile(seed: 7);
      final contract = profile.deploy(profile.roster.reserve.first, seed: 21);

      final before = contract.outpost.salvageRate;
      for (var i = 0; i < 5; i++) {
        profile.upgradeBuilding(Building.altar);
      }

      expect(profile.outpost.salvageRate, greaterThan(before));
      expect(contract.outpost.salvageRate, before,
          reason: 'снимок контракта не меняется задним числом');
    });

    test('повтор контракта считается по его снимку', () {
      final profile = _veteranProfile(seed: 8);
      final contract = profile.deploy(profile.roster.reserve.first, seed: 33);
      // Повтор сверяется с ЗАКОНЧЕННЫМ спуском: при отправке готов только
      // отрезок до первой развилки.
      profile.refreshContracts(
          DateTime.now().toUtc().add(const Duration(days: 1)));
      final original = contract.result!;

      for (var i = 0; i < 5; i++) {
        profile.upgradeBuilding(Building.armory);
      }

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

      expect(replay.maxDepth, original.maxDepth);
      expect(replay.itemsFound, original.itemsFound);
      expect(replay.gold, original.gold);
    });
  });

  group('постройка объясняет себя числом', () {
    test('у каждой постройки эффект на каждом уровне', () {
      // Экран улучшения показывает «сейчас → станет». Пустая или одинаковая
      // строка означала бы, что уровень ничего не меняет.
      for (final b in Building.values) {
        final first = Outpost.effectAt(b, 0);
        final last = Outpost.effectAt(b, Building.maxLevel);

        expect(first, isNotEmpty, reason: b.ru);
        expect(last, isNot(first),
            reason: '${b.ru}: восемь уровней ничего не меняют');
      }
    });

    test('числа в описании — те же, что в игре', () {
      // Второй расчёт «уровень → число» разошёлся бы с первым, и игрок увидел
      // бы одну цифру в описании и другую в бою.
      final outpost = Outpost({Building.vault: 4});
      expect(Outpost.effectAt(Building.vault, 4),
          contains('${outpost.stashSlots}'));
    });
  });

  group('экономика: уровень открывает глубина', () {
    test('без рекорда следующий уровень не купить ни за какие деньги', () {
      // Раньше Застава выкупалась вперёд прогресса: золото копится быстрее,
      // чем растёт глубина, и экономика закрывалась раньше, чем игрок видел
      // бездну.
      final profile = PlayerProfile(maxDepthEver: 0)..gold = 1e9;

      expect(profile.canUpgradeBuilding(Building.armory), isFalse);
      expect(profile.upgradeBuilding(Building.armory), isFalse);
      expect(profile.outpost.levelOf(Building.armory), 0);
    });

    test('рекорд открывает ровно один уровень за свой порог', () {
      final profile = PlayerProfile(maxDepthEver: Outpost.depthGate(1))
        ..gold = 1e9;

      expect(profile.upgradeBuilding(Building.armory), isTrue);
      expect(profile.canUpgradeBuilding(Building.armory), isFalse,
          reason: 'второй уровень ждёт своей глубины');
      expect(profile.outpost.nextGate(Building.armory), Outpost.depthGate(2));
    });

    test('цена уровня растёт вместе с его глубиной', () {
      final low = Outpost();
      final high = Outpost({Building.armory: 5});

      expect(high.upgradeCost(Building.armory),
          greaterThan(low.upgradeCost(Building.armory)));
    });
  });
}

/// Профиль игрока, который уже ходил глубоко и может улучшать Заставу.
PlayerProfile _veteranProfile({required int seed}) {
  final profile = PlayerProfile(maxDepthEver: 200, gold: 1000000);
  final rng = Rng.stream(seed, 0, 0, RngPurpose.tavern);
  profile.roster.reserve
      .add(MercFactory.roll(rng, tavernLevel: 0, idPrefix: 'outpost$seed'));
  return profile;
}
