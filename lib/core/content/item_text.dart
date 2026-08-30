import '../model/item.dart';
import 'content_pack.dart';
import 'text_template.dart';

/// Предмет словами.
///
/// Живёт в ядре, а не в интерфейсе: описание предмета нужно и экрану, и
/// журналу отсутствия, и балансировщику, когда он показывает, что именно
/// нашёл наёмник. Три разные реализации разошлись бы, и игрок увидел бы
/// «+8 % урона» в одном месте и «+0.08 урона» в другом.
class ItemText {
  ItemText._();

  /// Строки описания в порядке чтения: сперва то, что есть всегда, потом
  /// то, что выпало, и в конце то, что меняет правила.
  static List<String> lines(Item item) {
    final pack = ContentPack.isLoaded ? ContentPack.current : null;
    final out = <String>[];

    final implicit = item.implicit;
    if (implicit != null) {
      final def = pack?.implicitFor(item.kind);
      // Имплицит подписан отдельно намеренно. Он и аффикс могут давать один и
      // тот же стат, и две одинаковые строки подряд читаются как ошибка: игрок
      // не понимает, почему «+48 к броне» написано дважды.
      out.add('Основа: ${_sign(implicit.value)} '
          '${def?.stat.ru ?? implicit.stat.ru}');
    }

    for (final roll in item.affixes) {
      final def = pack?.statAffix(roll.affixId);
      if (def == null) {
        // Определение вырезали из контента, а ролл остался. Показать значение
        // всё равно честнее, чем спрятать строку и оставить игрока гадать,
        // почему предмет сильнее, чем выглядит.
        out.add('${_sign(roll.value)} ${roll.stat.ru}');
        continue;
      }
      out.add(TextTemplate.render(
        def.template,
        {'value': roll.value},
        tag: roll.tag,
      ));
    }

    final triggerId = item.triggerAffixId;
    if (triggerId != null) {
      final def = pack?.triggerAffix(triggerId);
      if (def != null) {
        out.add('${def.name}: ${TextTemplate.render(def.text, _numbers(def.params.raw))}');
      }
    }

    final relicId = item.relicId;
    if (relicId != null) {
      final def = pack?.relic(relicId);
      if (def != null) out.add(def.text);
    }

    return out;
  }

  /// Заголовок карточки: тип, уровень, редкость.
  static String title(Item item) {
    final hands = item.twoHanded ? ' (двуручное)' : '';
    // Редкость согласуется с типом вещи. Иначе заголовок читается как
    // «Кольцо · Редкий» — и это первое, обо что спотыкается глаз.
    return '${item.kind.ru}$hands · ${item.ilvl} ур. · '
        '${item.rarity.forKind(item.kind)}';
  }

  static Map<String, double> _numbers(Map<String, dynamic> raw) => {
        for (final entry in raw.entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      };

  static String _sign(double value) =>
      value >= 0 ? '+${_short(value)}' : _short(value);

  static String _short(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.005) return rounded.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
