import 'dart:io';

/// Сколько строк, которые видит ИГРОК, ещё не переведено.
///
///   dart run tool/l10n_ui.dart          сводка по файлам
///   dart run tool/l10n_ui.dart --list   каждая строка с номером
///
/// Простым поиском кириллицы не обойтись, и по двум причинам сразу.
///
/// **Переведённое тоже содержит русский.** `Phrase('Огонь', 'Fire')` — это
/// готовая строка, а не долг. Поэтому разбор идёт операторами, и оператор,
/// упоминающий язык, считается переведённым целиком.
///
/// **Не всякий русский текст видит игрок.** Валидатор контента и кодек сейва
/// разговаривают с разработчиком: «нет миграции с версии 3», «sqrt(a·b)
/// оказывается вне диапазона». Переводить их — не работа, а вред: сообщение
/// об ошибке ищут по тексту в исходниках, и перевод оборвёт этот путь.
/// Такие файлы перечислены в [_developerFacing] поимённо, с причиной.
///
/// Инструмент приблизителен, и это сказано вслух: он считает работу, а не
/// проверяет правильность. Ошибается он в сторону «ещё не переведено».
void main(List<String> args) {
  final list = args.contains('--list');

  final roots = [
    Directory('app/lib'),
    Directory('lib/core'),
  ];

  final perFile = <String, List<(int, String)>>{};

  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relative = entity.path.replaceAll(r'\', '/');
      if (_developerFacing.any(relative.endsWith)) continue;

      final found = _untranslatedIn(entity.readAsStringSync());
      if (found.isNotEmpty) perFile[relative] = found;
    }
  }

  final total = perFile.values.fold(0, (sum, l) => sum + l.length);
  if (total == 0) {
    stdout.writeln('Строк, которые видит игрок, непереведённых не осталось.');
    stdout.writeln('L10N-UI: OK');
    return;
  }

  final sorted = perFile.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  for (final entry in sorted) {
    stdout.writeln('${entry.value.length.toString().padLeft(5)}  ${entry.key}');
    if (!list) continue;
    for (final (line, text) in entry.value) {
      final short = text.length > 70 ? '${text.substring(0, 70)}…' : text;
      stdout.writeln('       :$line  $short');
    }
  }
  stdout.writeln('Осталось строк интерфейса: $total');
  stdout.writeln('L10N-UI: НЕПОЛНО');
}

/// Файлы, чей русский адресован разработчику, а не игроку.
///
/// Список поимённый, а не по маске: маска «всё в `content/`» однажды тихо
/// накрыла бы файл с настоящими игровыми текстами.
const _developerFacing = [
  // Валидатор контента: сообщения о битом JSON. Их читает тот, кто правит
  // контент, и ищет он их поиском по исходникам.
  'core/content/content_pack.dart',
  'core/content/json_node.dart',
  'core/content/params.dart',
  'core/content/content_issue.dart',
  'core/content/ability_def.dart',
  'core/content/affix_def.dart',
  'core/content/echo_tree_def.dart',
  'core/content/enemy_def.dart',
  'core/content/quest_def.dart',
  'core/content/relic_def.dart',
  'core/content/implicit_def.dart',
  'core/content/floor_modifier_def.dart',
  'core/content/passive_tree_def.dart',
  'core/content/text_template.dart',
  // Бестиарий Фазы 1 в `enemy.dart` — значения ПО УМОЛЧАНИЮ. Игра с
  // незагруженным контентом не стартует (`ContentPack.parse` бросает), так
  // что до экрана эти имена не доходят никогда: они нужны юнит-тестам формул
  // и `sim_cli`. Настоящие имена мобов лежат в `enemies.json` и переведены.
  'core/model/enemy.dart',
  // Список языков. «Русский» здесь — название языка на нём самом, и оно не
  // переводится по определению (см. `Lang.title`).
  'core/model/lang.dart',
  // Сейв: сообщения о нечитаемом файле и разорванной цепочке миграций.
  // Единственное, что из них доходит до игрока, — экран «сейв не читается»,
  // и его текст живёт в клиенте.
  'core/save/codec.dart',
  'core/save/migrations.dart',
  'core/save/save_data.dart',
  'core/save/save_issue.dart',
  // Дев-экран пробы ядра. К релизу он закрыт от игрока.
  'lib/dev/core_probe_screen.dart',
  'lib/dev/live_descent_panel.dart',
  'lib/dev/sim_runner.dart',
  'lib/dev/flame_probe.dart',
];

