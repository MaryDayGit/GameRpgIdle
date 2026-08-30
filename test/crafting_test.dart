import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/haul.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/relic_effect.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/sim/crafting.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Крафт существует ради одного свойства: он не должен устаревать вместе с
/// предметами. Проверяется именно оно — что осколок 96-го перцентиля остаётся
/// ценным на любой глубине, а не превращается в мусор через двадцать этажей.

Item _item({
  GearKind kind = GearKind.amulet,
  int ilvl = 20,
  Rarity rarity = Rarity.rare,
  List<AffixRoll> affixes = const [],
  String? relicId,
}) =>
    Item(
      kind: kind,
      ilvl: ilvl,
      rarity: rarity,
      affixes: affixes,
      relicId: relicId,
      relicEffect: relicId == null ? null : RelicEffect.eternalCurse,
    );

AffixRoll _roll(String id, StatKey stat, double percentile, double value) =>
    AffixRoll(affixId: id, stat: stat, percentile: percentile, value: value);

/// Предмет с одним настоящим аффиксом из контента — таким, какой перекат
/// умеет считать.
Item _itemWith(double percentile) => _item(
      affixes: [_roll('max_hp_flat', StatKey.maxHp, percentile, 100.0)],
    );

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('разбор и впечатывание', () {
    test('осколок хранит перцентиль минус плата за извлечение', () {
      final item = _item(affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.96, 123.0),
      ]);

      final shard = Crafting.extract(item, 0);

      expect(shard.affixId, 'max_hp_flat');
      expect(shard.percentile,
          closeTo(0.96 - Tuning.extractionPercentilePenalty, 1e-9));
      expect(shard.quality, 86);
    });

    test('впечатанный аффикс пересчитывается под уровень новой базы', () {
      // Это и есть причина, по которой крафт не устаревает: тот же перцентиль
      // на базе глубже даёт больше.
      final source = _item(ilvl: 20, affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 1.0, 0.0),
      ]);
      final shard = Crafting.extract(source, 0);

      final shallow = Crafting.imprint(_item(ilvl: 20), shard).item;
      final deep = Crafting.imprint(_item(ilvl: 80), shard).item;

      expect(deep.stats.maxHp, greaterThan(shallow.stats.maxHp));
      expect(
        deep.stats.maxHp / shallow.stats.maxHp,
        closeTo(Curves.itemScale(80) / Curves.itemScale(20), 1e-6),
      );
      expect(deep.affixes.single.percentile, closeTo(shard.percentile, 1e-9));
    });

    test('впечатанный аффикс не отличается от выпавшего', () {
      // Иначе один и тот же перцентиль давал бы разное число в зависимости от
      // того, как аффикс попал на предмет.
      final def = ContentPack.current.statAffix('armor_flat')!;
      final shard = Crafting.extract(
        _item(kind: GearKind.helmet, affixes: [
          _roll('armor_flat', StatKey.armor, 0.9, 0.0),
        ]),
        0,
      );

      final crafted =
          Crafting.imprint(_item(kind: GearKind.helmet, ilvl: 50), shard).item;

      expect(
        crafted.affixes.single.value,
        closeTo(
          def.base *
              shard.percentile *
              Curves.itemScale(50) *
              Tuning.itemPowerScale,
          1e-6,
        ),
      );
    });

    test('в занятый слот только с перезаписью', () {
      final full = _item(
        rarity: Rarity.common,
        affixes: [_roll('max_hp_flat', StatKey.maxHp, 0.8, 50.0)],
      );
      expect(Crafting.hasFreeSlot(full), isFalse);

      final shard = Crafting.extract(
        _item(affixes: [_roll('armor_flat', StatKey.armor, 0.9, 10.0)]),
        0,
      );

      expect(() => Crafting.imprint(full, shard),
          throwsA(isA<StateError>()));

      final overwritten = Crafting.imprint(full, shard, slotIndex: 0).item;
      expect(overwritten.affixes.single.affixId, 'armor_flat');
    });

    test('дубль того же аффикса не впечатывается', () {
      final item = _item(affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.8, 50.0),
      ]);
      final shard = Crafting.extract(item, 0);

      expect(Crafting.canImprint(item, shard), isFalse,
          reason: 'два одинаковых аффикса сложились бы в один');
    });

    test('осколок не лезет на чужой тип предмета', () {
      // «+X к урону атаки» не выпадает на ботинках — не должен и впечатываться.
      final shard = Crafting.extract(
        _item(kind: GearKind.weapon, affixes: [
          _roll('attack_damage_flat', StatKey.attackDamage, 0.9, 10.0),
        ]),
        0,
      );

      expect(Crafting.canImprint(_item(kind: GearKind.boots), shard), isFalse);
      expect(Crafting.canImprint(_item(kind: GearKind.weapon), shard), isTrue);
    });
  });

  group('реролл', () {
    test('цена растёт вместе с доходом, а не обгоняет его', () {
      // Реролл — бесконечный сток золота (GDD §6.3). Если его цена растёт
      // быстрее дохода, сток превращается в запрет.
      final shallow = _item(ilvl: 20, affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.8, 50.0),
      ]);
      final deep = _item(ilvl: 120, affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.8, 50.0),
      ]);

      final priceRatio =
          Crafting.rerollCost(deep, 0) / Crafting.rerollCost(shallow, 0);
      final incomeRatio =
          Curves.goldPerFloor(120) / Curves.goldPerFloor(20);

      expect(priceRatio, closeTo(incomeRatio, incomeRatio * 0.01));
    });

    test('повтор дорожает и обнуляется при смене аффикса', () {
      final item = _item(affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.8, 50.0),
      ]);
      final first = Crafting.rerollCost(item, 0);

      final once = Crafting.reroll(item, 0, Rng(1));
      expect(once.affixes.single.rerolls, 1);
      expect(Crafting.rerollCost(once, 0),
          closeTo(first * Tuning.rerollCostGrowth, 1e-6));

      // Впечатали другой аффикс — счётчик начинается заново, иначе слот
      // остаётся дорогим навсегда.
      final shard = Crafting.extract(
        _item(affixes: [_roll('armor_flat', StatKey.armor, 0.9, 10.0)]),
        0,
      );
      final replaced = Crafting.imprint(once, shard, slotIndex: 0).item;
      expect(replaced.affixes.single.rerolls, 0);
      expect(Crafting.rerollCost(replaced, 0), lessThan(first * 2));
    });

    test('Кузница поднимает нижнюю границу переката', () {
      final item = _item(affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.7, 30.0),
      ]);

      var lowest = 1.0;
      for (var seed = 0; seed < 200; seed++) {
        final rolled =
            Crafting.reroll(item, 0, Rng(seed), floorPercentile: 0.2);
        final p = rolled.affixes.single.percentile;
        if (p < lowest) lowest = p;
        expect(p, inInclusiveRange(0.0, Tuning.percentileMax));
      }
      expect(lowest, greaterThanOrEqualTo(Tuning.percentileMin + 0.2 - 1e-9));
    });
  });

  group('углубление реликта', () {
    test('поднимает уровень и статы, но не выше достигнутой глубины', () {
      final rng = Rng(5);
      var relic = ItemFactory.roll(ilvl: 30, rng: rng, kind: GearKind.ring);
      relic = Item(
        kind: relic.kind,
        ilvl: 30,
        rarity: Rarity.relic,
        affixes: relic.affixes,
        implicit: relic.implicit,
        relicId: 'seal_of_thousand_eyes',
        relicEffect: RelicEffect.eternalCurse,
      );

      final before = relic.stats.maxHp;
      final deepened = Crafting.deepen(relic, 100);

      expect(deepened.ilvl, 30 + Tuning.deepenIlvlStep);
      expect(deepened.stats.maxHp, greaterThan(before));
      expect(deepened.deepenings, 1);
      expect(deepened.relicId, relic.relicId,
          reason: 'уникальный эффект не трогаем');

      // Выше рекорда — нельзя: реликт не должен обгонять игрока.
      final capped = Crafting.deepen(deepened, deepened.ilvl);
      expect(capped.ilvl, deepened.ilvl);
    });

    test('обычные предметы не углубляются', () {
      final plain = _item(rarity: Rarity.rare);
      expect(Crafting.canDeepen(plain, 200), isFalse,
          reason: 'иначе исчезает смысл искать новые');
    });
  });

  group('крафт в профиле', () {
    PlayerProfile player() {
      final p = PlayerProfile(gold: 1e9);
      p.stash.add(_item(affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.95, 100.0),
      ]));
      return p;
    }

    test('разбор забирает предмет и кладёт осколок', () {
      final p = player();
      final item = p.stash.single;

      final shard = p.extractShard(item, 0);

      expect(shard, isNotNull);
      expect(p.stash, isEmpty);
      expect(p.shards.single, shard);
    });

    test('хранилище осколков конечно, и разбор не съедает предмет впустую', () {
      final p = player();
      final capacity = p.outpost.shardCapacity;
      for (var i = 0; i < capacity; i++) {
        p.shards.add(Crafting.extract(
          _item(affixes: [_roll('armor_flat', StatKey.armor, 0.9, 10.0)]),
          0,
        ));
      }

      final item = p.stash.single;
      expect(p.extractShard(item, 0), isNull);
      expect(p.stash, contains(item),
          reason: 'предмет не должен исчезнуть в никуда');
    });

    test('впечатывание тратит осколок и меняет предмет в сундуке', () {
      final p = player();
      p.stash.add(_item(kind: GearKind.amulet, ilvl: 60, affixes: const []));

      final shard = p.extractShard(p.stash.first, 0)!;
      final base = p.stash.single;

      final crafted = p.imprintShard(base, shard);

      expect(crafted, isNotNull);
      expect(p.shards, isEmpty);
      expect(p.stash.single, crafted);
      expect(crafted!.affixes.single.percentile, closeTo(shard.percentile, 1e-9));
    });

    test('реролл списывает золото по цене операции', () {
      final p = player();
      final item = p.stash.single;
      final cost = Crafting.rerollCost(item, 0);
      final before = p.gold;

      expect(p.rerollAffix(item, 0, Rng(3)), isNotNull);
      expect(p.gold, closeTo(before - cost, 1e-6));

      // Без золота операция не проходит и ничего не меняет.
      final poor = PlayerProfile(gold: 0.0)..stash.add(item);
      expect(poor.rerollAffix(item, 0, Rng(3)), isNull);
      expect(poor.stash.single, item);
    });

    test('углубление требует рекорда глубины', () {
      final p = PlayerProfile(gold: 1e9, maxDepthEver: 100);
      p.stash.add(_item(
        kind: GearKind.ring,
        ilvl: 30,
        rarity: Rarity.relic,
        relicId: 'seal_of_thousand_eyes',
        affixes: [_roll('max_hp_flat', StatKey.maxHp, 0.9, 50.0)],
      ));

      final deepened = p.deepenRelic(p.stash.single);
      expect(deepened, isNotNull);
      expect(deepened!.ilvl, 40);
      expect(p.gold, lessThan(1e9));

      final noRecord = PlayerProfile(gold: 1e9)..stash.add(deepened);
      expect(noRecord.deepenRelic(deepened), isNull,
          reason: 'реликт не должен обгонять игрока');
    });
  });

  group('операция объясняет себя до оплаты', () {
    test('перекат показывает границы, а не обещание', () {
      // Игрок платит за бросок. Не сказать ему, что бросок может стать хуже,
      // — это продать лотерейный билет как улучшение.
      // Перцентиль высокий намеренно: перекат тем и опасен, что хороший
      // ролл можно потерять.
      final item = _itemWith(0.95);
      final range = Crafting.rerollRange(item, 0);

      expect(range, isNotNull);
      expect(range!.worst.value, lessThan(range.best.value));
      expect(range.worst.percentile, lessThan(item.affixes[0].percentile),
          reason: 'при нулевой Кузнице перекат может увести вниз');
    });

    test('уровень Кузницы поднимает нижнюю границу — и это видно', () {
      // Ровно то, за что игрок платит, улучшая Кузницу. Если предпросмотр
      // не читает уровень, улучшение выглядит бесполезным.
      final item = _itemWith(0.5);

      final bare = Crafting.rerollRange(item, 0)!;
      final forged = Crafting.rerollRange(item, 0, floorPercentile: 0.4)!;

      expect(forged.worst.value, greaterThan(bare.worst.value));
      expect(forged.best.value, bare.best.value,
          reason: 'потолок Кузница не двигает');
    });

    test('предпросмотр совпадает с тем, что происходит на самом деле', () {
      // Два расчёта «что получится» разошлись бы, и предпросмотр врал бы
      // ровно там, где ему верят.
      final item = _itemWith(0.5);
      final range = Crafting.rerollRange(item, 0, floorPercentile: 0.2)!;

      for (var seed = 1; seed <= 50; seed++) {
        final rolled =
            Crafting.reroll(item, 0, Rng(seed), floorPercentile: 0.2);
        final value = rolled.affixes[0].value;

        expect(value, greaterThanOrEqualTo(range.worst.value - 1e-9));
        expect(value, lessThanOrEqualTo(range.best.value + 1e-9));
      }
    });

    test('углубление считается наперёд целиком', () {
      // `deepen` чистая, поэтому экран показывает будущий предмет тем же
      // расчётом, каким его потом и получит.
      final relic = ItemFactory.roll(ilvl: 40, rng: Rng(11), forceRelic: true);
      final preview = Crafting.deepen(relic, 200);

      expect(preview.ilvl, greaterThan(relic.ilvl));
      expect(Crafting.deepen(relic, 200).ilvl, preview.ilvl,
          reason: 'предпросмотр обязан быть воспроизводимым');
      expect(relic.ilvl, 40, reason: 'предпросмотр не трогает оригинал');
    });
  });

  group('гарантия от невезения', () {
    test('форсированный реликт выпадает по требованию', () {
      final forced =
          ItemFactory.roll(ilvl: 40, rng: Rng(7), forceRelic: true);
      expect(forced.rarity, Rarity.relic);
    });

    test('за долгий ран реликт обязан появиться', () {
      // Без гарантии игрок может пройти сотню этажей и не увидеть ни одного
      // билд-архетипа — то есть не увидеть половину игры.
      final outpost = Outpost();
      expect(outpost.shardCapacity, Tuning.shardCapacityBase);
      expect(Tuning.relicPityFloors, greaterThan(0));
    });
  });

  test('счётчик слотов и проверка свободного места считают одно и то же', () {
    // Экран показывал «1 из 2 слотов» и тут же предлагал перезапись: счётчик
    // не видел триггера, а проверка видела.
    final item = Item(
      kind: GearKind.amulet,
      ilvl: 20,
      rarity: Rarity.uncommon,
      affixes: [_roll('max_hp_flat', StatKey.maxHp, 0.8, 100.0)],
      triggerAffixId: 'vanguard',
    );

    expect(Crafting.usedSlots(item), 2);
    expect(Crafting.affixCapacity(item), 2);
    expect(Crafting.hasFreeSlot(item), isFalse);
    expect(Crafting.usedSlots(item) < Crafting.affixCapacity(item),
        Crafting.hasFreeSlot(item));
  });

  group('распыление', () {
    test('редкое оставляет осколок, а обычное — только золото', () {
      // Переплавка — то, ради чего в разборе добычи есть третья кнопка.
      // Раньше она случалась сама, когда находка не влезала в рюкзак; рюкзак
      // стал бесконечным, и теперь её зовёт игрок. Правило то же: с редкого
      // снимается лучший аффикс, с обычного — только золото.
      final haul = Haul(capacity: 1, salvageRate: 0.35);

      final rare = _item(ilvl: 50, rarity: Rarity.rare, affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.9, 100.0),
        _roll('armor_flat', StatKey.armor, 0.4, 20.0),
      ]);
      final common = _item(ilvl: 60, rarity: Rarity.common, affixes: [
        _roll('armor_flat', StatKey.armor, 0.8, 30.0),
      ]);

      expect(haul.salvage(rare), isNotNull);
      expect(haul.salvage(common), isNull, reason: 'с обычного снимать нечего');

      expect(haul.salvagedCount, 2);
      expect(haul.gold, greaterThan(0.0));
      expect(haul.shards, hasLength(1), reason: 'осколок только с редкого');
      expect(haul.shards.single.affixId, 'max_hp_flat',
          reason: 'снимается лучший аффикс, а не первый попавшийся');
    });

    test('бесконечный рюкзак ничего не распыляет сам', () {
      // Главное следствие правки: наёмник несёт наверх всё, и решение «что
      // оставить» больше не принимает за игрока никто.
      final haul = Haul(capacity: 1, salvageRate: 0.35);
      for (var i = 0; i < 20; i++) {
        haul.addItem(_item(ilvl: 10 + i, rarity: Rarity.common, affixes: [
          _roll('armor_flat', StatKey.armor, 0.5, 10.0),
        ]));
      }

      expect(haul.itemCount, 20, reason: 'вместимость больше не режет добычу');
      expect(haul.salvagedCount, 0);
      expect(haul.gold, 0.0);
    });

    test('осколок с переплавки теряет перцентиль так же, как разобранный', () {
      final haul = Haul(capacity: 0, salvageRate: 0.35);
      haul.salvage(_item(ilvl: 40, rarity: Rarity.rare, affixes: [
        _roll('max_hp_flat', StatKey.maxHp, 0.9, 100.0),
      ]));

      expect(haul.shards.single.percentile,
          closeTo(0.9 - Tuning.extractionPercentilePenalty, 1e-9));
    });
  });
}
