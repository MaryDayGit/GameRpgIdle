/// Числа и время в том виде, в каком их читает игрок.
///
/// Отдельным файлом, потому что формат чисел — это язык интерфейса: если
/// «12.4k» в одном месте и «12400» в другом, экран выглядит собранным из
/// разных игр.
library;

import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/model/lang.dart';

/// Крупные числа: 1.2k, 3.4M. Экспоненциальная экономика иначе не читается —
/// на сотом этаже золото измеряется миллионами.
String money(double value) {
  final v = value.abs();
  if (v >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}k';
  return value.toStringAsFixed(0);
}

/// Число, у которого важна дробная часть.
///
/// [money] округляет до целого — и «0.5 восстановления HP в секунду»
/// превращается в «1», то есть во вдвое большее число, чем на самом деле.
/// Для крупных величин это незаметно, а восстановление, регенерация маны и
/// скорость атаки живут как раз около единицы.
String precise(double value) {
  final v = value.abs();
  if (v >= 100.0) return money(value);
  if (v == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(v < 10.0 ? 1 : 0);
}

/// Длительность до минут. Секунды показываются только когда их меньше минуты:
/// «осталось 7 м 12 с» читается хуже, чем «осталось 7 минут».
String duration(Duration d) {
  if (d.inSeconds < 60) {
    return Lang.current == Lang.ru ? '${d.inSeconds} с' : '${d.inSeconds}s';
  }
  if (d.inMinutes < 60) {
    return Lang.current == Lang.ru
        ? '${d.inMinutes} мин'
        : '${d.inMinutes} min';
  }
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (minutes == 0) {
    return Lang.current == Lang.ru ? '$hours ч' : '${hours}h';
  }
  return Lang.current == Lang.ru
      ? '$hours ч $minutes мин'
      : '${hours}h $minutes min';
}

/// Время боя — с секундами: там они значат разницу.
String clock(double seconds) {
  final total = seconds.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Проценты. Пробел перед знаком ставит язык, а не вкус, — и то же правило
/// действует в ядре ([TextTemplate.percent]), чтобы «8 %» на экране и «8 %»
/// в описании аффикса набирались одинаково.
String percent(double fraction) =>
    TextTemplate.percent(fraction.isFinite ? fraction : 0.0);

/// Согласование числительного: 1 осколок, 2 осколка, 5 осколков.
///
/// Нужно не ради красоты: строки вида «3 осколков» и «6 этажа» встречаются
/// в игре на каждом экране, и читаются они как недоделка.
///
/// У русского три формы, у английского две, и это не «две из трёх», а другое
/// правило: русская форма выбирается по последней цифре, английская — по
/// равенству единице. Поэтому формы передаются отдельными наборами, а не
/// переиспользуются.
///
/// [en] — английское единственное число; множественное по умолчанию
/// получается прибавлением `s`, что верно для почти всех слов игры (floor,
/// item, shard). Неправильные формы задаются через [enMany].
///
/// Пока [en] не передан, английский показывает русское слово. Это тот же
/// откат, что и у накладок контента: перевод доезжает по частям, и экран, до
/// которого он ещё не дошёл, работает, а не падает.
/// Английское числительное: единственное число ровно на единице, иначе `s`.
///
/// Отдельно от [plural], а не флагом внутри него: там, где строка уже собрана
/// в ветке `Lang.en`, русские формы передавать нечего, и звать общий [plural]
/// с тремя пустыми строками значило бы писать заглушки ради сигнатуры.
String pluralEn(int n, String one, [String? many]) =>
    n.abs() == 1 ? '$n $one' : '$n ${many ?? '${one}s'}';

String plural(
  int n,
  String one,
  String few,
  String many, {
  String? en,
  String? enMany,
}) {
  if (Lang.current == Lang.en && en != null) {
    return n.abs() == 1 ? '$n $en' : '$n ${enMany ?? '${en}s'}';
  }

  final mod100 = n.abs() % 100;
  if (mod100 >= 11 && mod100 <= 14) return '$n $many';

  return switch (n.abs() % 10) {
    1 => '$n $one',
    2 || 3 || 4 => '$n $few',
    _ => '$n $many',
  };
}
