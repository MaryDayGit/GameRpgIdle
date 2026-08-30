import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/affix_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/build_power.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

List<Item> _many(int count, {required int ilvl, GearKind? kind, int seed = 7}) {
  final rng = Rng(seed);
  return [
    for (var i = 0; i < count; i++)
      ItemFactory.roll(ilvl: ilvl, rng: rng, kind: kind),
  ];
}

Item _handmade({
  required GearKind kind,
  required int ilvl,
  double attackDamage = 0.0,
  double maxHp = 0.0,
  double maxHpPct = 0.0,
}) =>
    Item(
      kind: kind,
      ilvl: ilvl,
      rarity: Rarity.common,
      affixes: [
        if (attackDamage > 0)
          AffixRoll(
            affixId: 'x',
            stat: StatKey.attackDamage,
            percentile: 1.0,
            value: attackDamage,
          ),
        if (maxHp > 0)
          AffixRoll(
            affixId: 'y',
            stat: StatKey.maxHp,
            percentile: 1.0,
            value: maxHp,
          ),
        if (maxHpPct > 0)
          AffixRoll(
            affixId: 'z',
            stat: StatKey.maxHpPct,
            percentile: 1.0,
            value: maxHpPct,
          ),
      ],
    );

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('ролл', () {
    test('детерминирован по сиду', () {
      final a = _many(20, ilvl: 40);
      final b = _many(20, ilvl: 40);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].kind, b[i].kind);
        expect(a[i].rarity, b[i].rarity);
        expect(a[i].affixes.length, b[i].affixes.length);
        for (var j = 0; j < a[i].affixes.length; j++) {
          expect(a[i].affixes[j].value, b[i].affixes[j].value);
        }
      }
    });

    test('число аффиксов задаёт редкость, двуручник получает лишний', () {
      for (final item in _many(200, ilvl: 25)) {
        final slots = (Tuning.affixSlotsByRarity[item.rarity] ?? 0) +
            (item.twoHanded ? 1 : 0);
        expect(item.affixes.length + (item.triggerAffixId == null ? 0 : 1),
            slots);
      }
    });

    test('плоские статы растут от ilvl, долевые — нет', () {
      // Это главное правило роллов: если бы росли и те и другие, сила билда
      // росла бы как itemScale² и формула стены перестала бы сходиться.
      double avgOf(int ilvl, bool Function(StatAffixDef) pick) {
        final pack = ContentPack.current;
        var sum = 0.0;
        var count = 0;
        for (final item in _many(400, ilvl: ilvl)) {
          // Двуручники исключены: у них свой множитель к роллам, и они
          // сдвинули бы среднее, ничего не сказав о правиле масштабирования.
          if (item.twoHanded) continue;
          for (final roll in item.affixes) {
            final def = pack.statAffix(roll.affixId)!;
            if (!pick(def)) continue;
            sum += roll.value / roll.percentile / def.base;
            count++;
          }
        }
        return count == 0 ? 0.0 : sum / count;
      }

      // Бюджет предмета умножает всё, но от глубины долевой аффикс
      // не зависит — это и проверяем.
      expect(avgOf(1, (d) => !d.scales), closeTo(Tuning.itemPowerScale, 1e-9));
      expect(avgOf(60, (d) => !d.scales), closeTo(Tuning.itemPowerScale, 1e-9),
          reason: 'долевой аффикс на 60-м этаже обязан остаться тем же');

      final flatDeep = avgOf(60, (d) => d.scales);
      expect(flatDeep, closeTo(Curves.itemScale(60) * Tuning.itemPowerScale, 1e-6));
    });

    test('имплицит есть всегда и не зависит от редкости', () {
      for (final item in _many(120, ilvl: 30)) {
        expect(item.implicit, isNotNull, reason: '${item.kind.name}');
        expect(item.implicit!.percentile, 1.0);

        final def = ContentPack.current.implicitFor(item.kind)!;
        final bonus = item.twoHanded ? 1.0 + Tuning.twoHandedRollBonus : 1.0;
        expect(
          item.implicit!.value,
          closeTo(
              def.base * Curves.itemScale(30) * Tuning.itemPowerScale * bonus,
              1e-6),
        );
      }
    });

    test('предмет глубже — апгрейд сам по себе, даже обычный против редкого',
        () {
      // Ровно та поломка, ради которой имплициты и появились: без них
      // апгрейдом мог стать только удачный редкий ролл.
      final rng = Rng(1);
      final shallowRare = ItemFactory.roll(ilvl: 20, rng: rng, kind: GearKind.weapon);
      final deepCommon = Item(
        kind: GearKind.weapon,
        ilvl: 60,
        rarity: Rarity.common,
        affixes: const [],
        implicit: AffixRoll(
          affixId: 'implicit.weapon',
          stat: ContentPack.current.implicitFor(GearKind.weapon)!.stat,
          percentile: 1.0,
          value: ContentPack.current.implicitFor(GearKind.weapon)!.base *
              Curves.itemScale(60) *
              Tuning.itemPowerScale,
        ),
      );

      final equipment = Equipment()..equipAt(0, shallowRare);
      final gain = equipment.gainFrom(deepCommon,
          base: Tuning.heroBase, depth: 60);
      expect(gain, greaterThan(0.0));
    });

    test('триггер — не больше одного и только на разрешённых типах', () {
      for (final item in _many(400, ilvl: 30)) {
        if (item.triggerAffixId == null) continue;
        expect(triggerAllowedKinds, contains(item.kind));
        final def = ContentPack.current.triggerAffix(item.triggerAffixId!);
        expect(def, isNotNull);
        expect(def!.kinds, contains(item.kind));
      }
    });

    test('реликт выпадает только с реликтовой редкостью и по типу предмета',
        () {
      var relics = 0;
      for (final item in _many(600, ilvl: 30)) {
        if (item.relicId == null) continue;
        relics++;
        expect(item.rarity, Rarity.relic);
        expect(ContentPack.current.relic(item.relicId!)!.kind, item.kind);
      }
      expect(relics, greaterThan(0), reason: 'реликты обязаны выпадать');
    });

    test('качество добычи наклоняет редкость, но не отменяет обычные', () {
      int relicsAt(double quality) {
        final rng = Rng(99);
        var count = 0;
        for (var i = 0; i < 600; i++) {
          final item =
              ItemFactory.roll(ilvl: 20, rng: rng, lootQuality: quality);
          if (item.rarity == Rarity.relic) count++;
        }
        return count;
      }

      expect(relicsAt(1.0), greaterThan(relicsAt(0.0)));
    });
  });

  group('экипировка', () {
    test('пустой слот заполняется всегда', () {
      final equipment = Equipment();
      final item = _handmade(kind: GearKind.helmet, ilvl: 5);
      expect(
        equipment.tryEquip(item, base: Tuning.heroBase, depth: 5),
        isEmpty,
      );
      expect(equipment.filledSlots, 1);
    });

    test('худшее не вытесняет лучшее, лучшее вытесняет и возвращается', () {
      final equipment = Equipment();
      final good = _handmade(kind: GearKind.weapon, ilvl: 40, attackDamage: 50);
      final bad = _handmade(kind: GearKind.weapon, ilvl: 90, attackDamage: 1);

      equipment.tryEquip(good, base: Tuning.heroBase, depth: 40);

      // Уровень выше, но статы хуже — предмет остаётся на руках.
      expect(
        equipment.tryEquip(bad, base: Tuning.heroBase, depth: 40),
        [same(bad)],
        reason: 'решает сила билда, а не ilvl',
      );

      final better =
          _handmade(kind: GearKind.weapon, ilvl: 41, attackDamage: 90);
      expect(
        equipment.tryEquip(better, base: Tuning.heroBase, depth: 40),
        [same(good)],
        reason: 'вытесненное возвращается, а не исчезает',
      );
    });

    test('второе кольцо занимает второй слот, а не вытесняет первое', () {
      final equipment = Equipment();
      final a = _handmade(kind: GearKind.ring, ilvl: 10, maxHp: 100);
      final b = _handmade(kind: GearKind.ring, ilvl: 10, maxHp: 100);

      expect(equipment.tryEquip(a, base: Tuning.heroBase, depth: 10), isEmpty);
      expect(equipment.tryEquip(b, base: Tuning.heroBase, depth: 10), isEmpty);
      expect(equipment.filledSlots, 2);
    });

    test('долевой множитель HP считается от собранной суммы, а не от базы', () {
      final equipment = Equipment()
        ..equipAt(3, _handmade(kind: GearKind.armor, ilvl: 10, maxHp: 300))
        ..equipAt(8, _handmade(kind: GearKind.amulet, ilvl: 10, maxHpPct: 0.5));

      const base = StatBlock(maxHp: 200.0);
      expect(equipment.apply(base).maxHp, closeTo((200 + 300) * 1.5, 1e-9));
    });

    test('дельта к надетому отрицательна для худшего предмета', () {
      final equipment = Equipment()
        ..equipAt(0, _handmade(kind: GearKind.weapon, ilvl: 40, attackDamage: 60));

      final worse = _handmade(kind: GearKind.weapon, ilvl: 40, attackDamage: 5);
      expect(equipment.gainFrom(worse, base: Tuning.heroBase, depth: 40), 0.0,
          reason: 'ухудшение не показывается как прирост');

      final better =
          _handmade(kind: GearKind.weapon, ilvl: 40, attackDamage: 120);
      expect(equipment.gainFrom(better, base: Tuning.heroBase, depth: 40),
          greaterThan(0.0));
    });

    test('сбор лоадаута забирает из сундука и оставляет остаток', () {
      final stash = _many(30, ilvl: 30);
      final before = stash.length;

      final equipment = Equipment();
      equipment.equipFrom(stash, base: Tuning.heroBase, depth: 30);

      expect(equipment.filledSlots, greaterThan(0));
      expect(stash.length, before - equipment.filledSlots);
    });

    test('снятое возвращается целиком', () {
      final stash = _many(30, ilvl: 30);
      final equipment = Equipment()
        ..equipFrom(stash, base: Tuning.heroBase, depth: 30);

      final worn = equipment.filledSlots;
      expect(equipment.unequipAll(), hasLength(worn));
      expect(equipment.filledSlots, 0);
    });

    test('снаряжение усиливает билд', () {
      final stash = _many(40, ilvl: 50);
      final equipment = Equipment()
        ..equipFrom(stash, base: Tuning.heroBase, depth: 50);

      final bare = BuildPower.of(Tuning.heroBase, 50);
      final geared = BuildPower.of(equipment.apply(Tuning.heroBase), 50);
      expect(geared, greaterThan(bare * 2));
    });
  });
}
