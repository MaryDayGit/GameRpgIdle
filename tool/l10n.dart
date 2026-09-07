import 'dart:convert';
import 'dart:io';

import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/text_overlay.dart';

import 'content_io.dart';

/// Инструмент перевода контента.
///
/// Тексты контента лежат в `assets/content/*.json` вперемешку с числами
/// баланса, и это правильно (см. `text_overlay.dart`). Переводы лежат
/// отдельно — `assets/content/<язык>/<файл>.json`, — и этот инструмент их
/// заводит, обновляет и считает.
///
///   dart run tool/l10n.dart --extract      завести/обновить лист перевода
///   dart run tool/l10n.dart --check        сколько ещё не переведено
///
/// Лист перевода заводится ЗАСЕЯННЫМ русским текстом, а не пустым. Пустое
/// поле пришлось бы держать в голове рядом с исходником в другом файле;
/// засеянное — рабочий лист, где исходник и перевод стоят рядом. Строка,
/// совпадающая с исходником, и считается непереведённой: отдельного признака
/// «готово» нет, потому что он рассинхронизировался бы с текстом при первой
/// же правке русского оригинала.
void main(List<String> args) {
  final mode = args.isEmpty ? '--help' : args.first;
  final lang = _optionValue(args, '--lang') ?? 'en';

  switch (mode) {
    case '--extract':
      _extract(lang);
    case '--check':
      exit(_check(lang) ? 0 : 1);
    default:
      stdout.writeln(_help);
  }
}

const _help = '''
Перевод контента «Расселины».

  dart run tool/l10n.dart --extract [--lang en]
      Заводит и обновляет assets/content/<lang>/*.json. Уже переведённые
      строки не трогает; новые записи контента добавляет засеянными русским
      текстом; записи, которых в контенте больше нет, убирает.

  dart run tool/l10n.dart --check [--lang en]
      Печатает, сколько строк переведено, а сколько ещё совпадает с русским
      оригиналом. Код возврата 1, если перевод неполон, — годится для CI.
''';

String? _optionValue(List<String> args, String name) {
  final at = args.indexOf(name);
  return at >= 0 && at + 1 < args.length ? args[at + 1] : null;
}

/// Одна переводимая строка: где лежит и что в ней написано по-русски.
typedef Sheet = Map<String, Map<String, String>>;

/// Собирает переводимые строки одного файла контента.
///
/// Обход тот же, что в [TextOverlay]: любая карта с опознаваемым ключом и
/// переводимым полем — запись. Держать здесь второе, независимое описание
/// формы контента нельзя: разойдясь, оно молча перестало бы находить часть
/// строк, и они бы просто остались непереведёнными без единого сообщения.
Sheet _collect(Object? node, {List<String>? duplicates}) {
  final out = <String, Map<String, String>>{};

  void walk(Object? n) {
    if (n is List) {
      for (final item in n) {
        walk(item);
      }
      return;
    }
    if (n is! Map) return;

    for (final value in n.values) {
      walk(value);
    }

    final key = entryKey(n.cast<Object?, Object?>());
    if (key == null) return;

    final strings = <String, String>{};
    for (final field in translatableFields) {
      final value = n[field];
      // Только строки: `_comment` бывает списком, а `about` у ветки древа —
      // строкой. Список комментариев автора переводить незачем.
      if (value is String && value.isNotEmpty) {
        strings[field == 'ru' ? 'name' : field] = value;
      }
    }
    if (strings.isEmpty) return;

    if (out.containsKey(key) && out[key].toString() != strings.toString()) {
      duplicates?.add(key);
    }
    out[key] = strings;
  }

  walk(node);
  return out;
}

