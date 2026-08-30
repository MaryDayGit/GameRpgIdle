import '../model/gear.dart';
import '../model/stat_key.dart';
import '../model/tags.dart';
import '../sim/events.dart';
import 'json_node.dart';
import 'params.dart';
import 'text_template.dart';

/// Статовый аффикс: «+X к чему-то». 18 записей дают 25 различимых роллов —
/// `damage_tag` это семейство из восьми, по одному на тег.
class StatAffixDef {
  const StatAffixDef({
    required this.id,
    required this.template,
    required this.stat,
    required this.base,
    required this.scales,
    required this.kinds,
    required this.weight,
    required this.family,
  });

  final String id;

  /// Шаблон описания: `{value}`, `{value:%}`, `{tag}` — см. [TextTemplate].
  final String template;

  final StatKey stat;

  /// Значение на ilvl 1 при перцентиле 1.0.
  final double base;

  /// Растёт ли значение как `itemScale(ilvl)`.
  final bool scales;

  /// На каких типах предметов может выпасть.
  final List<GearKind> kinds;

  final double weight;

  /// Для `tagDamage` — по какому тегу может выпасть ролл. Пусто у остальных.
  final List<Tag> family;

  static const _keys = {
    'id', 'ru', 'stat', 'base', 'scales', 'kinds', 'weight', 'family',
  };

  static StatAffixDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final stat = node.enumByName('stat', StatKey.values, or: StatKey.maxHp)!;
    final scales = node.flag('scales');
    final kinds = node.enumList('kinds', GearKind.values);
    final family = node.enumList('family', Tag.values);
    final weight = node.dbl('weight');

    // Процент, растущий экспоненциально от ilvl, вводит силу билда в квадрате:
    // формула стены (GDD §2.3) перестаёт сходиться, и кривая сложности
    // разъезжается тем сильнее, чем глубже спуск.
    if (scales && stat.isFraction) {
      node.issues.add('${node.path}.scales',
          'долевой стат ${stat.name} не может расти от ilvl');
    }
    // Цены способностей плоские — значит, и бюджет маны плоский.
    if (scales && stat.isManaBudget) {
      node.issues.add('${node.path}.scales',
          'мана не растёт от ilvl: цены способностей от глубины не зависят');
    }
    if (stat == StatKey.tagDamage && family.isEmpty) {
      node.issues.add('${node.path}.family',
          'аффикс на tagDamage обязан задавать семейство тегов');
    }
    if (stat != StatKey.tagDamage && family.isNotEmpty) {
      node.issues.add('${node.path}.family',
          'семейство тегов осмысленно только для tagDamage');
    }
    if (kinds.isEmpty) {
      node.issues.add('${node.path}.kinds',
          'аффикс, который не выпадает ни на чём, — мёртвый контент');
    }
    if (weight <= 0.0) {
      node.issues.add('${node.path}.weight', 'вес должен быть больше нуля');
    }

    checkTemplate(node, 'ru', node.str('ru', or: ''), {'value'});
    if (stat != StatKey.tagDamage &&
        TextTemplate.namesIn(node.str('ru', or: '')).contains('tag')) {
      node.issues.add('${node.path}.ru',
          'тег в описании есть, а семейства тегов у аффикса нет');
    }

    return StatAffixDef(
      id: node.str('id'),
      template: node.str('ru'),
      stat: stat,
      base: node.dbl('base'),
      scales: scales,
      kinds: kinds,
      weight: weight,
      family: family,
    );
  }

  @override
  String toString() => 'StatAffixDef($id, ${stat.name})';
}

/// Реализация триггера. Как и [AbilityKind], это контракт с рантаймом.
enum TriggerKind {
  everyNthHit,
  resetRandomCooldown,
  stackingBuff,
  applyDotOnTaggedAbility,
  lowHpTradeoff,
  periodicDoubleCast,
  curseSpread,
  reflect,
  firstHitBonus,
  healOnCursedKill,
  totemBoost,
  frostChain,
}

