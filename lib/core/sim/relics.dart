import '../content/content_pack.dart';
import '../model/equipment.dart';
import '../model/gear.dart';
import '../model/tags.dart';
import '../content/relic_def.dart';
import '../model/relic_effect.dart';

/// Свод правил, которые надетые реликты меняют в бою и в спуске.
///
/// Реликт меняет ПРАВИЛО, а не цифру (`docs/04-RELICS.md`), поэтому свести их
/// в набор статов нельзя — каждый требует своей ветки. Собираются они один раз
/// на смену снаряжения: спрашивать «а нет ли на мне Венца» в горячем цикле
/// боя означало бы ходить в контент по десять раз за тик.
class RelicRules {
  const RelicRules({
    this.burnCanCrit = false,
    this.burnMaxStacks = 1,
    this.directFirePenalty = 0.0,
    this.twoHandedInOneHand = false,
    this.maxHpPenalty = 0.0,
    this.singleActive = false,
    this.singleActiveCooldownReduction = 0.0,
    this.permanentLowLife = false,
    this.leechMultiplier = 1.0,
    this.counterRate = 1.0,
    this.critDisabled = false,
    this.waveReduction = 0,
    this.minRarity,
    this.goldEnabled = true,
    this.eternalCurse = false,
    this.uncursedPenalty = 0.0,
    this.passivesOnly = false,
    this.passivesPerSlot = 1,
    this.alwaysCrit = false,
    this.firstStrikeMultiplier = 1.0,
    this.afterFirstPenalty = 0.0,
    this.executeThreshold = 0.0,
    this.armorDisabled = false,
    this.bonusResistAll = 0.0,
    this.damageBonus = 0.0,
    this.painPerHit = 0.0,
    this.painMaxStacks = 0,
    this.healOnlyByLeech = false,
    this.freeCasts = false,
    this.cooldownMultiplier = 1.0,
    this.manaCostMultiplier = 1.0,
    this.conduitType,
    this.conduitBonus = 0.0,
    this.conduitResistPenalty = 0.0,
    this.restDisabled = false,
    this.bossRewardMultiplier = 1.0,
    this.mobHpBonus = 0.0,
    this.startDepthBonus = 0,
    this.twinRings = false,
  });

  static const RelicRules none = RelicRules();

  /// «Пепельный завет»: горение критует и копится до [burnMaxStacks] стаков,
  /// но прямой урон Огнём срезан.
  final bool burnCanCrit;
  final int burnMaxStacks;
  final double directFirePenalty;

  /// «Расколотый противовес»: двуручник можно носить в одной руке.
  final bool twoHandedInOneHand;

  /// Суммарный штраф к максимуму HP — его дают сразу два реликта.
  final double maxHpPenalty;

  /// «Венец одержимого»: одна активка, зато дешёвая и по всей волне.
  final bool singleActive;
  final double singleActiveCooldownReduction;

  /// «Кожа отчаяния»: эффекты «ниже X % HP» активны всегда.
  final bool permanentLowLife;
  final double leechMultiplier;

  /// «Счётчик мгновений»: эффекты со счётчиком идут вдвое чаще, критов нет.
  final double counterRate;
  final bool critDisabled;

  /// «Сапоги нисходящего»: волн меньше, но мелочь не подбирается.
  final int waveReduction;
  final Rarity? minRarity;
  final bool goldEnabled;

  /// «Печать тысячи глаз»: проклятия вечны, урон по непроклятым срезан.
  final bool eternalCurse;
  final double uncursedPenalty;

  /// «Оберег молчания»: только пассивки, зато по две в слот.
  final bool passivesOnly;

  /// Сколько ПАССИВНЫХ умений вмещает один слот. Больше единицы — награда
  /// «Оберега молчания» за то, что активные умения он отнимает целиком.
  final int passivesPerSlot;

  /// «Маска неизбежности»: каждый удар критический, базовый урон срезан.
  final bool alwaysCrit;

  /// «Перчатка первой крови»: первый удар по волне усилен, прочие ослаблены.
  final double firstStrikeMultiplier;
  final double afterFirstPenalty;

  /// «Жатва»: враг ниже этой доли здоровья гибнет мгновенно.
  final double executeThreshold;

  /// «Шкура призм»: броня не работает, зато сопротивления выше.
  final bool armorDisabled;
  final double bonusResistAll;

  /// «Стеклянный венец»: обе оси урона выше, здоровья меньше.
  final double damageBonus;

  /// «Клятый договор»: каждый полученный удар копит урон до конца волны.
  final double painPerHit;
  final int painMaxStacks;

