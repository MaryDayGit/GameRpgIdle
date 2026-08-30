import 'tags.dart';

/// Агрегированные статы (GDD §3.2).
///
/// Иммутабельный, складывается оператором `+`. Экипировка, пассивки, древо Эха
/// и модификатор этажа сворачиваются в один блок, который пересчитывается по
/// флагу dirty — не каждый тик.
///
/// Здесь живут только аддитивные величины (корзина `increased`).
/// Мультипликативная корзина (`more`) ситуативна — её место в бою, не здесь.
class StatBlock {
  const StatBlock({
    this.maxHp = 0.0,
    this.hpRegen = 0.0,
    this.maxMana = 0.0,
    this.manaRegen = 0.0,
    this.armor = 0.0,
    this.resistFire = 0.0,
    this.resistCold = 0.0,
    this.resistLightning = 0.0,
    this.resistVoid = 0.0,
    this.attackDamage = 0.0,
    this.spellPower = 0.0,
    this.increasedDamage = 0.0,
    this.attackSpeed = 0.0,
    this.increasedAttackSpeed = 0.0,
    this.critChance = 0.0,
    this.critMulti = 0.0,
    this.cooldownReduction = 0.0,
    this.leech = 0.0,
    this.lootQuality = 0.0,
    this.lootQuantity = 0.0,
    this.goldFind = 0.0,
    this.tagDamage = const {},
  });

  static const StatBlock zero = StatBlock();

  final double maxHp;
  final double hpRegen;

  /// Запас маны и её восстановление в секунду.
  ///
  /// Мана — общий бюджет на ВСЕ активные способности, в отличие от кулдауна,
  /// который считается каждой способности отдельно. Кулдаун отвечает на
  /// вопрос «как часто», мана — на вопрос «сколько их сразу»: три дорогих
  /// активки в сборке пересыхают, если не вложиться в запас и регенерацию.
  final double maxMana;
  final double manaRegen;
  final double armor;
  final double resistFire;
  final double resistCold;
  final double resistLightning;
  final double resistVoid;

  /// Плоский урон атаки. От него растут автоатака и способности с тегом
  /// «Атака».
  final double attackDamage;

  /// Плоская сила чар. От неё растут способности с тегом «Чары».
  ///
  /// Вторая ось намеренно отдельная и намеренно не сложена с уроном оружия:
  /// пока обе росли из одного стата, выбор способности не влиял на то, какое
  /// снаряжение игроку нужно, и «собрать билд» было не из чего.
  final double spellPower;

  /// Доля: 0.35 = +35 %. Аддитивная корзина.
  final double increasedDamage;

  /// Ударов в секунду, плоско.
  final double attackSpeed;

  /// Доля: 0.20 = +20 % скорости атаки. Аддитивная корзина.
  final double increasedAttackSpeed;

  /// Доля: 0.05 = 5 %.
  final double critChance;

  /// Доля сверх единицы: 0.5 = ×1.5 урона на крите.
  final double critMulti;

  /// Доля: 0.15 = −15 % кулдаунов.
  final double cooldownReduction;

  /// Доля нанесённого урона, возвращаемая в HP.
  final double leech;

  final double lootQuality;
  final double lootQuantity;
  final double goldFind;

  /// «+X % урона с тегом Y» — то самое семейство из 8 роллов,
  /// ради которого существует система тегов.
  final Map<Tag, double> tagDamage;

