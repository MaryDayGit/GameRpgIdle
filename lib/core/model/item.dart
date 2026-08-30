import 'gear.dart';
import 'relic_effect.dart';
import 'stat_key.dart';
import 'stat_block.dart';
import 'tags.dart';

/// Один выпавший статовый аффикс.
///
/// Хранится и значение, и перцентиль. Значение нужно бою, перцентиль —
/// крафту: осколок несёт перцентиль, а не число, поэтому 96-й перцентиль
/// остаётся ценным на любой глубине (GDD §5.3).
class AffixRoll {
  const AffixRoll({
    required this.affixId,
    required this.stat,
    required this.percentile,
    required this.value,
    this.tag,
    this.rerolls = 0,
  });

  final String affixId;
  final StatKey stat;

  /// 0.70..1.00 по умолчанию.
  final double percentile;

  /// Уже посчитанное значение: `base × percentile × itemScale(ilvl)`
  /// для растущих статов и `base × percentile` для долевых.
  final double value;

  /// Для семейства `tagDamage` — по какому тегу выпал ролл.
  final Tag? tag;

  /// Сколько раз этот ролл перекатывали. Цена следующего реролла растёт от
  /// него, а при смене аффикса в слоте счётчик обнуляется — иначе реролл
  /// превращается в спам вместо двух-четырёх осмысленных попыток (GDD §6.3).
  final int rerolls;

  AffixRoll copyWith({double? percentile, double? value, int? rerolls}) =>
      AffixRoll(
        affixId: affixId,
        stat: stat,
        percentile: percentile ?? this.percentile,
        value: value ?? this.value,
        tag: tag,
        rerolls: rerolls ?? this.rerolls,
      );

  /// Вклад в [StatBlock]. Долевые множители максимума HP и брони сюда не
  /// попадают: они применяются к уже собранной сумме, иначе сложение блоков
  /// перестало бы быть ассоциативным.
  StatBlock toStatBlock() => switch (stat) {
        StatKey.maxHp => StatBlock(maxHp: value),
        StatKey.hpRegen => StatBlock(hpRegen: value),
        StatKey.maxMana => StatBlock(maxMana: value),
        StatKey.manaRegen => StatBlock(manaRegen: value),
        StatKey.armor => StatBlock(armor: value),
        StatKey.resistFire => StatBlock(resistFire: value),
        StatKey.resistCold => StatBlock(resistCold: value),
        StatKey.resistLightning => StatBlock(resistLightning: value),
        StatKey.resistVoid => StatBlock(resistVoid: value),
        StatKey.attackDamage => StatBlock(attackDamage: value),
        StatKey.spellPower => StatBlock(spellPower: value),
        StatKey.increasedDamage => StatBlock(increasedDamage: value),
        StatKey.increasedAttackSpeed => StatBlock(increasedAttackSpeed: value),
        StatKey.critChance => StatBlock(critChance: value),
        StatKey.critMulti => StatBlock(critMulti: value),
        StatKey.cooldownReduction => StatBlock(cooldownReduction: value),
        StatKey.leech => StatBlock(leech: value),
        StatKey.lootQuality => StatBlock(lootQuality: value),
        StatKey.lootQuantity => StatBlock(lootQuantity: value),
        StatKey.goldFind => StatBlock(goldFind: value),
        StatKey.tagDamage =>
          tag == null ? StatBlock.zero : StatBlock(tagDamage: {tag!: value}),
        StatKey.maxHpPct || StatKey.armorPct => StatBlock.zero,
      };

  @override
  String toString() =>
      'AffixRoll($affixId${tag != null ? ':${tag!.name}' : ''} '
      '${value.toStringAsFixed(3)} p${(percentile * 100).round()})';
}

/// Предмет.
///
/// Иммутабельный: крафт создаёт новый предмет, а не правит существующий.
/// Так у истории предмета нет скрытых состояний, а сейв не может застать
/// предмет на середине изменения.
class Item {
  Item({
    required this.kind,
    required this.ilvl,
    required this.rarity,
    required this.affixes,
    this.implicit,
    this.triggerAffixId,
    this.relicId,
    this.relicEffect,
    this.twoHanded = false,
    this.deepenings = 0,
    this.bonusAffixSlots = 0,
  })  : _stats = affixes.fold(
          implicit?.toStatBlock() ?? StatBlock.zero,
          (sum, a) => sum + a.toStatBlock(),
        ),
        maxHpPct = _sumOf(affixes, StatKey.maxHpPct),
        armorPct = _sumOf(affixes, StatKey.armorPct);

  final GearKind kind;
  final int ilvl;
  final Rarity rarity;
  final List<AffixRoll> affixes;

  /// Базовый стат типа предмета. Не роллится, не извлекается, не переписывается
  /// крафтом — именно он делает предмет большей глубины апгрейдом сам по себе.
  final AffixRoll? implicit;

  /// Триггерный аффикс, максимум один на предмет. Хранится id: параметры
  /// живут в контенте и не роллятся, поэтому копировать их в предмет незачем.
  final String? triggerAffixId;

  /// Уникальный эффект реликта. Не масштабируется от ilvl и не извлекается.
  final String? relicId;

  /// Правило, которое реликт меняет. Хранится на предмете, а не берётся из
  /// контента по id: снаряжение обязано уметь отвечать на вопрос «двуручник
  /// в одной руке разрешён?» без похода в загруженный контент.
  final RelicEffect? relicEffect;

  /// Занимает оба слота рук. Взамен несёт лишний аффикс и усиленные роллы.
  final bool twoHanded;

  /// Сколько раз реликт углубляли. Цена следующего углубления растёт от него.
  final int deepenings;

  /// Слоты аффиксов сверх положенных редкости — их открывают отмычки боссов
  /// и древо Эха (GDD §5.3).
  final int bonusAffixSlots;

  Item copyWith({
    int? ilvl,
    List<AffixRoll>? affixes,
    AffixRoll? implicit,
    int? deepenings,
    int? bonusAffixSlots,
  }) =>
      Item(
        kind: kind,
        ilvl: ilvl ?? this.ilvl,
        rarity: rarity,
        affixes: affixes ?? this.affixes,
        implicit: implicit ?? this.implicit,
        triggerAffixId: triggerAffixId,
        relicId: relicId,
        relicEffect: relicEffect,
        twoHanded: twoHanded,
        deepenings: deepenings ?? this.deepenings,
        bonusAffixSlots: bonusAffixSlots ?? this.bonusAffixSlots,
      );

  final StatBlock _stats;

  /// Долевые множители, применяемые к сумме, а не входящие в неё.
  final double maxHpPct;
  final double armorPct;

  StatBlock get stats => _stats;

  bool get isRelic => relicId != null;

  static double _sumOf(List<AffixRoll> affixes, StatKey stat) {
    var sum = 0.0;
    for (final a in affixes) {
      if (a.stat == stat) sum += a.value;
    }
    return sum;
  }

  /// Средний перцентиль роллов — «качество» предмета одним числом.
  /// Не сила: сила определяется ilvl, качество — тем, как повезло с роллами.
  double get quality {
    if (affixes.isEmpty) return 0.0;
    var sum = 0.0;
    for (final a in affixes) {
      sum += a.percentile;
    }
    return sum / affixes.length;
  }

  @override
  String toString() => 'Item(${kind.name}${twoHanded ? " 2H" : ""} '
      'ilvl$ilvl ${rarity.name}, '
      '${affixes.length} аффиксов${isRelic ? ", реликт $relicId" : ""})';
}