final _cyrillic = RegExp('[а-яА-ЯёЁ]');
final _literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");

/// Ищет непереведённые строки в тексте файла.
///
/// Целиком, а не построчно: двуязычное выражение занимает несколько строк —
/// русская форма на одной, английская на другой, — и построчный разбор счёл
/// бы первую половину пары долгом.
List<(int, String)> _untranslatedIn(String source) {
  // Комментарии заменяются пробелами той же длины: русского в них больше, чем
  // в самой игре, но вырезать их насовсем нельзя — сместятся номера строк.
  final text = source.replaceAllMapped(
      RegExp(r'^[ \t]*///?.*$', multiLine: true),
      (m) => ' ' * m.group(0)!.length);

  // Разбор идёт ОПЕРАТОРАМИ, а не строками, и правило одно: оператор,
  // упоминающий язык, переведён целиком.
  //
  // Так проще и надёжнее, чем вылавливать регуляркой каждую форму записи.
  // Их слишком много: `Phrase(…, …)`, тернарник `Lang.current == Lang.ru ? …
  // : …`, `switch (Lang.current)` с вложенным вторым switch внутри ветки.
  // Каждую пришлось бы описать отдельно, и первая же новая форма молча
  // добавила бы полсотни ложных долгов.
  //
  // Граница оператора — точка с запятой. Грубо, но для этой задачи верно:
  // двуязычное выражение целиком помещается в один оператор, и разрезать его
  // пополам нечему.
  final out = <(int, String)>[];
  var start = 0;
  String? quote;

  for (var i = 0; i <= text.length; i++) {
    if (i != text.length) {
      final ch = text[i];

      // Точка с запятой встречается и ВНУТРИ текста — «оно пропадёт; Верстак
      // даёт шанс». Резать оператор по ней значило бы разорвать двуязычную
      // пару пополам и объявить вторую половину долгом.
      if (quote != null) {
        if (ch == r'\') {
          i++;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch != ';') continue;
    }

    final statement = text.substring(start, i);
    if (!_bilingual.hasMatch(statement) && !_developerText.hasMatch(statement)) {
      for (final match in _literal.allMatches(statement)) {
        if (!_cyrillic.hasMatch(match.group(1)!)) continue;
        final at = start + match.start;
        final line = '\n'.allMatches(text.substring(0, at)).length + 1;
        out.add((line, match.group(1)!));
      }
    }
    start = i + 1;
  }
  return out;
}

/// Признаки того, что оператор уже говорит на двух языках.
///
/// [Forms] — четыре русские формы прилагательного. Согласование есть только в
/// русском, и второго набора у них не бывает по устройству языка: такой
/// оператор переведён ровно настолько, насколько это вообще возможно.
final _bilingual = RegExp(r'\bLang\.|\bPhrase(?:\.same)?\(|\bForms\(');

/// Признаки того, что переводить в операторе нечего.
///
/// Три случая, и все узнаются по форме, а не по имени файла — файл может
/// содержать и то, и другое:
///
///  * **сообщение исключения.** Его читает тот, кто чинит игру, и ищет он его
///    поиском по исходникам. Перевод оборвал бы этот путь. Единственное
///    исключение, которое доходит до игрока, — нечитаемый сейв, и его текст
///    пишет экран, а не то место, где исключение брошено;
///  * **`toString()`.** Это отладочный вывод: он попадает в лог и в отладчик,
///    но никогда на экран;
///  * **`_legacy…`** — данные прежних версий, которые читаются, но не
///    выдаются заново. Такие строки уже у игроков в сейвах: переводить их
///    поздно, а трогать — значит потерять то, на что они указывают. Пример —
///    русские имена наёмников в `mercenary.dart`, по которым выводится род на
///    сейве, сделанном до перевода имён.
final _developerText = RegExp(r'\bthrow\b|\btoString\(\)|\b_legacy');
