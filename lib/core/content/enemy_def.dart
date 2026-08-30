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

  static EnemyArchetype _common(
    JsonNode node, {
    required bool isBoss,
    required int packMin,
    required int packMax,
    required double weight,
    int everyFloors = 0,
    List<String> phases = const [],
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
    );
  }
}
