import 'dart:convert';
import 'dart:io';

import 'package:rift/core/content/content_issue.dart';
import 'package:rift/core/content/content_pack.dart';

/// Балансовые таблицы: весь контент игры в Markdown и обратно.
///
/// ## Зачем
///
/// Числа игры лежат в `assets/content/*.json`. Править их с телефона нельзя:
/// JSON на маленьком экране — это ловушка из запятых и вложенности, и одна
/// пропущенная скобка ломает загрузку целиком. А баланс как раз и хочется
/// смотреть не за рабочим столом: он живёт в голове, а не в IDE.
///
/// Поэтому здесь **две стороны одного и того же**:
///
/// * `--export` — раскладывает JSON в таблицы `balance/*.md`. Их видно с
///   телефона на github.com, они читаются глазами и правятся в веб-редакторе;
/// * `--apply` — забирает правки из таблиц обратно в JSON.
///
/// ## Почему это не второй источник правды
///
/// Таблицы **выводятся** из контента, а не ведутся рядом с ним. `--export`
/// перезаписывает их целиком, `--apply` меняет только те числа, что
/// разошлись. Расходиться им негде: между двумя запусками файл — это ровно
/// тот же контент, только в другой записи.
///
/// Якорь строки — не её место в файле, а пара «id сущности + путь к числу».
/// Поэтому переставленные строки, дописанные заметки и правки текста вокруг
/// таблиц ничего не ломают: разбирается только то, что размечено маркером
/// `<!-- balance: ... -->`.
///
/// ## Что защищает от порчи
///
/// `--apply` сначала собирает ВСЕ изменения, потом прогоняет получившийся
/// контент через `ContentPack.parse`, и лишь если проверка чиста — пишет на
/// диск. Опечатка в одной клетке не оставит игру с половиной применённых
/// правок: либо всё, либо ничего.
///
/// ## Использование
///
/// ```
/// dart run tool/balance_sheet.dart --export   # JSON → таблицы
/// dart run tool/balance_sheet.dart --check    # что изменится, без записи
/// dart run tool/balance_sheet.dart --apply    # таблицы → JSON
/// ```
void main(List<String> args) {
  final mode = args.isEmpty ? '--export' : args.first;

  switch (mode) {
    case '--export':
      final written = BalanceSheet.export();
      stdout.writeln('Записано файлов: $written');
      stdout.writeln('BALANCE-SHEET: OK');
    case '--check':
      _report(BalanceSheet.apply(dryRun: true));
    case '--apply':
      _report(BalanceSheet.apply(dryRun: false));
    default:
      stderr.writeln('Режимы: --export, --check, --apply');
      exit(2);
  }
}

void _report(ApplyReport report) {
  for (final error in report.errors) {
    stderr.writeln('ОШИБКА: $error');
  }
  if (report.errors.isNotEmpty) {
    stderr.writeln('Ничего не записано: сначала исправьте перечисленное.');
    exit(1);
  }

  if (report.changes.isEmpty) {
    stdout.writeln('Расхождений нет — контент и таблицы совпадают.');
    stdout.writeln('BALANCE-SHEET: OK');
    return;
  }

  for (final change in report.changes) {
    stdout.writeln(change);
  }
  stdout.writeln('Изменений: ${report.changes.length}');

  if (report.dryRun) {
    stdout.writeln('Это проверка. Записать: --apply');
  } else {
    stdout.writeln('Записано. Дальше:');
    stdout.writeln('  cd app && dart run tool/sync_content.dart');
    stdout.writeln('  dart run tool/sim_cli.dart --campaign 20');
  }
  stdout.writeln('BALANCE-SHEET: OK');
}

/// Что дал `--apply`.
class ApplyReport {
  ApplyReport({
    required this.changes,
    required this.errors,
    required this.dryRun,
  });

  /// Строки вида «enemies · Падальщик · hpMult: 0.6 → 0.7».
  final List<String> changes;

  /// Всё, что помешало применить. Пока список не пуст, не пишется НИЧЕГО.
  final List<String> errors;

  final bool dryRun;
}

/// Одно число в таблице.
class _Cell {
  _Cell(this.path, this.value);

  /// Путь внутри сущности: `hpMult`, `params.weaponMultiplier`,
  /// `resists.fire`.
  final String path;

  /// `num` либо `List<num>` — списки живут одной клеткой через запятую.
  final Object value;
}