  StatBlock operator +(StatBlock o) {
    Map<Tag, double> mergedTags;
    if (tagDamage.isEmpty) {
      mergedTags = o.tagDamage;
    } else if (o.tagDamage.isEmpty) {
      mergedTags = tagDamage;
    } else {
      mergedTags = {...tagDamage};
      o.tagDamage.forEach((tag, v) {
        mergedTags[tag] = (mergedTags[tag] ?? 0.0) + v;
      });
    }
    return StatBlock(
      maxHp: maxHp + o.maxHp,
      hpRegen: hpRegen + o.hpRegen,
      maxMana: maxMana + o.maxMana,
      manaRegen: manaRegen + o.manaRegen,
      armor: armor + o.armor,
      resistFire: resistFire + o.resistFire,
      resistCold: resistCold + o.resistCold,
      resistLightning: resistLightning + o.resistLightning,
      resistVoid: resistVoid + o.resistVoid,
      attackDamage: attackDamage + o.attackDamage,
      spellPower: spellPower + o.spellPower,
      increasedDamage: increasedDamage + o.increasedDamage,
      attackSpeed: attackSpeed + o.attackSpeed,
      increasedAttackSpeed: increasedAttackSpeed + o.increasedAttackSpeed,
      critChance: critChance + o.critChance,
      critMulti: critMulti + o.critMulti,
      cooldownReduction: cooldownReduction + o.cooldownReduction,
      leech: leech + o.leech,
      lootQuality: lootQuality + o.lootQuality,
      lootQuantity: lootQuantity + o.lootQuantity,
      goldFind: goldFind + o.goldFind,
      tagDamage: mergedTags,
    );
  }

  /// Масштабирование всех «размерных» статов — используется синтетической
  /// моделью снаряжения Фазы 1 и множителем статов мобов от Клейма.
  StatBlock scaled(double k) => StatBlock(
        maxHp: maxHp * k,
        hpRegen: hpRegen * k,
        // Мана — плоский бюджет: цены способностей от глубины не зависят,
        // аффиксы на ману не растут от ilvl, и синтетическая модель силы
        // билда обязана вести себя так же. Иначе замер стены показывал бы
        // рост, которого у настоящего снаряжения нет.
        maxMana: maxMana,
        manaRegen: manaRegen,
        armor: armor * k,
        resistFire: resistFire,
        resistCold: resistCold,
        resistLightning: resistLightning,
        resistVoid: resistVoid,
        attackDamage: attackDamage * k,
        spellPower: spellPower * k,
        increasedDamage: increasedDamage,
        attackSpeed: attackSpeed,
        increasedAttackSpeed: increasedAttackSpeed,
        critChance: critChance,
        critMulti: critMulti,
        cooldownReduction: cooldownReduction,
        leech: leech,
        lootQuality: lootQuality,
        lootQuantity: lootQuantity,
        goldFind: goldFind,
        tagDamage: tagDamage,
      );

  /// Применяет долевые множители максимума HP и брони.
  ///
  /// Отдельным шагом, а не полями блока: `maxHpPct` умножает СОБРАННУЮ сумму,
  /// и если бы он лежал в блоке, сложение перестало бы быть ассоциативным —
  /// `(A + B) + C` дало бы не то же, что `A + (B + C)`.
  StatBlock withFractions({double maxHpPct = 0.0, double armorPct = 0.0}) =>
      StatBlock(
        maxHp: maxHp * (1.0 + maxHpPct),
        hpRegen: hpRegen,
        maxMana: maxMana,
        manaRegen: manaRegen,
        armor: armor * (1.0 + armorPct),
        resistFire: resistFire,
        resistCold: resistCold,
        resistLightning: resistLightning,
        resistVoid: resistVoid,
        attackDamage: attackDamage,
        spellPower: spellPower,
        increasedDamage: increasedDamage,
        attackSpeed: attackSpeed,
        increasedAttackSpeed: increasedAttackSpeed,
        critChance: critChance,
        critMulti: critMulti,
        cooldownReduction: cooldownReduction,
        leech: leech,
        lootQuality: lootQuality,
        lootQuantity: lootQuantity,
        goldFind: goldFind,
        tagDamage: tagDamage,
      );

  double resistFor(DamageType type) => switch (type) {
        DamageType.physical => 0.0,
        DamageType.fire => resistFire,
        DamageType.cold => resistCold,
        DamageType.lightning => resistLightning,
        DamageType.voidType => resistVoid,
      };

  /// Итоговая скорость атаки, ударов в секунду.
  double get effectiveAttackSpeed => attackSpeed * (1.0 + increasedAttackSpeed);

  @override
  String toString() => 'StatBlock(hp: ${maxHp.toStringAsFixed(0)}, '
      'dmg: ${attackDamage.toStringAsFixed(1)}, '
      'as: ${effectiveAttackSpeed.toStringAsFixed(2)}, '
      'armor: ${armor.toStringAsFixed(0)}, '
      'crit: ${(critChance * 100).toStringAsFixed(1)}%)';
}
