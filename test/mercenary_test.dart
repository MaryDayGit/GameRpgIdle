import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/haul.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Предмет-болванка: рюкзаку важен только уровень.
Item _item(int ilvl) => Item(
      kind: GearKind.ring,
      ilvl: ilvl,
      rarity: Rarity.common,
      affixes: const [],
    );

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('ранги', () {
    test('сила и рюкзак растут вместе с рангом', () {
      for (var i = 1; i < MercRank.values.length; i++) {
        final prev = MercRank.values[i - 1];
        final cur = MercRank.values[i];
        expect(cur.statMultiplier, greaterThan(prev.statMultiplier));
        expect(cur.backpackSlots, greaterThan(prev.backpackSlots));
      }
    });

    test('цена найма растёт быстрее силы', () {
      // Иначе высокий ранг был бы строго выгоднее, и выбора в Таверне нет.
      final cheap = Roster.hireCost(MercRank.ragged);
      final dear = Roster.hireCost(MercRank.legend);
      final costRatio = dear / cheap;
      final powerRatio =
          MercRank.legend.statMultiplier / MercRank.ragged.statMultiplier;
      expect(costRatio, greaterThan(powerRatio));
    });

    test('задаток растёт вместе с доходом, но не раньше времени', () {
      // Сток, который не растёт, перестаёт быть стоком: доход за ран
      // экспоненциален по глубине, и на шестидесятом ране золоту не было
      // применения. Ниже якоря цена не меняется — ранние раны измерены.
      final anchor = Curves.hireScaleFromDepth;

      expect(Roster.hireCost(MercRank.legend, maxDepthEver: anchor ~/ 2),
          Roster.hireCost(MercRank.legend));
      expect(Roster.hireCost(MercRank.legend, maxDepthEver: anchor),
          Roster.hireCost(MercRank.legend));

      final deep = Roster.hireCost(MercRank.legend, maxDepthEver: anchor + 60);
      expect(deep, greaterThan(Roster.hireCost(MercRank.legend) * 10),
          reason: 'иначе задаток отстаёт от дохода на порядки');

      // Темп — тот же, что у дохода: доля рана, уходящая на задаток, не плывёт.
      final incomeRatio =
          Curves.goldPerFloor(anchor + 60) / Curves.goldPerFloor(anchor);
      expect(deep / Roster.hireCost(MercRank.legend), closeTo(incomeRatio, 1e-6));
    });

    test('Оборванец не дорожает никогда', () {
      // Единственный ход, который нельзя потерять: игрок без наёмника и без
      // золота не смог бы заработать снова.
      expect(Roster.hireCost(MercRank.ragged, maxDepthEver: 100000),
          Roster.hireCost(MercRank.ragged));
    });

    test('цену найма считает профиль, а не экран', () {
      // Экран найма и проверка кошелька обязаны читать одно число.
      final merc = MercFactory.roll(Rng(1), idPrefix: 'hire');
      final profile = PlayerProfile(maxDepthEver: 150);

      expect(profile.hireCostOf(merc),
          Roster.hireCost(merc.rank, maxDepthEver: 150));
    });
  });

  group('черты', () {
    test('тег-черта не превращается в общий множитель силы', () {
      // «+25 % урона Огнём» обязано остаться прибавкой к тегу.
      // Если черта применится до масштабирования, она тихо станет +25 % ко всему.
      final merc = Mercenary(
        id: 'x',
        name: 'Тест',
        rank: MercRank.ragged,
        trait: MercTrait.emberborn,
      );
      final plain = Mercenary(
        id: 'y',
        name: 'Контроль',
        rank: MercRank.ragged,
        trait: MercTrait.swift,
      );

      final stats = merc.toProfile().aggregate();
      expect(stats.tagDamage[Tag.fire], closeTo(0.25, 1e-9));

      // Общий урон обязан остаться таким же, как у наёмника без огненной
      // черты: аффиксы стартового набора у обоих одинаковы, и разницу может
      // дать только черта.
      expect(stats.increasedDamage,
          closeTo(plain.toProfile().aggregate().increasedDamage, 1e-9));
    });

    test('ранг умножает базовые статы', () {
      final ragged = Mercenary(
        id: 'a', name: 'A', rank: MercRank.ragged, trait: MercTrait.swift,
      ).toProfile().aggregate();
      final legend = Mercenary(
        id: 'b', name: 'B', rank: MercRank.legend, trait: MercTrait.swift,
      ).toProfile().aggregate();
      expect(
        legend.attackDamage / ragged.attackDamage,
        closeTo(MercRank.legend.statMultiplier, 1e-9),
      );
    });

    test('живучесть даёт ровно +20 % HP', () {
      final plain = Mercenary(
        id: 'a', name: 'A', rank: MercRank.ragged, trait: MercTrait.swift,
      ).toProfile().aggregate();
      final hardy = Mercenary(
        id: 'b', name: 'B', rank: MercRank.ragged, trait: MercTrait.hardy,
      ).toProfile().aggregate();
      expect(hardy.maxHp / plain.maxHp, closeTo(1.20, 1e-9));
    });
  });

  group('таверна', () {
    test('уровень смещает распределение к высоким рангам', () {
      double legendShare(int level) {
        final w = MercFactory.rankWeights(level);
        return w.last / w.reduce((a, b) => a + b);
      }

      expect(legendShare(6), greaterThan(legendShare(0) * 3));
    });

    test('кандидаты детерминированы по сиду', () {
      final a = MercFactory.roll(Rng(77), tavernLevel: 3);
      final b = MercFactory.roll(Rng(77), tavernLevel: 3);
      expect(a.rank, b.rank);
      expect(a.trait, b.trait);
      expect(a.name, b.name);
    });

    test('ростер не пускает больше наёмников, чем есть слотов', () {
      // Задел на нескольких наёмников: слот один, но правило уже проверяется.
      final roster = Roster();
      final m1 = Mercenary(
          id: '1', name: 'A', rank: MercRank.ragged, trait: MercTrait.swift);
      final m2 = Mercenary(
          id: '2', name: 'B', rank: MercRank.ragged, trait: MercTrait.swift);
      roster.reserve.addAll([m1, m2]);

      roster.deploy(m1);
      expect(() => roster.deploy(m2), throwsStateError);

      roster.activeSlots = 2;
      roster.deploy(m2);
      expect(roster.deployed.length, 2);
    });
  });

  group('рюкзак', () {
    test('несёт наверх ВСЁ: вместимость больше не режет добычу', () {
      // Раньше рюкзак вытеснял худшее и распылял его сам. Правило разумное,
      // но оно принимало за игрока главное решение цикла: что оставить.
      // «Худшая по уровню» вещь вполне может быть единственной с нужным
      // тегом, а наёмник про сборку не знает ничего.
      final haul = Haul(capacity: 3, salvageRate: 0.35);
      for (final ilvl in [10, 40, 20, 60, 30]) {
        haul.addItem(_item(ilvl));
      }

      expect(haul.itemCount, 5);
      expect(haul.salvagedCount, 0, reason: 'по дороге ничего не теряется');
      expect(haul.gold, 0.0);
    });

    test('находки отсортированы по убыванию уровня', () {
      // Разбор добычи показывает список как есть: лучшее сверху, чтобы
      // решение начиналось с того, ради чего спуск и был.
      final haul = Haul(capacity: 2, salvageRate: 0.35);
      haul..addItem(_item(50))..addItem(_item(10))..addItem(_item(40));
      expect(haul.items.map((i) => i.ilvl), [50, 40, 10]);
    });

    test('курс Алтаря влияет на выручку с переплавки', () {
      Haul melted(double rate) {
        final h = Haul(capacity: 1, salvageRate: rate);
        h.salvage(_item(30));
        return h;
      }

      expect(melted(0.7).salvagedGold, greaterThan(melted(0.35).salvagedGold));
    });
  });

  group('Застава', () {
    test('цена уровня растёт вместе с доходом на глубине', () {
      // Фиксированные цены обесценивались за 8 контрактов: доход растёт
      // экспоненциально, а цена — нет.
      final outpost = Outpost();
      final first = outpost.upgradeCost(Building.tavern);
      outpost..upgrade(Building.tavern)..upgrade(Building.tavern);
      final third = outpost.upgradeCost(Building.tavern);
      final incomeRatio = Curves.goldPerFloor(Outpost.depthGate(3)) /
          Curves.goldPerFloor(Outpost.depthGate(1));
      expect(third / first, closeTo(incomeRatio, 1e-9));
    });

    test('уровни ограничены потолком — кроме Хранилища', () {
      final outpost = Outpost();
      for (var i = 0; i < 50; i++) {
        outpost.upgrade(Building.tavern);
      }
      expect(outpost.levelOf(Building.tavern), Building.maxLevel);
      expect(outpost.canUpgrade(Building.tavern), isFalse);
    });

    test('Хранилище растёт без потолка — это сток для золота', () {
      // Замер кампании: к двенадцатому контракту из двадцати выкуплены и
      // древо Эха, и вся Застава, а золота копится тринадцать миллионов, и
      // деть его некуда. Награда, которую нечем потратить, перестаёт быть
      // наградой. Сундук — единственное, чего игрок хочет всегда.
      final outpost = Outpost();
      for (var i = 0; i < 50; i++) {
        outpost.upgrade(Building.vault);
      }

      expect(outpost.levelOf(Building.vault), 50);
      expect(outpost.canUpgrade(Building.vault), isTrue);
      expect(Building.vault.isEndless, isTrue);

      // И цена продолжает расти вместе с доходом, а не стоит на месте.
      final at50 = outpost.upgradeCost(Building.vault);
      final at8 = Outpost({Building.vault: 8}).upgradeCost(Building.vault);
      expect(at50, greaterThan(at8 * 10));
    });

    test('Застава не даёт прямой силы — только экономику', () {
      // Если золото начнёт покупать силу, Эхо становится лишней валютой.
      final maxed = Outpost({for (final b in Building.values) b: Building.maxLevel});
      expect(maxed.descentPowerBonus, 0.0);
      expect(maxed.stashSlots, greaterThan(Outpost().stashSlots));
      expect(maxed.salvageRate, greaterThan(Outpost().salvageRate));
    });

    test('сериализация круговая', () {
      final src = Outpost({Building.forge: 3, Building.campfire: 5});
      final back = Outpost.fromJson(src.toJson());
      for (final b in Building.values) {
        expect(back.levelOf(b), src.levelOf(b));
      }
    });
  });

  group('Застава читает контент, а не код', () {
    test('вместимость сундука берётся из balance.json', () {
      final outpost = Outpost();
      expect(outpost.stashSlots, Tuning.stashSlotsBase);

      final upgraded = Outpost({Building.vault: 3});
      expect(upgraded.stashSlots,
          Tuning.stashSlotsBase + Tuning.stashSlotsPerLevel * 3);
    });

    // Этот тест доказывает только, что числа растут. Что их кто-то ЧИТАЕТ,
    // проверяет `outpost_effects_test.dart` — без него Оружейная восемь
    // уровней подряд не делала ничего, а тест был зелёным.
    test('все производные постройки растут с уровнем', () {
      final zero = Outpost();
      final maxed = Outpost({
        for (final b in Building.values) b: Building.maxLevel,
      });

      expect(maxed.stashSlots, greaterThan(zero.stashSlots));
      expect(maxed.lootQuality, greaterThan(zero.lootQuality));
      expect(maxed.lootQuantity, greaterThan(zero.lootQuantity));
      expect(maxed.rerollFloorPercentile,
          greaterThan(zero.rerollFloorPercentile));
      expect(maxed.shardSalvageOnOverwrite,
          greaterThan(zero.shardSalvageOnOverwrite));
      expect(maxed.salvageRate, greaterThan(zero.salvageRate));
      expect(maxed.forecastFloors, greaterThan(zero.forecastFloors));
      expect(maxed.restHealBonus, greaterThan(zero.restHealBonus));
      expect(maxed.tavernCandidates, greaterThan(zero.tavernCandidates));
    });
  });
}