/// Откуда берутся строки таблицы.
class _Source {
  const _Source({
    required this.file,
    required this.path,
    required this.title,
    this.about,
  });

  /// Имя файла контента без `.json`.
  final String file;

  /// Путь до списка сущностей или до словаря чисел. Сегмент, который
  /// указывает на список списков (древо Эха: `branches` → `nodes`), просто
  /// перечисляется дальше: `['branches', 'nodes']`.
  final List<String> path;

  final String title;
  final String? about;
}

/// Один файл таблиц.
class _Sheet {
  const _Sheet({
    required this.name,
    required this.title,
    required this.about,
    required this.sources,
  });

  final String name;
  final String title;
  final String about;
  final List<_Source> sources;
}

class BalanceSheet {
  BalanceSheet._();

  static const dir = 'balance';
  static const contentDir = 'assets/content';

  /// Ключи, которые числа, но не баланс. Координаты узлов дерева — это
  /// вёрстка картинки; правкой `x` баланс не двигают, а дерево разъезжается.
  static const _skip = {'x', 'y', 'version', 'icon'};

  static const _sheets = <_Sheet>[
    _Sheet(
      name: '01-core',
      title: 'Основа: кривые, герой, бой, добыча',
      about: 'Числа, от которых зависит вся игра сразу. Кривые роста врагов '
          'и вещей решают, где стена; базовые статы героя — с чего он '
          'начинает; добыча — сколько всего этого падает.\n\n'
          'Здесь правки самые опасные: один множитель роста меняет каждый '
          'спуск. После правки обязательно прогнать `--curve` и `--campaign`.',
      sources: [
        _Source(
          file: 'balance',
          path: ['curves'],
          title: 'Кривые',
          about: 'Рост врагов, рост вещей, Эхо, золото, Клеймо, верёвка.',
        ),
        _Source(
          file: 'balance',
          path: ['hero'],
          title: 'Голый герой',
          about: 'С чем наёмник входит вниз без единой вещи.',
        ),
        _Source(
          file: 'balance',
          path: ['combat'],
          title: 'Бой и спуск',
          about: 'Тик, волны, отдых, развилки, третий путь.',
        ),
        _Source(
          file: 'balance',
          path: ['loot'],
          title: 'Добыча',
          about: 'Сундуки, редкости, перцентили, крафтовое сырьё.',
        ),
        _Source(
          file: 'balance',
          path: ['traits'],
          title: 'Повадки врагов',
          about: 'Числа за повадками бестиария: замедление, взрыв, отражение.',
        ),
        _Source(
          file: 'balance',
          path: ['crafting'],
          title: 'Кузница',
          about: 'Цены переката и углубления, вместимость верстака.',
        ),
        _Source(
          file: 'balance',
          path: ['outpost'],
          title: 'Застава',
          about: 'Постройки: что даёт уровень и сколько он стоит.',
        ),
      ],
    ),
    _Sheet(
      name: '02-enemies',
      title: 'Враги и боссы',
      about: 'Множители считаются от кривой этажа, а не задаются числом: '
          '`hpMult` 0.6 значит «шесть десятых обычного HP этого этажа». '
          'Поэтому мобов можно переставлять между собой, не трогая кривые.\n\n'
          '`weight` — вес в выпадении: чем больше, тем чаще встречается.',
      sources: [
        _Source(file: 'enemies', path: ['enemies'], title: 'Обычные'),
        _Source(file: 'enemies', path: ['bosses'], title: 'Боссы'),
      ],
    ),
    _Sheet(
      name: '03-modifiers',
      title: 'Модификаторы этажей',
      about: 'Каждый модификатор — одна плата и одна награда. Ими же живёт '
          'разлом дня и третий путь развилки: он складывает награды обоих '
          'путей, так что усиление любого модификатора усиливает и его.',
      sources: [
        _Source(file: 'floor_modifiers', path: ['modifiers'], title: 'Восемь путей'),
      ],
    ),
    _Sheet(
      name: '04-abilities',
      title: 'Умения',
      about: '`cooldown` — перезарядка в секундах, `mana` — цена срабатывания. '
          'Остальное лежит в `params` и зависит от вида умения: множитель '
          'урона оружия, доля силы чар, число целей, длительность.\n\n'
          'Текст умения на экране собирается из этих же чисел, так что '
          'править описание отдельно не нужно — оно подставится само.',
      sources: [
        _Source(file: 'abilities', path: ['abilities'], title: 'Все 55'),
      ],
    ),
    _Sheet(
      name: '05-relics',
      title: 'Реликты',
      about: 'Реликт меняет правило боя, а числа при нём — цена и размер '
          'этого правила. Что именно делает реликт, задаёт поле `effect` в '
          'JSON: его тут нет намеренно, это не баланс, а код.',
      sources: [
        _Source(file: 'relics', path: ['relics'], title: 'Двадцать пять'),
      ],
    ),
    _Sheet(
      name: '06-affixes',
      title: 'Аффиксы и основы вещей',
      about: '`base` — значение на первом уровне предмета; дальше оно растёт '
          'по кривой вещей, если `scales`. `weight` — как часто аффикс '
          'выпадает по сравнению с остальными для того же вида вещи.',
      sources: [
        _Source(file: 'affixes_stat', path: ['affixes'], title: 'Статовые'),
        _Source(file: 'affixes_trigger', path: ['affixes'], title: 'Триггерные'),
        _Source(file: 'items', path: ['implicits'], title: 'Основы вещей'),
      ],
    ),
    _Sheet(
      name: '07-trees',
      title: 'Древо Эха и дерево пассивок',
      about: 'Древо Эха покупается за Эхо и остаётся навсегда; дерево '
          'пассивок берётся очками за глубину и живёт один спуск.\n\n'
          'Координаты узлов (`x`, `y`) в таблицы не выведены: это вёрстка '
          'картинки, а не баланс.',
      sources: [
        _Source(
          file: 'echo_tree',
          path: ['branches', 'nodes'],
          title: 'Древо Эха',
        ),
        _Source(
          file: 'passive_tree',
          path: ['nodes'],
          title: 'Дерево пассивок',
        ),
      ],
    ),
    _Sheet(
      name: '08-quests',
      title: 'Задания',
      about: '`value` — порог, на котором задание закрывается; `echo` — '
          'сколько Эха оно платит сверх умения.',
      sources: [
        _Source(file: 'quests', path: ['quests'], title: 'Сорок четыре цели'),
      ],
    ),
  ];

