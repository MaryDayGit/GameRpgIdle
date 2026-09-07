import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../content/affix_def.dart';
import '../content/content_pack.dart';
import '../model/equipment.dart';
import '../model/gear.dart';
import '../model/item.dart';
import '../model/relic_effect.dart';
import '../model/stat_key.dart';
import 'rng.dart';

/// Генерация предметов (GDD §4.2–4.4).
///
/// Главное правило роллов, ради которого существует флаг `scales` в контенте:
/// плоские статы растут как `itemScale(ilvl)`, долевые — нет. Если бы росли и
/// те и другие, сила билда росла бы как `itemScale²`, и формула стены
/// (GDD §2.3) перестала бы сходиться — кривая сложности разъезжалась бы тем
/// сильнее, чем глубже спуск. Валидатор контента проверяет это же правило со
/// своей стороны.
class ItemFactory {
  ItemFactory._();

  /// Предмет с глубины [ilvl].
  ///
  /// [lootQuality] сдвигает веса редкости в сторону старших: вес умножается на
  /// `(1 + lootQuality)^ранг`. Обычные предметы при этом не исчезают, просто
  /// становятся реже относительно редких — это наклон, а не порог.
  static Item roll({
    required int ilvl,
    required Rng rng,
    GearKind? kind,
    double lootQuality = 0.0,
    int rarityBonus = 0,
    int bonusAffixSlots = 0,
    bool forceRelic = false,
  }) {
    final pack = ContentPack.current;

    final itemKind = kind ?? GearKind.values[rng.nextInt(GearKind.values.length)];
    // Модификатор «Пустотная гниль» поднимает редкость сундука на ранг —
    // это подъём уже выпавшего, а не наклон весов: гарантия, а не шанс.
    final rarity = forceRelic
        ? Rarity.relic
        : _raise(_rollRarity(rng, lootQuality), rarityBonus);

    // Двуручник занимает оба слота рук и получает за это лишний аффикс и
    // усиленные роллы: два слота под аффиксы против концентрированной мощи.
    final twoHanded = itemKind == GearKind.weapon &&
        rng.chance(Tuning.twoHandedChance);
    final rollBonus = twoHanded ? 1.0 + Tuning.twoHandedRollBonus : 1.0;
    // Узел древа «Печать мастера» даёт лишний слот ВСЕМ предметам: и уже
    // лежащим в сундуке (через `Crafting.affixCapacity`), и тем, что упадут.
    final slots = (Tuning.affixSlotsByRarity[rarity] ?? 1) +
        (twoHanded ? 1 : 0) +
        bonusAffixSlots;

    final statPool = [
      for (final def in pack.statAffixes)
        if (def.kinds.contains(itemKind)) def,
    ];
    final triggerPool = [
      for (final def in pack.triggerAffixes)
        if (def.kinds.contains(itemKind)) def,
    ];

    // Веса пулов слота — характер слота, записанный числом (`ImplicitDef`).
    // Ролл выбирает СНАЧАЛА пул, потом аффикс внутри него: иначе доля защиты
    // у слота получалась бы суммой двадцати шести чужих весов, и подвинуть её
    // было бы нечем.
    final slotPools = pack.implicitFor(itemKind)?.pools ?? const {};

    final affixes = <AffixRoll>[];
    String? triggerId;
    var triggersLeft = Tuning.maxTriggerAffixesPerItem;

    for (var i = 0; i < slots; i++) {
      final statCount = statPool.length;
      final triggerCount = triggersLeft > 0 ? triggerPool.length : 0;
      if (statCount + triggerCount == 0) break;

      // Стат против триггера — по прежним общим весам: доля триггеров на
      // предмете от разбиения на пулы не меняется, меняется только то, какой
      // именно стат выпадет.
      final statWeight = statPool.fold<double>(0, (a, d) => a + d.weight);
      final triggerWeight = triggersLeft == 0
          ? 0.0
          : triggerPool.fold<double>(0, (a, d) => a + d.weight);

      if (statCount > 0 &&
          (triggerWeight <= 0 ||
              rng.weightedIndex([statWeight, triggerWeight]) == 0)) {
        final def = _pickStat(statPool, slotPools, rng);
        statPool.remove(def);
        affixes.add(_rollAffix(def, ilvl, rng, rollBonus));
      } else {
        final index =
            rng.weightedIndex([for (final def in triggerPool) def.weight]);
        final def = triggerPool.removeAt(index);
        triggerId = def.id;
        triggersLeft--;
      }
    }

    // Реликт — это редкость, а не отдельный тип предмета: он несёт и обычные
    // аффиксы, и уникальное правило. Правило одно на тип предмета (§04-RELICS).
    String? relicId;
    RelicEffect? relicEffect;
    if (rarity == Rarity.relic) {
      for (final relic in pack.relics) {
        if (relic.kind == itemKind) {
          relicId = relic.id;
          relicEffect = relic.effect;
          break;
        }
      }
    }

    final implicitDef = pack.implicitFor(itemKind);

    return Item(
      kind: itemKind,
      ilvl: ilvl,
      rarity: rarity,
      affixes: affixes,
      implicit: implicitDef == null
          ? null
          : AffixRoll(
              affixId: 'implicit.${itemKind.name}',
              stat: implicitDef.stat,
              percentile: 1.0,
              value: implicitDef.base *
                  Curves.itemScale(ilvl) *
                  Tuning.itemPowerScale *
                  rollBonus,
            ),
      triggerAffixId: triggerId,
      relicId: relicId,
      relicEffect: relicEffect,
      twoHanded: twoHanded,
    );
  }