  /// «Кровавый обет»: лечит только вампиризм.
  final bool healOnlyByLeech;

  /// «Бесконечная кадильница»: касты бесплатны, перезарядка дольше.
  final bool freeCasts;

  /// Множители перезарядки и цены маны от реликтов.
  final double cooldownMultiplier;
  final double manaCostMultiplier;

  /// «Проводник стихии»: весь урон героя становится этой стихией.
  final DamageType? conduitType;
  final double conduitBonus;
  final double conduitResistPenalty;

  /// «Неутомимые сапоги»: отдыха между этажами нет.
  final bool restDisabled;

  /// «Рог охоты»: боссы щедрее, обычные враги крепче.
  final double bossRewardMultiplier;
  final double mobHpBonus;

  /// «Канат глубин»: спуск начинается глубже.
  final int startDepthBonus;

  /// «Парные кольца»: кольца дают вдвое, амулет не работает.
  final bool twinRings;

  bool get isEmpty =>
      !burnCanCrit &&
      !twoHandedInOneHand &&
      maxHpPenalty == 0.0 &&
      !singleActive &&
      !permanentLowLife &&
      counterRate == 1.0 &&
      !critDisabled &&
      waveReduction == 0 &&
      minRarity == null &&
      goldEnabled &&
      !eternalCurse &&
      !passivesOnly;

  /// Определение реликта по id. Отдельным методом, чтобы снаряжению не
  /// приходилось знать про устройство контента ради одной проверки.
  static RelicDef? definitionOf(String relicId) =>
      ContentPack.isLoaded ? ContentPack.current.relic(relicId) : null;