  // --- Экспорт ---------------------------------------------------------------

  /// JSON → таблицы. Возвращает число записанных файлов.
  static int export({String root = '.'}) {
    final content = _readAll(root);
    Directory('$root/$dir').createSync(recursive: true);

    var written = 0;
    for (final sheet in _sheets) {
      File('$root/$dir/${sheet.name}.md')
          .writeAsStringSync(_renderSheet(sheet, content));
      written++;
    }
    File('$root/$dir/README.md').writeAsStringSync(_renderIndex());
    written++;

    // Контент переписывается в той же записи, в которой его пишет `--apply`.
    // Иначе первая же правка одного числа давала бы диф на весь файл — из-за
    // отступов, а не из-за баланса.
    for (final entry in content.entries) {
      _writeJson('$root/$contentDir/${entry.key}.json', entry.value);
    }
    return written;
  }

  static String _renderIndex() {
    final buffer = StringBuffer()
      ..writeln('# Баланс «Расселины»')
      ..writeln()
      ..writeln('Все числа игры таблицами. Их можно читать и править прямо '
          'здесь, с телефона: GitHub даёт редактор на каждый файл.')
      ..writeln()
      ..writeln('## Как это работает')
      ..writeln()
      ..writeln('1. Правите число в клетке и коммитите — прямо в вебе.')
      ..writeln('2. На машине с проектом:')
      ..writeln()
      ..writeln('```')
      ..writeln('git pull')
      ..writeln('dart run tool/balance_sheet.dart --check   # что изменится')
      ..writeln('dart run tool/balance_sheet.dart --apply   # в JSON игры')
      ..writeln('cd app && dart run tool/sync_content.dart  # зеркало для APK')
      ..writeln('```')
      ..writeln()
      ..writeln('3. Проверить, во что это обошлось игре:')
      ..writeln()
      ..writeln('```')
      ..writeln('dart test                                   # правила игры целы')
      ..writeln('dart run tool/sim_cli.dart --curve           # где стена')
      ..writeln('dart run tool/sim_cli.dart --campaign 20     # шестьдесят спусков')
      ..writeln('dart run tool/audit_cli.dart --relics        # всё ли работает')
      ..writeln('```')
      ..writeln()
      ..writeln('## Правила таблиц')
      ..writeln()
      ..writeln('* Правится **только колонка со значением.** Имя, id и путь '
          'параметра — это адрес строки; поменяете их — правка не найдёт, '
          'куда лечь.')
      ..writeln('* Пустая клетка значит «этого параметра у сущности нет». '
          'Оставьте её пустой.')
      ..writeln('* Дробная часть — через точку или запятую, обе понимаются. '
          'Список чисел в одной клетке разделяется запятой с пробелом.')
      ..writeln('* Строки можно переставлять, между таблицами — дописывать '
          'свои заметки. Разбирается только то, что размечено маркером '
          '`<!-- balance: ... -->`; его трогать не надо.')
      ..writeln('* `--apply` либо применяет ВСЁ, либо не пишет ничего: '
          'сначала он собирает правки, потом проверяет получившийся контент '
          'целиком, и только чистый контент попадает на диск.')
      ..writeln()
      ..writeln('## Файлы')
      ..writeln();

    for (final sheet in _sheets) {
      buffer.writeln('* [${sheet.title}](${sheet.name}.md)');
    }

    buffer
      ..writeln()
      ..writeln('## Чего здесь нет')
      ..writeln()
      ..writeln('Не-числовых полей: тегов умений, видов вещей, эффектов '
          'реликтов, текстов. Это не баланс, а устройство контента — и '
          'правится оно в `assets/content/*.json` вместе с кодом, который '
          'их читает.')
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('Файлы этой папки собраны `tool/balance_sheet.dart`. '
          'Править их руками — можно и нужно; переписывать по кругу '
          '`--export` тоже безопасно: он выводит их из того же контента.');
    return buffer.toString();
  }

