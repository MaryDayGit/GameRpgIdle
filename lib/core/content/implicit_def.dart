import '../model/gear.dart';
import '../model/stat_key.dart';
import 'affix_def.dart';
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
    required this.pools,
    required this.profile,
  });

  final GearKind kind;
  final StatKey stat;

  /// Значение на ilvl 1. Растёт как `itemScale(ilvl)`.
  final double base;

  /// С какими пулами аффиксов работает слот и в какой пропорции.
  ///
  /// Это и есть характер слота, записанный числом. Ролл сначала выбирает
  /// пул по этим весам и только потом аффикс внутри пула — поэтому «доля
  /// защиты у левой руки» перестала быть тем, что случайно вышло из суммы
  /// двадцати шести весов, и стала тем, что здесь написано.
  ///
  /// Правило, которое держит валидатор: **у слота ровно два пула, и защита
  /// с атакой не встречаются вместе.** Исключение одно — кольцо и амулет:
  /// это единственные слоты, где можно найти что угодно, и в этом вся их
  /// роль.
  final Map<AffixPool, double> pools;

  /// Профиль слота одной строкой (GDD §4.1) — текст для UI.
  final String profile;

  static const _keys = {'kind', 'stat', 'base', 'pools', 'ru'};

  static ImplicitDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final stat = node.enumByName('stat', StatKey.values, or: StatKey.maxHp)!;
    final base = node.dbl('base');
    final pools = node.enumDoubleMap('pools', AffixPool.values);

    // Долевой имплицит не растёт от ilvl и потому не решает ту задачу,
    // ради которой имплициты существуют.
    if (stat.isFraction) {
      node.issues.add('${node.path}.stat',
          'имплицит обязан быть растущим статом, а ${stat.name} — долевой');
    }
    if (base <= 0.0) {
      node.issues.add('${node.path}.base', 'должен быть больше нуля');
    }

    // Слот без пулов не роллит ничего: предмет выпадет с одним имплицитом.
    if (pools.values.where((w) => w > 0).isEmpty) {
      node.issues.add('${node.path}.pools',
          'слот обязан принимать хотя бы один пул с ненулевым весом');
    }
    for (final e in pools.entries) {
      if (e.value < 0.0) {
        node.issues.add('${node.path}.pools.${e.key.name}',
            'вес пула не может быть отрицательным');
      }
    }

    return ImplicitDef(
      kind: node.enumByName('kind', GearKind.values, or: GearKind.weapon)!,
      stat: stat,
      base: base,
      pools: pools,
      profile: node.str('ru', or: ''),
    );
  }

  @override
  String toString() => 'ImplicitDef(${kind.name}: ${stat.name} $base)';
}
