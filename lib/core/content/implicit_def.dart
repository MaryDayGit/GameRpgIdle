import '../model/gear.dart';
import '../model/stat_key.dart';
import 'json_node.dart';

/// Базовый стат типа предмета.
///
/// Не роллится и не зависит от редкости — в этом весь смысл. Имплицит
/// гарантирует, что предмет большей глубины сам по себе является апгрейдом.
/// Без него апгрейдом становится только удачный редкий ролл: обычные предметы
/// перестают побеждать надетое уже через полтора десятка этажей, снаряжение
/// отстаёт от глубины всё сильнее, и формула стены (GDD §2.3) перестаёт
/// сходиться — замерено 16 этажей на удвоение силы вместо 40.
class ImplicitDef {
  const ImplicitDef({
    required this.kind,
    required this.stat,
    required this.base,
    required this.profile,
  });

  final GearKind kind;
  final StatKey stat;

  /// Значение на ilvl 1. Растёт как `itemScale(ilvl)`.
  final double base;

  /// Профиль слота одной строкой (GDD §4.1) — текст для UI.
  final String profile;

  static const _keys = {'kind', 'stat', 'base', 'ru'};

  static ImplicitDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final stat = node.enumByName('stat', StatKey.values, or: StatKey.maxHp)!;
    final base = node.dbl('base');

    // Долевой имплицит не растёт от ilvl и потому не решает ту задачу,
    // ради которой имплициты существуют.
    if (stat.isFraction) {
      node.issues.add('${node.path}.stat',
          'имплицит обязан быть растущим статом, а ${stat.name} — долевой');
    }
    if (base <= 0.0) {
      node.issues.add('${node.path}.base', 'должен быть больше нуля');
    }

    return ImplicitDef(
      kind: node.enumByName('kind', GearKind.values, or: GearKind.weapon)!,
      stat: stat,
      base: base,
      profile: node.str('ru', or: ''),
    );
  }

  @override
  String toString() => 'ImplicitDef(${kind.name}: ${stat.name} $base)';
}
