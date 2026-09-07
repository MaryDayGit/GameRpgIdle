import 'lang.dart';

/// Имя стата, на который ссылается контент.
///
/// Шире, чем поля [StatBlock]: `maxHpPct` и `armorPct` — это множители,
/// применяемые к уже собранной сумме, а не слагаемые. Их нельзя держать в
/// [StatBlock] полями, иначе сложение блоков перестанет быть ассоциативным:
/// `(A + B) + C` с процентами внутри даёт не то же, что `A + (B + C)`.
enum StatKey {
  maxHp(Phrase('к максимуму HP', 'maximum HP')),
  maxHpPct(Phrase('% к максимуму HP', '% maximum HP')),
  hpRegen(Phrase('восстановления HP в секунду', 'HP regeneration per second')),
  maxMana(Phrase('к максимуму маны', 'maximum mana')),
  manaRegen(
      Phrase('восстановления маны в секунду', 'mana regeneration per second')),
  armor(Phrase('к броне', 'armor')),
  armorPct(Phrase('% к броне', '% armor')),
  resistFire(Phrase('к сопротивлению огню', 'fire resistance')),
  resistCold(Phrase('к сопротивлению холоду', 'cold resistance')),
  resistLightning(Phrase('к сопротивлению молнии', 'lightning resistance')),
  resistVoid(Phrase('к сопротивлению пустоте', 'void resistance')),
  attackDamage(Phrase('к урону атаки', 'attack damage')),

  /// Вторая ось силы: от неё растут способности с тегом `Чары`.
  ///
  /// Существует ради того, чтобы выбор способности менял то, какое
  /// снаряжение игроку нужно. Пока всё росло от урона оружия, любая вещь
  /// одинаково годилась любой сборке — и «подобрать снаряжение под умения»
  /// было нечем.
  spellPower(Phrase('к силе чар', 'spell power')),
  increasedDamage(Phrase('% к урону', '% increased damage')),
  increasedAttackSpeed(
      Phrase('% к скорости атаки', '% increased attack speed')),
  critChance(
      Phrase('% к шансу критического удара', '% critical strike chance')),
  critMulti(
      Phrase('% к множителю критического удара', '% critical strike multiplier')),
  cooldownReduction(
      Phrase('% к перезарядке способностей', '% cooldown reduction')),
  leech(Phrase('% вампиризма', '% life leech')),
  lootQuality(Phrase('% к качеству добычи', '% loot quality')),
  lootQuantity(Phrase('% к количеству добычи', '% loot quantity')),
  goldFind(Phrase('% к находимому золоту', '% gold found')),

  /// Особый случай: значение кладётся не в поле, а в карту `tagDamage`
  /// по тегу из `family`. Ради этого семейства существует система тегов.
  tagDamage(Phrase('% к урону с тегом', '% damage with tag'));

  const StatKey(this._label);

  final Phrase _label;

  /// Как стат читается ПОСЛЕ числа: «+30 к максимуму HP», «+30 maximum HP».
  ///
  /// Не название, а хвост строки, и потому со строчной буквы: число впереди
  /// ставит не код, а тот, кто собирает строку, — [ItemText] или шаблон
  /// аффикса. Ведущий «%» в процентных статах — часть хвоста: он прилипает
  /// к числу, и пробел перед ним расставляет [TextTemplate] по правилам
  /// языка, а не эта строка.
  String get label => _label.text;

  /// Мана — плоский бюджет.
  ///
  /// Цены способностей заданы числами и от глубины не зависят, поэтому и
  /// запас с регенерацией обязаны быть плоскими: растущая от ilvl мана к
  /// сотому этажу перестала бы что-либо ограничивать, а вместе с ней
  /// обесценился бы и выбор «сколько активок унести вниз».
  bool get isManaBudget =>
      this == StatKey.maxMana || this == StatKey.manaRegen;

  /// Процентные статы не растут от ilvl (`scales: false` в контенте).
  /// Проверка нужна валидатору: процент, растущий экспоненциально, вводит
  /// силу билда в квадрате и ломает формулу стены (GDD §2.3).
  bool get isFraction => switch (this) {
        StatKey.maxHp ||
        StatKey.hpRegen ||
        StatKey.maxMana ||
        StatKey.manaRegen ||
        StatKey.armor ||
        StatKey.attackDamage ||
        StatKey.spellPower ||
        StatKey.resistFire ||
        StatKey.resistCold ||
        StatKey.resistLightning ||
        StatKey.resistVoid =>
          false,
        _ => true,
      };
}
