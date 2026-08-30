import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../content/affix_def.dart';
import '../content/content_pack.dart';
import '../model/item.dart';
import '../model/shard.dart';
import '../model/stat_key.dart';
import '../model/tags.dart';
import 'rng.dart';

/// Крафт: разбор, впечатывание, реролл, углубление (GDD §5.3, §6.3).
///
/// Все операции ЧИСТЫЕ: предмет иммутабелен, каждая возвращает новый. Так у
/// вещи нет промежуточных состояний — сейв не может застать её на середине
/// изменения, а отменить неудачную операцию значит просто не сохранить
/// результат.
///
/// Стоимость и вероятности живут в контенте. Здесь только правила.
class Crafting {
  Crafting._();

  /// Сколько аффиксов вмещает предмет: по редкости плюс открытые слоты.
  static int affixCapacity(Item item, {int treeBonus = 0}) =>
      (Tuning.affixSlotsByRarity[item.rarity] ?? 1) +
      (item.twoHanded ? 1 : 0) +
      item.bonusAffixSlots +
      treeBonus;

  /// Сколько слотов предмета занято.
  ///
  /// Триггер занимает слот наравне с обычным аффиксом. Считать его отдельно
  /// нельзя: экран показывал «1 из 2 слотов» и тут же предлагал перезапись,
  /// потому что счётчик и проверка расходились в одном слагаемом.
  static int usedSlots(Item item) =>
      item.affixes.length + (item.triggerAffixId == null ? 0 : 1);

  /// Есть ли куда впечатывать без перезаписи.
  static bool hasFreeSlot(Item item, {int treeBonus = 0}) =>
      usedSlots(item) < affixCapacity(item, treeBonus: treeBonus);

  // --- Разбор ---------------------------------------------------------------

  /// Превращает аффикс предмета в осколок. Предмет при этом уничтожается —
  /// удалить его из сундука должен вызывающий.
  ///
  /// Плата за извлечение снимается всегда и именно поэтому существует: без
  /// неё выгодно было бы бесконечно пересаживать один и тот же ролл, и охота
  /// за новыми прекратилась бы (GDD §5.3).
  static Shard extract(Item item, int affixIndex) {
    if (affixIndex < 0 || affixIndex >= item.affixes.length) {
      throw RangeError('Нет аффикса №$affixIndex');
    }
    final roll = item.affixes[affixIndex];

    return Shard(
      affixId: roll.affixId,
      stat: roll.stat,
      tag: roll.tag,
      percentile: (roll.percentile - Tuning.extractionPercentilePenalty)
          .clamp(0.0, 1.0),
    );
  }

  /// Можно ли впечатать осколок в этот предмет.
  ///
  /// Проверяется тип предмета, а не уровень: требований к уровню у крафта нет
  /// намеренно — осколок пересчитывается под ilvl базы, и в этом весь смысл.
  static bool canImprint(Item item, Shard shard) {
    final def = ContentPack.current.statAffix(shard.affixId);
    if (def == null) return false;
    if (!def.kinds.contains(item.kind)) return false;

    // Два одинаковых аффикса на одном предмете складывались бы в один и
    // выглядели бы как ошибка отображения.
    return !item.affixes.any(
        (a) => a.affixId == shard.affixId && a.tag == shard.tag);
  }

  /// Впечатывает осколок. `slotIndex` = null — в свободный слот; иначе
  /// перезаписывает указанный аффикс.
  ///
  /// Возвращает новый предмет и то, что осталось от стёртого аффикса:
  /// Верстак осколков даёт шанс сохранить его вместо потери.
  static ({Item item, Shard? displaced}) imprint(
    Item item,
    Shard shard, {
    int? slotIndex,
    double salvageChance = 0.0,
    int treeBonus = 0,
    Rng? rng,
  }) {
    final def = ContentPack.current.statAffix(shard.affixId);
    if (def == null) {
      throw StateError('Нет аффикса «${shard.affixId}» в контенте');
    }

    final roll = _rollFrom(def, shard.percentile, item.ilvl, shard.tag);
    final affixes = [...item.affixes];

    Shard? displaced;
    if (slotIndex == null) {
      if (!hasFreeSlot(item, treeBonus: treeBonus)) {
        throw StateError('Свободных слотов нет — нужен номер для перезаписи');
      }
      affixes.add(roll);
    } else {
      if (slotIndex < 0 || slotIndex >= affixes.length) {
        throw RangeError('Нет аффикса №$slotIndex');
      }
      final old = affixes[slotIndex];
      affixes[slotIndex] = roll;

      // Верстак умеет спасать стираемое. Шанс, а не гарантия: иначе
      // перезапись перестала бы быть риском и выбором.
      if (salvageChance > 0.0 && (rng?.chance(salvageChance) ?? false)) {
        displaced = Shard(
          affixId: old.affixId,
          stat: old.stat,
          tag: old.tag,
          percentile: (old.percentile - Tuning.extractionPercentilePenalty)
              .clamp(0.0, 1.0),
        );
      }
    }

    return (item: item.copyWith(affixes: affixes), displaced: displaced);
  }

  // --- Реролл ---------------------------------------------------------------