  static String _renderSheet(_Sheet sheet, Map<String, Object?> content) {
    final buffer = StringBuffer()
      ..writeln('# ${sheet.title}')
      ..writeln()
      ..writeln(sheet.about)
      ..writeln();

    for (final source in sheet.sources) {
      final rows = _collect(content, source);
      if (rows.isEmpty) continue;

      buffer
        ..writeln('## ${source.title}')
        ..writeln();
      if (source.about != null) {
        buffer
          ..writeln(source.about)
          ..writeln();
      }

      if (source.path.length == 1 && rows.length == 1 && rows.first.isScalars) {
        _renderScalars(buffer, source, rows.first);
      } else {
        _renderEntities(buffer, source, rows);
      }
      buffer.writeln();
    }

    buffer
      ..writeln('---')
      ..writeln()
      ..writeln('Правится только колонка со значением. '
          'Как применить — [в оглавлении](README.md).');
    return buffer.toString();
  }

  /// Словарь чисел (разделы `balance.json`): ключ, значение и пояснение из
  /// соседнего `_кл ючComment`, если оно есть.
  static void _renderScalars(
      StringBuffer buffer, _Source source, _Row row) {
    buffer
      ..writeln('<!-- balance: file=${source.file} '
          'path=${source.path.join('/')} kind=scalars -->')
      ..writeln('| ключ | значение | что это |')
      ..writeln('|---|---|---|');

    for (final cell in row.cells) {
      final about = row.notes[cell.path] ?? '';
      buffer.writeln('| `${cell.path}` | ${_format(cell.value)} '
          '| ${_escape(about)} |');
    }
  }

  /// Список сущностей. Общие для большинства числа идут широкой таблицей —
  /// её и читают, сравнивая мобов между собой; редкие уходят в длинную, где
  /// у каждого числа своя строка.
  static void _renderEntities(
      StringBuffer buffer, _Source source, List<_Row> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      for (final cell in row.cells) {
        counts[cell.path] = (counts[cell.path] ?? 0) + 1;
      }
    }

    final common = [
      for (final entry in counts.entries)
        if (entry.value * 2 >= rows.length) entry.key,
    ];
    // Широкая таблица шире восьми колонок на телефоне уезжает вбок целиком.
    final wide = common.length <= 8 ? common : const <String>[];
    final rest = [
      for (final path in counts.keys)
        if (!wide.contains(path)) path,
    ];

