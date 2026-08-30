import '../model/gear.dart';
import '../model/relic_effect.dart';
import 'json_node.dart';
import 'params.dart';

const Map<RelicEffect, List<ParamSpec>> relicParamSpecs = {
  RelicEffect.burnCanCrit: [
    ParamSpec.integer('maxStacks'),
    ParamSpec.number('directFirePenalty'),
  ],
  RelicEffect.twoHandedInOneHand: [
    ParamSpec.number('maxHpPenalty'),
  ],
  RelicEffect.singleActive: [
    ParamSpec.number('cooldownReduction'),
  ],
  RelicEffect.permanentLowLife: [
    ParamSpec.number('maxHpPenalty'),
    ParamSpec.number('leechMultiplier'),
  ],
  RelicEffect.doubleCounters: [
    ParamSpec.number('rate'),
  ],
  RelicEffect.recordRun: [
    ParamSpec.integer('waveReduction'),
    ParamSpec.text('minRarity'),
    ParamSpec.boolean('goldEnabled'),
  ],
  RelicEffect.eternalCurse: [
    ParamSpec.number('uncursedPenalty'),
  ],
  RelicEffect.passivesOnly: [
    ParamSpec.integer('passivesPerSlot'),
  ],

  // --- Бой ---------------------------------------------------------------------
  RelicEffect.alwaysCrit: [
    ParamSpec.number('damagePenalty'),
  ],
  RelicEffect.firstStrike: [
    ParamSpec.number('multiplier'),
    ParamSpec.number('penalty'),
  ],
  RelicEffect.executeLow: [
    ParamSpec.number('threshold'),
    ParamSpec.number('damagePenalty'),
  ],
  RelicEffect.armorIntoResist: [
    ParamSpec.number('resistAll'),
  ],
  RelicEffect.fragilePower: [
    ParamSpec.number('damageBonus'),
    ParamSpec.number('maxHpPenalty'),
  ],
  RelicEffect.painToPower: [
    ParamSpec.number('perHit'),
    ParamSpec.integer('maxStacks'),
  ],
  RelicEffect.bloodPact: [
    ParamSpec.number('leechMultiplier'),
  ],

  // --- Способности ---------------------------------------------------------------
  RelicEffect.freeCasts: [
    ParamSpec.number('cooldownMultiplier'),
  ],
  RelicEffect.swiftCasts: [
    ParamSpec.number('cooldownMultiplier'),
    ParamSpec.number('manaCostMultiplier'),
  ],
  RelicEffect.elementalConduit: [
    ParamSpec.text('element'),
    ParamSpec.number('damageBonus'),
    ParamSpec.number('resistPenalty'),
  ],

  // --- Спуск ---------------------------------------------------------------------
  RelicEffect.restless: [
    ParamSpec.integer('waveReduction'),
  ],
  RelicEffect.bossbane: [
    ParamSpec.number('bossReward'),
    ParamSpec.number('mobHp'),
  ],
  RelicEffect.deepStart: [
    ParamSpec.integer('floors'),
    ParamSpec.number('maxHpPenalty'),
  ],
  // Правило без чисел: кольца вдвое, амулет никак. Настраивать здесь нечего.
  RelicEffect.twinRings: [],
};

class RelicDef {
  const RelicDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.text,
    required this.effect,
    required this.params,
    required this.exclusiveWith,
  });

  final String id;
  final String name;

  /// Тип предмета, на котором реликт может выпасть. По одному на тип.
  final GearKind kind;

  final String text;
  final RelicEffect effect;
  final Params params;

  /// Жёсткие пары: «одна активка» и «ноль активок» не могут работать вместе.
  /// Проверка ссылок — в [ContentPack], здесь только чтение.
  final List<String> exclusiveWith;

  static const _keys = {
    'id', 'ru', 'kind', 'text', 'effect', 'params', 'exclusiveWith',
  };

  static RelicDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final effect = node.enumByName('effect', RelicEffect.values,
        or: RelicEffect.burnCanCrit)!;
    final params = readParams(node, relicParamSpecs[effect] ?? const []);

    if (effect == RelicEffect.recordRun && params.has('minRarity')) {
      final name = params.str('minRarity');
      if (!Rarity.values.any((r) => r.name == name)) {
        node.issues.add('${node.path}.params.minRarity',
            'неизвестная редкость «$name»');
      }
    }

    return RelicDef(
      id: node.str('id'),
      name: node.str('ru'),
      kind: node.enumByName('kind', GearKind.values, or: GearKind.weapon)!,
      text: node.str('text'),
      effect: effect,
      params: params,
      exclusiveWith: node.strList('exclusiveWith'),
    );
  }

  @override
  String toString() => 'RelicDef($id, ${effect.name})';
}
