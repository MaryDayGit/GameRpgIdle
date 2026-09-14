import '../model/enemy.dart';
import '../model/grammar.dart';
import '../model/tags.dart';
import 'json_node.dart';

/// Разбор бестиария. Результат — те же [EnemyArchetype], что и значения по
/// умолчанию в [Bestiary]: модель одна, источников два.
class EnemyParser {
  EnemyParser._();

  static const _enemyKeys = {
    'id', 'ru', 'gender', 'role', 'hpMult', 'dpsMult', 'attackSpeed',
    'armorMult', 'packMin', 'packMax', 'damageType', 'resists', 'weight',
    'traits',
  };

  static const _bossKeys = {
    'id', 'ru', 'gender', 'role', 'everyFloors', 'hpMult', 'dpsMult',
    'attackSpeed', 'armorMult', 'damageType', 'resists', 'traits', 'phases',
  };

  static EnemyArchetype parseEnemy(JsonNode node) {
    node.checkKeys(_enemyKeys);

    final packMin = node.integer('packMin');
    final packMax = node.integer('packMax');
    final weight = node.dbl('weight');

    if (packMin < 1) {
      node.issues.add('${node.path}.packMin', 'в пачке должен быть хотя бы один');
    }
    if (packMax < packMin) {
      node.issues.add('${node.path}.packMax', 'верхняя граница ниже нижней');
    }
    if (weight <= 0.0) {
      node.issues.add('${node.path}.weight',
          'моб с нулевым весом не выпадет никогда — это мёртвый контент');
    }

    return _common(
      node,
      isBoss: false,
      packMin: packMin,
      packMax: packMax,
      weight: weight,
    );
  }

  static EnemyArchetype parseBoss(JsonNode node) {
    node.checkKeys(_bossKeys);

    final everyFloors = node.integer('everyFloors');
    if (everyFloors <= 0) {
      node.issues.add('${node.path}.everyFloors',
          'периодичность босса должна быть больше нуля');
    }

    return _common(
      node,
      isBoss: true,
      packMin: 1,
      packMax: 1,
      weight: 0.0,
      everyFloors: everyFloors,
      phases: node.strList('phases'),
    );
  }

  static const _guardianKeys = {
    'id', 'ru', 'gender', 'role', 'boss', 'hpMult', 'dpsMult',
    'attackSpeed', 'armorMult', 'damageType', 'resists', 'traits', 'phases',
    'skills',
  };

  static const _skillKeys = {
    'id', 'ru', 'kind', 'every', 'first', 'windup', 'power', 'duration',
    'threshold',
  };

  /// Страж области: тот же босс, но в своём логове и в полную силу.
  static EnemyArchetype parseGuardian(JsonNode node) {
    node.checkKeys(_guardianKeys);

    return _common(
      node,
      isBoss: true,
      packMin: 1,
      packMax: 1,
      weight: 0.0,
      phases: node.strList('phases'),
      embodies: node.str('boss'),
      skills: [for (final s in node.children('skills')) _skill(s)],
    );
  }

  /// Умение стража. Проверяется по виду: у каждого свои обязательные числа, и
  /// умение с нулём там, где оно должно бить, молча не делало бы ничего.
  static GuardianSkill _skill(JsonNode n) {
    n.checkKeys(_skillKeys);

    final kind = n.enumByName('kind', GuardianSkillKind.values) ??
        GuardianSkillKind.slam;
    final every = n.dbl('every', or: 0.0);
    final windup = n.dbl('windup', or: 0.0);
    final power = n.dbl('power', or: 0.0);
    final duration = n.dbl('duration', or: 0.0);
    final threshold = n.dbl('threshold', or: 0.0);

    void bad(String field, String why) =>
        n.issues.add('${n.path}.$field', why);

    if (kind != GuardianSkillKind.enrage) {
      if (every <= 0.0) bad('every', 'умение без перерыва — это не умение');
      if (windup < 0.0 || windup >= every) {
        bad('windup', 'замах обязан быть короче перерыва');
      }
    }

    switch (kind) {
      case GuardianSkillKind.slam:
      case GuardianSkillKind.expose:
        if (power <= 0.0) bad('power', 'должно быть больше нуля');
        if (kind == GuardianSkillKind.expose && duration <= 0.0) {
          bad('duration', 'должно быть больше нуля');
        }
      case GuardianSkillKind.burn:
        if (power <= 0.0) bad('power', 'должно быть больше нуля');
        if (duration <= 0.0) bad('duration', 'должно быть больше нуля');
      case GuardianSkillKind.stun:
        // Оглушение дольше половины перерыва — это не умение, а цепи: герой
        // стоит больше, чем бьёт, и исход решает не сборка, а таймер.
        if (duration <= 0.0 || duration > every * 0.5) {
          bad('duration', 'оглушение обязано быть короче половины перерыва');
        }
      case GuardianSkillKind.silence:
        if (duration <= 0.0 || duration >= every) {
          bad('duration', 'немота обязана быть короче перерыва');
        }
      case GuardianSkillKind.shield:
        // Щит на весь бой — это не повадка, а бессмертие.
        if (power <= 0.0 || power > 0.8) bad('power', 'доля от 0 до 0.8');
        if (duration <= 0.0 || duration >= every) {
          bad('duration', 'щит обязан быть короче перерыва');
        }
      case GuardianSkillKind.enrage:
        if (threshold <= 0.0 || threshold >= 1.0) {
          bad('threshold', 'доля здоровья от 0 до 1');
        }
        if (power <= 0.0) bad('power', 'должно быть больше нуля');
    }

    return GuardianSkill(
      id: n.str('id'),
      name: n.str('ru'),
      kind: kind,
      every: every,
      first: n.dbl('first', or: 0.0),
      windup: windup,
      power: power,
      duration: duration,
      threshold: threshold,
    );
  }

  static EnemyArchetype _common(
    JsonNode node, {
    required bool isBoss,
    required int packMin,
    required int packMax,
    required double weight,
    int everyFloors = 0,
    String? embodies,
    List<String> phases = const [],
    List<GuardianSkill> skills = const [],
  }) {
    final attackSpeed = node.dbl('attackSpeed');
    final hpMult = node.dbl('hpMult');
    final dpsMult = node.dbl('dpsMult');

    // Урон за удар выводится делением на скорость атаки. Ноль здесь — это не
    // «моб не бьёт», а бесконечность в боевом цикле.
    if (attackSpeed <= 0.0) {
      node.issues.add('${node.path}.attackSpeed', 'должна быть больше нуля');
    }
    if (hpMult <= 0.0) {
      node.issues.add('${node.path}.hpMult', 'должен быть больше нуля');
    }
    if (dpsMult <= 0.0) {
      node.issues.add('${node.path}.dpsMult', 'должен быть больше нуля');
    }

    return EnemyArchetype(
      id: node.str('id'),
      name: node.str('ru'),
      gender: node.enumByName('gender', Gender.values, or: Gender.masculine)!,
      role: node.str('role', or: ''),
      hpMult: hpMult,
      dpsMult: dpsMult,
      attackSpeed: attackSpeed,
      armorMult: node.dbl('armorMult', or: 0.0),
      packMin: packMin,
      packMax: packMax,
      damageType: node.enumByName('damageType', DamageType.values,
          or: DamageType.physical)!,
      resists: node.enumDoubleMap('resists', DamageType.values),
      isBoss: isBoss,
      weight: weight,
      traits: node.enumList('traits', EnemyTrait.values).toSet(),
      everyFloors: everyFloors,
      phases: phases,
      embodies: embodies,
      skills: skills,
    );
  }
}