const Map<TriggerKind, List<ParamSpec>> triggerParamSpecs = {
  TriggerKind.everyNthHit: [
    ParamSpec.integer('n'),
    ParamSpec.number('multiplier'),
  ],
  TriggerKind.resetRandomCooldown: [
    ParamSpec.number('chance'),
  ],
  TriggerKind.stackingBuff: [
    ParamSpec.text('stat'),
    ParamSpec.number('value'),
    ParamSpec.number('duration'),
    ParamSpec.integer('maxStacks'),
  ],
  TriggerKind.applyDotOnTaggedAbility: [
    ParamSpec.text('tag'),
    ParamSpec.number('duration'),
    ParamSpec.number('dpsFraction'),
  ],
  TriggerKind.lowHpTradeoff: [
    ParamSpec.number('threshold'),
    ParamSpec.number('moreDamage'),
    ParamSpec.number('lessArmor'),
  ],
  TriggerKind.periodicDoubleCast: [
    ParamSpec.number('period'),
  ],
  TriggerKind.curseSpread: [],
  TriggerKind.reflect: [
    ParamSpec.number('chance'),
    ParamSpec.number('armorFraction'),
  ],
  TriggerKind.firstHitBonus: [
    ParamSpec.number('moreDamage'),
  ],
  TriggerKind.healOnCursedKill: [
    ParamSpec.number('fraction'),
  ],
  TriggerKind.totemBoost: [
    ParamSpec.number('duration'),
    ParamSpec.number('rate'),
  ],
  TriggerKind.frostChain: [
    ParamSpec.number('duration'),
    ParamSpec.number('slow'),
  ],
};

/// Типы предметов, на которых допустим триггерный аффикс.
///
/// Пять типов — это шесть слотов (колец два), то есть потолок в шесть
/// активных триггеров. Без потолка девять слотов дали бы восемнадцать и
/// комбинаторный хаос, который не проверяется ни тестами, ни балансировщиком.
const Set<GearKind> triggerAllowedKinds = {
  GearKind.weapon,
  GearKind.offhand,
  GearKind.gloves,
  GearKind.ring,
  GearKind.amulet,
};

class TriggerAffixDef {
  const TriggerAffixDef({
    required this.id,
    required this.name,
    required this.text,
    required this.event,
    required this.kind,
    required this.params,
    required this.kinds,
    required this.weight,
  });

  final String id;
  final String name;

  /// Шаблон описания для UI.
  final String text;

  /// Точка подписки на шине событий.
  final GameEventType event;

  final TriggerKind kind;
  final Params params;
  final List<GearKind> kinds;
  final double weight;

  static const _keys = {
    'id', 'ru', 'text', 'event', 'kind', 'params', 'kinds', 'weight',
  };

  static TriggerAffixDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final kind = node.enumByName('kind', TriggerKind.values,
        or: TriggerKind.everyNthHit)!;
    final params = readParams(node, triggerParamSpecs[kind] ?? const []);
    final kinds = node.enumList('kinds', GearKind.values);

    for (final k in kinds) {
      if (!triggerAllowedKinds.contains(k)) {
        node.issues.add('${node.path}.kinds',
            'триггер на ${k.name} ломает потолок в шесть активных триггеров');
      }
    }
    if (kind == TriggerKind.stackingBuff && params.has('stat')) {
      final name = params.str('stat');
      if (!StatKey.values.any((s) => s.name == name)) {
        node.issues
            .add('${node.path}.params.stat', 'неизвестный стат «$name»');
      }
    }
    if (kind == TriggerKind.applyDotOnTaggedAbility && params.has('tag')) {
      final name = params.str('tag');
      if (!Tag.values.any((t) => t.name == name)) {
        node.issues.add('${node.path}.params.tag', 'неизвестный тег «$name»');
      }
    }

    checkTemplate(
      node,
      'text',
      node.str('text', or: ''),
      {for (final spec in triggerParamSpecs[kind] ?? const []) spec.key},
    );

    return TriggerAffixDef(
      id: node.str('id'),
      name: node.str('ru'),
      text: node.str('text'),
      event: node.enumByName('event', GameEventType.values,
          or: GameEventType.onHit)!,
      kind: kind,
      params: params,
      kinds: kinds,
      weight: node.dbl('weight'),
    );
  }

  @override
  String toString() => 'TriggerAffixDef($id, ${kind.name})';
}