void _extract(String lang) {
  final source = readContentJson();
  final dir = Directory('assets/content/$lang');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  var added = 0;
  var dropped = 0;
  var kept = 0;

  for (final name in ContentPack.fileNames) {
    final raw = source[name];
    if (raw == null) continue;

    final duplicates = <String>[];
    final wanted = _collect(raw, duplicates: duplicates);
    if (duplicates.isNotEmpty) {
      stderr.writeln('ВНИМАНИЕ $name.json: один идентификатор на разные '
          'строки — ${duplicates.toSet().join(', ')}. Накладка переведёт их '
          'одинаково.');
    }
    if (wanted.isEmpty) continue;

    final file = File('assets/content/$lang/$name.json');
    final existing = file.existsSync()
        ? TextOverlay.fromJson(jsonDecode(file.readAsStringSync())).entries
        : const <String, Map<String, String>>{};

    final merged = <String, Map<String, String>>{};
    for (final entry in wanted.entries) {
      final was = existing[entry.key] ?? const <String, String>{};
      final fields = <String, String>{};
      for (final field in entry.value.entries) {
        final translated = was[field.key];
        // Уже переведённое поле остаётся как есть. Русское значение
        // подставляется только там, где перевода ещё нет: перезаписать
        // готовый перевод исходником значит потерять работу молча.
        if (translated != null) {
          fields[field.key] = translated;
          kept++;
        } else {
          fields[field.key] = field.value;
          added++;
        }
      }
      merged[entry.key] = fields;
    }
    dropped += existing.keys.where((k) => !wanted.containsKey(k)).length;

    file.writeAsStringSync(_encode(lang, name, merged));
  }

  stdout.writeln('Лист перевода $lang: сохранено переводов $kept, '
      'заведено новых строк $added, убрано записей вне контента $dropped.');
  stdout.writeln('Файлы: assets/content/$lang/');
}

bool _check(String lang) {
  final source = readContentJson();
  var total = 0;
  var done = 0;
  final gaps = <String, int>{};

  for (final name in ContentPack.fileNames) {
    final raw = source[name];
    if (raw == null) continue;

    final wanted = _collect(raw);
    if (wanted.isEmpty) continue;

    final file = File('assets/content/$lang/$name.json');
    final overlay = file.existsSync()
        ? TextOverlay.fromJson(jsonDecode(file.readAsStringSync())).entries
        : const <String, Map<String, String>>{};

    var fileGap = 0;
    for (final entry in wanted.entries) {
      for (final field in entry.value.entries) {
        total++;
        final translated = overlay[entry.key]?[field.key];
        // Совпало с русским — значит, до этой строки ещё не дошли. Признак
        // выводится, а не хранится: хранимый «переведено» разошёлся бы с
        // текстом при первой правке оригинала и врал бы в обе стороны.
        //
        // Кроме одного случая: строка, в которой вне плейсхолдеров нет ни
        // одной буквы («+{value:%} {tag}»), на всех языках одинакова. Требовать
        // её «перевести» значит вечно держать в отчёте пять строк, с которыми
        // ничего нельзя сделать, — и приучить не смотреть в отчёт.
        if (!_needsTranslation(field.value) ||
            (translated != null && translated != field.value)) {
          done++;
        } else {
          fileGap++;
        }
      }
    }
    if (fileGap > 0) gaps[name] = fileGap;
  }

  final percent = total == 0 ? 100 : (done * 100 / total).floor();
  stdout.writeln('Перевод $lang: $done из $total строк ($percent %).');
  if (gaps.isNotEmpty) {
    stdout.writeln('Осталось:');
    final sorted = gaps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final gap in sorted) {
      stdout.writeln('  ${gap.value.toString().padLeft(5)}  ${gap.key}.json');
    }
  }
  stdout.writeln(done == total ? 'L10N-$lang: OK' : 'L10N-$lang: НЕПОЛНО');
  return done == total;
}

/// Есть ли в строке что переводить.
///
/// Шаблон целиком из плейсхолдеров и знаков — «+{value:%} {tag}» — на всех
/// языках выглядит одинаково: слова в него подставляет [Tag.damage], и они
/// уже переведены в ядре. Такая строка не «ждёт перевода», она готова.
final _placeholder = RegExp(r'\{[^}]*\}');
final _letter = RegExp(r'\p{L}', unicode: true);

bool _needsTranslation(String source) =>
    _letter.hasMatch(source.replaceAll(_placeholder, ''));

/// Записывает накладку читаемо и устойчиво к diff: ключи по алфавиту, отступ
/// в два пробела. Файл правится руками и живёт в git — порядок ключей в нём
/// не должен зависеть от порядка обхода.
String _encode(String lang, String name, Sheet sheet) {
  final keys = sheet.keys.toList()..sort();
  final entries = <String, Object?>{
    for (final key in keys) key: sheet[key],
  };
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({
        'version': 1,
        '_comment': 'Перевод $name.json на $lang. Числа и правила остаются в '
            'исходнике; здесь только строки. Строка, совпадающая с русской, '
            'считается непереведённой — см. tool/l10n.dart --check.',
        'entries': entries,
      })}\n';
}
