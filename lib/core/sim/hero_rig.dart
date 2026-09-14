import '../model/hero.dart';
import 'abilities.dart';
import 'events.dart';
import 'passive_rules.dart';
import 'relics.dart';
import 'triggers.dart';

/// Боевой рантайм героя, собранный из профиля: состояние, способности,
/// триггеры, правила реликтов и дерева пассивок.
///
/// Собирается в ОДНОМ месте, потому что героя в бой выводят двое — спуск и
/// логово стража. Две сборки одного и того же расходятся молча (раунды 16,
/// 22, 24): страж, которого бьют без «Порога» древа или без триггеров
/// снаряжения, — это бой с другим героем, чем тот, что уходит в бездну.
class HeroRig {
  HeroRig._({
    required this.hero,
    required this.mods,
    required this.rules,
    required this.abilities,
    required this.triggers,
    required this.passives,
  });

  factory HeroRig.of(HeroProfile profile, EventBus bus) {
    final mods = CombatModifiers()
      ..deathThreshold = profile.tree?.hasDeathThreshold ?? false;
    final rules = profile.relicRules;
    final abilities =
        AbilityRuntime(profile.loadout, modifiers: mods, rules: rules);
    final triggers = TriggerRuntime(bus: bus, abilities: abilities, mods: mods)
      ..rules = rules
      ..configure(profile.gear.triggerIds);

    return HeroRig._(
      hero: HeroState(profile.aggregate()),
      mods: mods,
      rules: rules,
      abilities: abilities,
      triggers: triggers,
      passives: PassiveRules.from(profile.passives),
    );
  }

  final HeroState hero;
  final CombatModifiers mods;
  final RelicRules rules;
  final AbilityRuntime abilities;
  final TriggerRuntime triggers;
  final PassiveRules passives;
}