  /// Цена перекатать значение аффикса.
  ///
  /// Растёт от глубины предмета так же, как доход (`goldPerFloor` считается от
  /// того же [Curves.itemScale]). Поэтому реролл остаётся сопоставимым с
  /// заработком на любой глубине — это и есть бесконечный сток золота
  /// (GDD §6.3), а не запретительная цена.
  static double rerollCost(Item item, int affixIndex) {
    final roll = item.affixes[affixIndex];
    final rarity = Tuning.rerollRarityMultiplier[item.rarity] ?? 1.0;

    return Tuning.rerollCostBase *
        Curves.itemScale(item.ilvl) *
        rarity *
        _pow(Tuning.rerollCostGrowth, roll.rerolls);
  }

  /// Перекатывает перцентиль аффикса.
  ///
  /// Кузница поднимает НИЖНЮЮ границу: с её уровнем перекат перестаёт быть
  /// лотереей «а вдруг станет хуже» и превращается в постепенное улучшение.
  static Item reroll(
    Item item,
    int affixIndex,
    Rng rng, {
    double floorPercentile = 0.0,
  }) {
    final def = ContentPack.current.statAffix(
        item.affixes[affixIndex].affixId);
    if (def == null) return item;

    final old = item.affixes[affixIndex];
    final low = (Tuning.percentileMin + floorPercentile)
        .clamp(0.0, Tuning.percentileMax);
    final percentile = rng.nextRange(low, Tuning.percentileMax);

    final affixes = [...item.affixes];
    affixes[affixIndex] = _rollFrom(def, percentile, item.ilvl, old.tag)
        .copyWith(rerolls: old.rerolls + 1);

    return item.copyWith(affixes: affixes);
  }

  /// Каким аффикс МОЖЕТ стать после переката: худший и лучший исход.
  ///
  /// Перекат — лотерея, и точное значение до оплаты никто не покажет. Но
  /// границы показать обязаны: игрок платит за бросок, не зная даже, может ли
  /// стать хуже. Нижняя граница поднимается уровнем Кузницы — именно здесь и
  /// видно, за что игрок платил, улучшая её.
  ///
  /// `null`, если аффикса нет в контенте: тогда перекат ничего не изменит.
  static ({AffixRoll worst, AffixRoll best})? rerollRange(
    Item item,
    int affixIndex, {
    double floorPercentile = 0.0,
  }) {
    final old = item.affixes[affixIndex];
    final def = ContentPack.current.statAffix(old.affixId);
    if (def == null) return null;

    final low = (Tuning.percentileMin + floorPercentile)
        .clamp(0.0, Tuning.percentileMax);

    return (
      worst: _rollFrom(def, low, item.ilvl, old.tag),
      best: _rollFrom(def, Tuning.percentileMax, item.ilvl, old.tag),
    );
  }

  // --- Углубление реликта ---------------------------------------------------

  /// Можно ли углубить. Обычные предметы не углубляются намеренно: иначе
  /// исчезает смысл искать новые (GDD §5.4).
  static bool canDeepen(Item item, int maxDepthEver) =>
      item.isRelic && item.ilvl < maxDepthEver;

  static double deepenCost(Item item) {
    final target = item.ilvl + Tuning.deepenIlvlStep;
    return Tuning.deepenCostBase *
        Curves.itemScale(target) *
        _pow(Tuning.deepenCostGrowth, item.deepenings);
  }

  /// Поднимает уровень реликта, пересчитывая всё, что от уровня зависит.
  ///
  /// Уникальный эффект не стареет, а базовые статы стареют — углубление
  /// лечит именно это. Выше достигнутой глубины поднять нельзя: иначе реликт
  /// обгонял бы игрока.
  static Item deepen(Item item, int maxDepthEver) {
    if (!canDeepen(item, maxDepthEver)) return item;

    final target =
        (item.ilvl + Tuning.deepenIlvlStep).clamp(item.ilvl, maxDepthEver);
    final pack = ContentPack.current;

    final affixes = [
      for (final roll in item.affixes)
        (pack.statAffix(roll.affixId) == null)
            ? roll
            : _rollFrom(pack.statAffix(roll.affixId)!, roll.percentile, target,
                    roll.tag)
                .copyWith(rerolls: roll.rerolls),
    ];

    final implicitDef = pack.implicitFor(item.kind);
    final implicit = implicitDef == null
        ? item.implicit
        : AffixRoll(
            affixId: 'implicit.${item.kind.name}',
            stat: implicitDef.stat,
            percentile: 1.0,
            value: implicitDef.base *
                Curves.itemScale(target) *
                Tuning.itemPowerScale,
          );

    return item.copyWith(
      ilvl: target,
      affixes: affixes,
      implicit: implicit,
      deepenings: item.deepenings + 1,
    );
  }

  // --- Общее ----------------------------------------------------------------

  /// Пересчёт перцентиля в значение под конкретный уровень предмета.
  /// Ровно та же формула, что и при дропе, — иначе впечатанный аффикс
  /// отличался бы от выпавшего при одинаковом перцентиле.
  static AffixRoll _rollFrom(
      StatAffixDef def, double percentile, int ilvl, Tag? tag) {
    final scale = def.scales ? Curves.itemScale(ilvl) : 1.0;
    return AffixRoll(
      affixId: def.id,
      stat: def.stat,
      percentile: percentile,
      value: def.base * percentile * scale * Tuning.itemPowerScale,
      tag: def.stat == StatKey.tagDamage ? tag : null,
    );
  }

  static double _pow(double base, int exp) {
    var out = 1.0;
    for (var i = 0; i < exp; i++) {
      out *= base;
    }
    return out;
  }
}