    if (wide.isNotEmpty) {
      buffer
        ..writeln('<!-- balance: file=${source.file} '
            'path=${source.path.join('/')} kind=wide -->')
        ..writeln('| id | название | ${wide.map((p) => '`$p`').join(' | ')} |')
        ..writeln('|---|---|${wide.map((_) => '---').join('|')}|');

      for (final row in rows) {
        final cells = [
          for (final path in wide)
            _format(row.valueOf(path)),
        ];
        buffer.writeln(
            '| `${row.id}` | ${_escape(row.name)} | ${cells.join(' | ')} |');
      }
      buffer.writeln();
    }

    if (rest.isEmpty) return;

    if (wide.isNotEmpty) {
      buffer
        ..writeln('Остальные числа:')
        ..writeln();
    }

    buffer
      ..writeln('<!-- balance: file=${source.file} '
          'path=${source.path.join('/')} kind=long -->')
      ..writeln('| id | название | параметр | значение |')
      ..writeln('|---|---|---|---|');

    for (final row in rows) {
      for (final cell in row.cells) {
        if (!rest.contains(cell.path)) continue;
        buffer.writeln('| `${row.id}` | ${_escape(row.name)} '
            '| `${cell.path}` | ${_format(cell.value)} |');
      }
    }
  }

  // --- Применение ------------------------------------------------------------

  /// Таблицы → JSON.
  static ApplyReport apply({required bool dryRun, String root = '.'}) {
    final content = _readAll(root);
    final changes = <String>[];
    final errors = <String>[];
    final touched = <String>{};

    for (final sheet in _sheets) {
      final file = File('$root/$dir/${sheet.name}.md');
      if (!file.existsSync()) {
        errors.add('нет файла таблиц ${sheet.name}.md — соберите `--export`');
        continue;
      }
      _parseSheet(
        file.readAsStringSync(),
        where: '${sheet.name}.md',
        content: content,
        changes: changes,
        errors: errors,
        touched: touched,
      );
    }

    if (errors.isEmpty) {
      // Проверка ЦЕЛИКОМ и до записи: контент связный, и «броня −5» ломает
      // не свою строку, а загрузку игры. Загрузчик копит замечания и бросает
      // их пачкой — здесь они и превращаются в список ошибок.
      try {
        ContentPack.parse(content);
      } on ContentException catch (e) {
        for (final issue in e.issues) {
          errors.add('контент не проходит проверку: $issue');
        }
      }
    }

    if (errors.isEmpty && !dryRun && changes.isNotEmpty) {
      for (final name in touched) {
        _writeJson('$root/$contentDir/$name.json', content[name]);
      }
    }

    return ApplyReport(changes: changes, errors: errors, dryRun: dryRun);
  }

  static final _marker = RegExp(
      r'<!--\s*balance:\s*file=(\S+)\s+path=(\S+)\s+kind=(\S+)\s*-->');

  static void _parseSheet(
    String text, {
    required String where,
    required Map<String, Object?> content,
    required List<String> changes,
    required List<String> errors,
    required Set<String> touched,
  }) {
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final match = _marker.firstMatch(lines[i]);
      if (match == null) continue;

      final file = match.group(1)!;
      final path = match.group(2)!.split('/');
      final kind = match.group(3)!;

      // Заголовок таблицы и разделитель — следующие две строки; дальше идут
      // строки данных, пока не кончится таблица.
      var j = i + 1;
      if (j >= lines.length || !lines[j].trimLeft().startsWith('|')) continue;
      final header = _cells(lines[j]);
      j += 2;

      for (; j < lines.length; j++) {
        final line = lines[j];
        if (!line.trimLeft().startsWith('|')) break;

        final cells = _cells(line);
        _applyRow(
          where: '$where:${j + 1}',
          file: file,
          path: path,
          kind: kind,
          header: header,
          cells: cells,
          content: content,
          changes: changes,
          errors: errors,
          touched: touched,
        );
      }
      i = j - 1;
    }
  }

  static void _applyRow({
    required String where,
    required String file,
    required List<String> path,
    required String kind,
    required List<String> header,
    required List<String> cells,
    required Map<String, Object?> content,
    required List<String> changes,
    required List<String> errors,
    required Set<String> touched,
  }) {
    final json = content[file];
    if (json == null) {
      errors.add('$where: нет файла контента «$file»');
      return;
    }

    void set(Map<String, Object?> target, String leaf, String raw, String label) {
      if (raw.isEmpty) return;

      final current = _leafOf(target, leaf);
      if (current == null) {
        errors.add('$where: у «$label» нет параметра `$leaf`. '
            'Новые параметры добавляются в JSON, а не в таблице.');
        return;
      }

      final parsed = _parse(raw, current);
      if (parsed == null) {
        errors.add('$where: «$raw» — не число (`$leaf`, $label)');
        return;
      }
      if (_same(current, parsed)) return;

      _setLeaf(target, leaf, parsed);
      touched.add(file);
      changes.add('$file · $label · $leaf: '
          '${_format(current)} → ${_format(parsed)}');
    }

    switch (kind) {
      case 'scalars':
        if (cells.length < 2) return;
        final section = _walk(json, path);
        if (section is! Map<String, Object?>) {
          errors.add('$where: путь «${path.join('/')}» не словарь');
          return;
        }
        set(section, _bare(cells[0]), cells[1].trim(), path.join('/'));

      case 'wide':
        if (cells.length < 3) return;
        final id = _bare(cells[0]);
        final entity = _findById(json, path, id);
        if (entity == null) {
          errors.add('$where: не нашёл «$id» в ${path.join('/')}');
          return;
        }
        for (var c = 2; c < cells.length && c < header.length; c++) {
          set(entity, _bare(header[c]), cells[c].trim(), '$id');
        }

      case 'long':
        if (cells.length < 4) return;
        final id = _bare(cells[0]);
        final entity = _findById(json, path, id);
        if (entity == null) {
          errors.add('$where: не нашёл «$id» в ${path.join('/')}');
          return;
        }
        set(entity, _bare(cells[2]), cells[3].trim(), '$id');

      default:
        errors.add('$where: неизвестный вид таблицы «$kind»');
    }
  }

  // --- Чтение контента -------------------------------------------------------

  static Map<String, Object?> _readAll(String root) {
    final files = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      final file = File('$root/$contentDir/$name.json');
      if (!file.existsSync()) continue;
      files[name] = jsonDecode(file.readAsStringSync());
    }
    return files;
  }

  static void _writeJson(String path, Object? json) {
    const encoder = JsonEncoder.withIndent('  ');
    File(path).writeAsStringSync('${encoder.convert(json)}\n');
  }

  /// Строки одной таблицы: сущности списка или единственная «строка» из
  /// словаря чисел.
  static List<_Row> _collect(Map<String, Object?> content, _Source source) {
    final json = content[source.file];
    if (json == null) return const [];

    final node = _walk(json, source.path);

    if (node is Map<String, Object?>) {
      final cells = <_Cell>[];
      final notes = <String, String>{};
      _flatten(node, '', cells);
      for (final entry in node.entries) {
        // «_итогоComment» рядом с «итого» — это и есть пояснение к числу.
        if (!entry.key.startsWith('_') || !entry.key.endsWith('Comment')) {
          continue;
        }
        final key = entry.key.substring(1, entry.key.length - 'Comment'.length);
        final value = entry.value;
        if (value is String) {
          notes[_lowerFirst(key)] = value;
        }
      }
      return [_Row(id: source.path.last, name: '', cells: cells, notes: notes)];
    }

    final entities = _entities(json, source.path);
    return [
      for (final entity in entities)
        if (entity['id'] is String)
          () {
            final cells = <_Cell>[];
            _flatten(entity, '', cells);
            return _Row(
              id: entity['id'] as String,
              name: (entity['ru'] ?? entity['name'] ?? '') as String,
              cells: cells,
              notes: const {},
            );
          }(),
    ];
  }

  static Object? _walk(Object? json, List<String> path) {
    Object? node = json;
    for (final key in path) {
      if (node is Map<String, Object?>) {
        node = node[key];
      } else {
        return null;
      }
    }
    return node;
  }

  /// Все сущности по пути. Путь может проходить через список: у древа Эха
  /// узлы лежат внутри ветвей (`branches` → `nodes`).
  static List<Map<String, Object?>> _entities(
      Object? json, List<String> path) {
    var nodes = <Object?>[json];
    for (final key in path) {
      final next = <Object?>[];
      for (final node in nodes) {
        if (node is Map<String, Object?>) {
          final child = node[key];
          if (child is List) {
            next.addAll(child);
          } else if (child != null) {
            next.add(child);
          }
        } else if (node is List) {
          for (final item in node) {
            if (item is Map<String, Object?> && item[key] is List) {
              next.addAll(item[key] as List);
            }
          }
        }
      }
      nodes = next;
    }
    return [
      for (final node in nodes)
        if (node is Map<String, Object?>) node,
    ];
  }

  static Map<String, Object?>? _findById(
      Object? json, List<String> path, String id) {
    for (final entity in _entities(json, path)) {
      if (entity['id'] == id) return entity;
    }
    return null;
  }

  /// Числа сущности с путями до них. Списки чисел остаются одной клеткой:
  /// «25, 40, 55» правится глазами, а `brandUnlockDepths.0` — нет.
  static void _flatten(
      Map<String, Object?> node, String prefix, List<_Cell> out) {
    for (final entry in node.entries) {
      final key = entry.key;
      if (key.startsWith('_') || _skip.contains(key)) continue;

      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;

      if (value is num && value is! bool) {
        out.add(_Cell(path, value));
      } else if (value is Map<String, Object?>) {
        _flatten(value, path, out);
      } else if (value is List && value.isNotEmpty && value.every((v) => v is num)) {
        out.add(_Cell(path, List<num>.from(value)));
      }
    }
  }

  static Object? _leafOf(Map<String, Object?> entity, String path) {
    Object? node = entity;
    final parts = path.split('.');
    for (var i = 0; i < parts.length; i++) {
      if (node is! Map<String, Object?>) return null;
      node = node[parts[i]];
    }
    if (node is num) return node;
    if (node is List && node.every((v) => v is num)) return node;
    return null;
  }

  static void _setLeaf(Map<String, Object?> entity, String path, Object value) {
    final parts = path.split('.');
    Object? node = entity;
    for (var i = 0; i < parts.length - 1; i++) {
      node = (node! as Map<String, Object?>)[parts[i]];
    }
    (node! as Map<String, Object?>)[parts.last] = value;
  }

  // --- Числа -----------------------------------------------------------------

  /// Разбирает клетку, СОХРАНЯЯ тип: где в контенте целое — там и останется
  /// целое. «Волн на этаже 3.0» контент не примет, а молча округлять число,
  /// которое человек написал руками, — худший из возможных ответов.
  static Object? _parse(String raw, Object current) {
    final text = raw
        .replaceAll('`', '')
        .replaceAll('−', '-')
        .replaceAll(' ', ' ')
        .trim();

    if (current is List) {
      final parts = text.split(',');
      final out = <num>[];
      for (final part in parts) {
        final value = _number(part.trim(), integer: current.every((v) => v is int));
        if (value == null) return null;
        out.add(value);
      }
      return out;
    }

    return _number(text.replaceAll(',', '.'), integer: current is int);
  }

  static num? _number(String text, {required bool integer}) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null) return null;
    if (!integer) return value;
    if (value != value.roundToDouble()) return null;
    return value.round();
  }

  static bool _same(Object a, Object b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if ((a[i] as num) != (b[i] as num)) return false;
      }
      return true;
    }
    return a is num && b is num && a == b;
  }

  static String _format(Object? value) {
    if (value == null) return '';
    if (value is List) return value.map(_format).join(', ');
    if (value is int) return '$value';
    if (value is double) {
      // «30» вместо «30.0»: тип сохраняется при записи, а в таблице лишний
      // ноль только мешает читать столбец.
      if (value == value.roundToDouble() && value.abs() < 1e15) {
        return '${value.round()}';
      }
      return '$value';
    }
    return '$value';
  }

  static List<String> _cells(String line) {
    var text = line.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|')) text = text.substring(0, text.length - 1);
    return text.split('|').map((c) => c.trim()).toList();
  }

  static String _bare(String cell) => cell.replaceAll('`', '').trim();

  /// Труба внутри клетки разорвала бы таблицу.
  static String _escape(String text) => text.replaceAll('|', '\\|').trim();

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
}

class _Row {
  _Row({
    required this.id,
    required this.name,
    required this.cells,
    required this.notes,
  });

  final String id;
  final String name;
  final List<_Cell> cells;

  /// Пояснения к ключам — для разделов `balance.json`.
  final Map<String, String> notes;

  bool get isScalars => name.isEmpty;

  Object? valueOf(String path) {
    for (final cell in cells) {
      if (cell.path == path) return cell.value;
    }
    return null;
  }
}
