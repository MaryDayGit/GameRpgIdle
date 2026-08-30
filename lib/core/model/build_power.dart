import 'dart:math' as math;

import '../balance/curves.dart';
import '../content/ability_def.dart';
import '../content/content_pack.dart';
import 'stat_block.dart';
import 'tags.dart';

/// Сила билда одним числом.
///
/// Нужна ровно для двух вещей: наёмнику — решить, надевать ли найденное,
/// игроку — увидеть дельту к надетому в карточке предмета (без неё девять
/// слотов сравнивать невозможно, GDD §4.1).
///
/// Определение не произвольное. В формуле стены (GDD §2.3) множитель силы
/// билда `m` входит В КВАДРАТЕ: он поднимает и урон, и запас прочности.
/// Значит «сила» — это среднее геометрическое урона и EHP, и удвоение обоих
/// даёт ровно удвоение силы. Любая другая свёртка разошлась бы с той самой
/// формулой, на которой стоит весь баланс.
///
/// ## Почему сюда пришёл лоадаут
///
/// Первая версия считала одну автоатаку и не знала ни про способности, ни
/// про теги. Пока способность была прибавкой к тому же урону оружия, это
/// сходило с рук. С появлением второй оси перестало: сила чар не входила в
/// оценку вовсе, и наёмник, собирая лоадаут из сундука, НИКОГДА не надевал
/// вещь с силой чар — она стоила ровно ноль. Игрок собирал сборку на чарах,
/// а на спуск уходил боец с пустой левой рукой.
///
/// То же и с тегами: «+45 % к урону Огнём» стоило ноль, потому что оценка не
/// знала, чем этот билд бьёт.
///
/// Поэтому оценка принимает лоадаут. Без него она считает только автоатаку —
/// как и раньше, — и это честный ответ на вопрос «сколько стоит эта вещь
/// вообще», но не на вопрос «сколько она стоит ЭТОЙ сборке».
///
/// Это по-прежнему оценка ДЛЯ СРАВНЕНИЯ, а не число баланса: в ней нет ни
/// сопротивлений (они типозависимы), ни вампиризма, ни регена, ни того, что
/// способность делает помимо урона.
class BuildPower {
  BuildPower._();

  /// Долевые прибавки, которые достаются удару с этими тегами.
  static double _increased(StatBlock s, List<Tag> tags) {
    var v = s.increasedDamage;
    for (final tag in tags) {
      v += s.tagDamage[tag] ?? 0.0;
    }
    return 1.0 + v;
  }

  /// Теги автоатаки с учётом пропитки. Повторяет правило боя — и обязано
  /// повторять: два построения одного и того же расходятся.
  static List<Tag> _autoTags(List<AbilityDef> loadout) {
    for (final def in loadout) {
      if (def.kind == AbilityKind.infusion) {
        return [Tag.attack, Tag.strike, def.damageType.tag];
      }
    }
    return const [Tag.attack, Tag.strike, Tag.physical];
  }

  static double dps(StatBlock s, {List<AbilityDef> loadout = const []}) {
    final crit = 1.0 + s.critChance * s.critMulti;

    var total = s.attackDamage *
        s.effectiveAttackSpeed *
        _increased(s, _autoTags(loadout)) *
        crit;

    for (final def in loadout) {
      if (!def.isActive || def.cooldown <= 0.0) continue;

      final multiplier = def.params.dbl('weaponMultiplier');
      if (multiplier <= 0.0) continue;

      // От какой оси растёт способность — то же правило, что в бою.
      final base = def.isSpell ? s.spellPower : s.attackDamage;
      if (base <= 0.0) continue;

      // Сколько целей задевает. Волна редко бывает больше горстки, и
      // считать «по всей волне» за девяносто девять целей значило бы
      // объявить одну способность сильнее всей остальной сборки.
      final targets =
          def.params.integer('targets', 1).clamp(1, _typicalWaveSize);

      // Долевое сокращение перезарядки — там же, где в бою, и с тем же полом.
      final cooldown =
          def.cooldown * (1.0 - s.cooldownReduction).clamp(0.1, 1.0);

      total += base *
          multiplier *
          targets /
          cooldown *
          _increased(s, def.tags) *
          crit;
    }

    return total;
  }

  /// Сколько целей в типичной волне. Не точное число, а потолок оценки:
  /// способность «по всей волне» не должна выглядеть в сто раз сильнее
  /// способности по одной цели.
  static const int _typicalWaveSize = 4;

  static double ehp(StatBlock s, int depth) {
    final taken = 1.0 - Curves.armorMitigation(s.armor, depth);
    if (taken <= 0.0) return double.infinity;
    return s.maxHp / taken;
  }

  static double of(StatBlock s, int depth,
      {List<AbilityDef> loadout = const []}) {
    final d = dps(s, loadout: loadout);
    final e = ehp(s, depth);
    if (d <= 0.0 || e <= 0.0) return 0.0;
    if (e.isInfinite) return double.infinity;
    return math.sqrt(d * e);
  }

  /// Лоадаут по списку id. Неизвестные молча пропускаются: оценка не место,
  /// где падать из-за сейва, — этим занимается загрузка контента.
  static List<AbilityDef> loadoutOf(Iterable<String> ids) => [
        for (final id in ids)
          if (ContentPack.current.ability(id) case final def?) def,
      ];
}
