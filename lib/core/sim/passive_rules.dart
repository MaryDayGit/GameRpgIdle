import '../content/passive_tree_def.dart';
import '../model/passive_tree.dart';

/// Боевые правила от дерева пассивок.
///
/// Отдельно от [RelicRules] намеренно: источники разные — реликт лежит в
/// снаряжении и теряется вместе с ним, дерево принадлежит игроку и переживает
/// любое число наёмников. Сложить их в один объект значило бы потерять ответ
/// на вопрос «откуда это правило взялось», а он нужен и игроку, и замеру.
///
/// Сюда попадают только те правила, которые зависят от происходящего в бою.
/// Пересчёты статов (мана в урон, броня в сопротивление) живут в сборке
/// билда — их место в [PassiveTree.applyTo], а не в тике.
class PassiveRules {
  const PassiveRules({
    this.killHeal = 0.0,
    this.lowLifeMoreDamage = 0.0,
    this.critVsSlowed = false,
    this.critHeal = 0.0,
    this.firstStrike = 0.0,
    this.dotMoreDamage = 0.0,
    this.chillOnHit = 0.0,
    this.shockSplash = 0.0,
    this.curseMoreDamage = 0.0,
  });

  static const PassiveRules none = PassiveRules();

  /// Доля максимума HP, возвращаемая за убийство.
  final double killHeal;

  /// Множитель урона, пока здоровье ниже половины.
  final double lowLifeMoreDamage;

  /// По замедленным крит всегда.
  final bool critVsSlowed;

  /// Доля максимума HP, возвращаемая критическим ударом.
  final double critHeal;

  /// Насколько усилен первый удар по новой волне.
  final double firstStrike;

  /// Множитель длительного урона.
  final double dotMoreDamage;

  /// На сколько удар замедляет цель. Ноль — не замедляет.
  final double chillOnHit;

  /// Доля урона Молнией, которая задевает вторую цель.
  final double shockSplash;

  /// Множитель урона по проклятым.
  final double curseMoreDamage;

  /// Собирает правила из взятых узлов.
  ///
  /// Единственное место сборки: два таких места разошлись бы, и правило,
  /// видимое на экране, не совпало бы с тем, что происходит в бою.
  factory PassiveRules.from(PassiveTree? tree) {
    if (tree == null) return none;

    return PassiveRules(
      killHeal: tree.ruleValue(PassiveRule.killHeal),
      lowLifeMoreDamage: tree.ruleValue(PassiveRule.lowLifeDamage),
      critVsSlowed: tree.ruleValue(PassiveRule.critVsSlowed) > 0.0,
      critHeal: tree.ruleValue(PassiveRule.critHeal),
      firstStrike: tree.ruleValue(PassiveRule.firstStrike),
      dotMoreDamage: tree.ruleValue(PassiveRule.dotMoreDamage),
      chillOnHit: tree.ruleValue(PassiveRule.chillOnHit),
      shockSplash: tree.ruleValue(PassiveRule.shockSplash),
      curseMoreDamage: tree.ruleValue(PassiveRule.curseMoreDamage),
    );
  }

  bool get isEmpty =>
      killHeal == 0.0 &&
      lowLifeMoreDamage == 0.0 &&
      !critVsSlowed &&
      critHeal == 0.0 &&
      firstStrike == 0.0 &&
      dotMoreDamage == 0.0 &&
      chillOnHit == 0.0 &&
      shockSplash == 0.0 &&
      curseMoreDamage == 0.0;
}