  /// Выбирает статовый аффикс: сперва пул по весам слота, потом аффикс.
  ///
  /// Пулы, в которых на этом предмете уже ничего не осталось, из розыгрыша
  /// выпадают: слот с весами «защита 75, утилита 25», у которого разобрали всю
  /// утилиту, обязан докатывать защитой, а не терять слот аффикса.
  static StatAffixDef _pickStat(
    List<StatAffixDef> pool,
    Map<AffixPool, double> slotPools,
    Rng rng,
  ) {
    final kinds = <AffixPool>[];
    final weights = <double>[];
    for (final entry in slotPools.entries) {
      if (entry.value <= 0.0) continue;
      if (!pool.any((d) => d.pool == entry.key)) continue;
      kinds.add(entry.key);
      weights.add(entry.value);
    }

    // Пулов у слота нет вовсе — старое поведение: разыгрываем всё скопом.
    // Валидатор такого не пропустит, но ролл не должен падать из-за контента.
    if (kinds.isEmpty) {
      return pool[rng.weightedIndex([for (final d in pool) d.weight])];
    }

    final chosen = kinds[rng.weightedIndex(weights)];
    final inPool = [for (final d in pool) if (d.pool == chosen) d];
    return inPool[rng.weightedIndex([for (final d in inPool) d.weight])];
  }

  static AffixRoll _rollAffix(
      StatAffixDef def, int ilvl, Rng rng, double rollBonus) {
    final percentile = rng.nextRange(Tuning.percentileMin, Tuning.percentileMax);
    final scale = def.scales ? Curves.itemScale(ilvl) : 1.0;

    return AffixRoll(
      affixId: def.id,
      stat: def.stat,
      percentile: percentile,
      value: def.base * percentile * scale * Tuning.itemPowerScale * rollBonus,
      tag: def.stat == StatKey.tagDamage && def.family.isNotEmpty
          ? def.family[rng.nextInt(def.family.length)]
          : null,
    );
  }

  static Rarity _raise(Rarity rarity, int steps) {
    if (steps <= 0) return rarity;
    final index = (rarity.index + steps).clamp(0, Rarity.values.length - 1);
    return Rarity.values[index];
  }

  static Rarity _rollRarity(Rng rng, double lootQuality) {
    final rarities = Rarity.values;
    final weights = <double>[
      for (final r in rarities)
        (Tuning.rarityWeights[r] ?? 0.0) *
            _pow(1.0 + lootQuality, r.rank),
    ];
    return rarities[rng.weightedIndex(weights)];
  }

  static double _pow(double base, int exp) {
    var out = 1.0;
    for (var i = 0; i < exp; i++) {
      out *= base;
    }
    return out;
  }

  /// Стартовый набор нового наёмника: оружие и доспех первого уровня.
  ///
  /// Сид фиксирован намеренно. Стартовый лоадаут — это точка отсчёта, с
  /// которой сравнивается вся ранняя прогрессия; случайный старт сделал бы
  /// первые десять минут игры лотереей, а замеры первого рана — шумом.
  static Equipment starterKit() {
    final equipment = Equipment();
    final rng = Rng.stream(0, 0, 0, RngPurpose.lootRoll);
    for (final kind in const [GearKind.weapon, GearKind.armor]) {
      final item = roll(ilvl: 1, rng: rng, kind: kind);
      equipment.tryEquip(item, base: Tuning.heroBase, depth: 1);
    }
    return equipment;
  }
}
