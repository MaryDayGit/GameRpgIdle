import '../model/tags.dart';
import 'json_node.dart';

/// Подстановка чисел в описания аффиксов, триггеров и способностей.
///
/// Плейсхолдер называет ПАРАМЕТР, а не свою позицию: `{duration:s}`, а не
/// `{d}`. Разница не косметическая — при позиционных плейсхолдерах никто не
/// может проверить, что `{p1}` и `{p2}` стоят в том же порядке, в каком лежат
/// параметры, и текст расходится с механикой молча. С именами это проверяет
/// валидатор контента, а расхождение становится ошибкой загрузки.
///
/// Формат после двоеточия задаёт автор текста, а не угадывает код:
///
///  * `{value}`      — как есть, округлённо
///  * `{value:%}`    — доля в процентах: 0.08 -> «8 %»
///  * `{value:x}`    — множитель: 2.0 -> «×2»
///  * `{value:s}`    — секунды: 4.0 -> «4 с»
///  * `{tag}`        — тег в форме «к урону Огнём»; особый случай
///                    семейства `tagDamage`
class TextTemplate {
  TextTemplate._();

  static final RegExp _slot = RegExp(r'\{(\w+)(?::([%xs]))?\}');

  /// Имена параметров, на которые ссылается шаблон.
  static List<String> namesIn(String template) =>
      [for (final m in _slot.allMatches(template)) m.group(1)!];

  /// Подставляет значения. Неизвестное имя остаётся плейсхолдером — так оно
  /// заметно в интерфейсе, а не превращается в пустоту.
  static String render(
    String template,
    Map<String, double> values, {
    Tag? tag,
  }) =>
      template.replaceAllMapped(_slot, (match) {
        final name = match.group(1)!;
        final format = match.group(2);

        // Форма «к урону Огнём», а не название «Огонь»: строка собирается
        // вокруг тега, и падеж принадлежит ему, а не шаблону.
        if (name == 'tag') return tag?.ruDamage ?? match.group(0)!;

        final value = values[name];
        if (value == null) return match.group(0)!;

        return switch (format) {
          '%' => '${_number(value * 100)} %',
          'x' => '×${_number(value)}',
          's' => '${_number(value)} с',
          _ => _number(value),
        };
      });

  /// Числа в описаниях: без хвостовых нулей, но и без потери долей.
  /// «+0.15 восстановления» и «+30 к HP» должны читаться одинаково спокойно.
  static String _number(double value) {
    final rounded = value.roundToDouble();
    final text = (value - rounded).abs() < 0.005
        ? rounded.toStringAsFixed(0)
        : value.abs() < 1.0
            ? value.toStringAsFixed(2)
            : value.toStringAsFixed(1);

    // Минус — типографский, как в текстах аффиксов. Дефис из `toString`
    // рядом с «−15 %» из соседней строки читается как другой знак, и это
    // ровно тот сорт мелочи, из которого складывается «странно выглядит».
    return text.startsWith('-') ? '\u2212${text.substring(1)}' : text;
  }
}

/// Проверяет, что каждый плейсхолдер шаблона называет существующий параметр.
///
/// Это и есть причина, по которой плейсхолдеры именованные. Описание, где
/// написано «+20 % урона», а в параметрах лежит 0.6, — это ложь игроку, и
/// заметить её можно только глазами, сверяя два файла. Здесь она становится
/// ошибкой загрузки.
void checkTemplate(
  JsonNode node,
  String field,
  String template,
  Set<String> allowed,
) {
  for (final name in TextTemplate.namesIn(template)) {
    if (name == 'tag') continue;
    if (allowed.contains(name)) continue;
    node.issues.add('${node.path}.$field',
        'плейсхолдер {$name} не соответствует ни одному параметру'
        '${allowed.isEmpty ? "" : " (есть: ${allowed.join(", ")})"}');
  }
}