  /// Собирает правила по надетому. Реликт в заблокированном слоте не считается:
  /// вещь, которая не работает, не должна менять правила.
  static RelicRules from(Equipment gear) {
    final pack = ContentPack.current;

    var burnCanCrit = false;
    var burnMaxStacks = 1;
    var directFirePenalty = 0.0;
    var twoHandedInOneHand = false;
    var maxHpPenalty = 0.0;
    var singleActive = false;
    var singleActiveCdr = 0.0;
    var permanentLowLife = false;
    var leechMultiplier = 1.0;
    var counterRate = 1.0;
    var critDisabled = false;
    var waveReduction = 0;
    Rarity? minRarity;
    var goldEnabled = true;
    var eternalCurse = false;
    var uncursedPenalty = 0.0;
    var passivesOnly = false;
    var passivesPerSlot = 1;

    var alwaysCrit = false;
    var firstStrikeMultiplier = 1.0;
    var afterFirstPenalty = 0.0;
    var executeThreshold = 0.0;
    var armorDisabled = false;
    var bonusResistAll = 0.0;
    var damageBonus = 0.0;
    var painPerHit = 0.0;
    var painMaxStacks = 0;
    var healOnlyByLeech = false;
    var freeCasts = false;
    var cooldownMultiplier = 1.0;
    var manaCostMultiplier = 1.0;
    DamageType? conduitType;
    var conduitBonus = 0.0;
    var conduitResistPenalty = 0.0;
    var restDisabled = false;
    var bossRewardMultiplier = 1.0;
    var mobHpBonus = 0.0;
    var startDepthBonus = 0;
    var twinRings = false;

    final offhandOk = gear.offhandUsable;
    final slots = gear.slots;

    for (var i = 0; i < slots.length; i++) {
      final item = slots[i];
      if (item == null || item.relicId == null) continue;
      if (i == 1 && !offhandOk) continue;

      final def = pack.relic(item.relicId!);
      if (def == null) continue;
      final p = def.params;

      switch (def.effect) {
        case RelicEffect.burnCanCrit:
          burnCanCrit = true;
          burnMaxStacks = p.integer('maxStacks', 1);
          directFirePenalty += p.dbl('directFirePenalty');
        case RelicEffect.twoHandedInOneHand:
          twoHandedInOneHand = true;
          maxHpPenalty += p.dbl('maxHpPenalty');
        case RelicEffect.singleActive:
          singleActive = true;
          singleActiveCdr += p.dbl('cooldownReduction');
        case RelicEffect.permanentLowLife:
          permanentLowLife = true;
          maxHpPenalty += p.dbl('maxHpPenalty');
          leechMultiplier *= p.dbl('leechMultiplier', 1.0);
        case RelicEffect.doubleCounters:
          counterRate *= p.dbl('rate', 1.0);
          critDisabled = true;
        case RelicEffect.recordRun:
          waveReduction += p.integer('waveReduction');
          goldEnabled = goldEnabled && p.flag('goldEnabled', true);
          final name = p.str('minRarity');
          for (final rarity in Rarity.values) {
            if (rarity.name == name) minRarity = rarity;
          }
        case RelicEffect.eternalCurse:
          eternalCurse = true;
          uncursedPenalty += p.dbl('uncursedPenalty');
        case RelicEffect.alwaysCrit:
          alwaysCrit = true;
          damageBonus -= p.dbl('damagePenalty');
        case RelicEffect.firstStrike:
          firstStrikeMultiplier = p.dbl('multiplier', 1.0);
          afterFirstPenalty += p.dbl('penalty');
        case RelicEffect.executeLow:
          executeThreshold = p.dbl('threshold');
          damageBonus -= p.dbl('damagePenalty');
        case RelicEffect.armorIntoResist:
          armorDisabled = true;
          bonusResistAll += p.dbl('resistAll');
        case RelicEffect.fragilePower:
          damageBonus += p.dbl('damageBonus');
          maxHpPenalty += p.dbl('maxHpPenalty');
        case RelicEffect.painToPower:
          painPerHit = p.dbl('perHit');
          painMaxStacks = p.integer('maxStacks', 0);
        case RelicEffect.bloodPact:
          healOnlyByLeech = true;
          leechMultiplier *= p.dbl('leechMultiplier', 1.0);
        case RelicEffect.freeCasts:
          freeCasts = true;
          cooldownMultiplier *= p.dbl('cooldownMultiplier', 1.0);
        case RelicEffect.swiftCasts:
          cooldownMultiplier *= p.dbl('cooldownMultiplier', 1.0);
          manaCostMultiplier *= p.dbl('manaCostMultiplier', 1.0);
        case RelicEffect.elementalConduit:
          conduitType = DamageType.values.firstWhere(
            (t) => t.name == p.str('element'),
            orElse: () => DamageType.fire,
          );
          conduitBonus += p.dbl('damageBonus');
          conduitResistPenalty += p.dbl('resistPenalty');
        case RelicEffect.restless:
          restDisabled = true;
          waveReduction += p.integer('waveReduction', 0);
        case RelicEffect.bossbane:
          bossRewardMultiplier *= p.dbl('bossReward', 1.0);
          mobHpBonus += p.dbl('mobHp');
        case RelicEffect.deepStart:
          startDepthBonus += p.integer('floors', 0);
          maxHpPenalty += p.dbl('maxHpPenalty');
        case RelicEffect.twinRings:
          twinRings = true;
        case RelicEffect.passivesOnly:
          passivesOnly = true;
          passivesPerSlot = p.integer('passivesPerSlot', 1);
      }
    }

    return RelicRules(
      burnCanCrit: burnCanCrit,
      burnMaxStacks: burnMaxStacks,
      directFirePenalty: directFirePenalty.clamp(0.0, 0.95),
      twoHandedInOneHand: twoHandedInOneHand,
      maxHpPenalty: maxHpPenalty.clamp(0.0, 0.95),
      singleActive: singleActive,
      singleActiveCooldownReduction: singleActiveCdr.clamp(0.0, 0.9),
      permanentLowLife: permanentLowLife,
      leechMultiplier: leechMultiplier,
      counterRate: counterRate,
      critDisabled: critDisabled,
      waveReduction: waveReduction,
      minRarity: minRarity,
      goldEnabled: goldEnabled,
      eternalCurse: eternalCurse,
      uncursedPenalty: uncursedPenalty.clamp(0.0, 0.95),
      passivesOnly: passivesOnly,
      passivesPerSlot: passivesPerSlot,
      alwaysCrit: alwaysCrit,
      firstStrikeMultiplier: firstStrikeMultiplier,
      afterFirstPenalty: afterFirstPenalty.clamp(0.0, 0.95),
      executeThreshold: executeThreshold.clamp(0.0, 0.5),
      armorDisabled: armorDisabled,
      bonusResistAll: bonusResistAll,
      damageBonus: damageBonus,
      painPerHit: painPerHit,
      painMaxStacks: painMaxStacks,
      healOnlyByLeech: healOnlyByLeech,
      freeCasts: freeCasts,
      cooldownMultiplier: cooldownMultiplier,
      manaCostMultiplier: manaCostMultiplier,
      conduitType: conduitType,
      conduitBonus: conduitBonus,
      conduitResistPenalty: conduitResistPenalty,
      restDisabled: restDisabled,
      bossRewardMultiplier: bossRewardMultiplier,
      mobHpBonus: mobHpBonus,
      startDepthBonus: startDepthBonus,
      twinRings: twinRings,
    );
  }
}
