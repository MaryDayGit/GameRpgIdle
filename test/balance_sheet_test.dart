import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/balance_sheet.dart';

/// Балансовые таблицы — единственное место, где числа игры можно править не
/// за рабочим столом. Значит проверять надо не «файл собрался», а три вещи,
/// каждая из которых по-своему делает эту затею вредной:
///
/// * **таблицы = контент.** Разойдись они хоть на одно число — и правка
///   вслепую меняет не то, что человек видел на экране телефона;
/// * **правка доезжает.** Иначе это красивый отчёт, а не инструмент;
/// * **опечатка не проходит.** С телефона правят одним пальцем в дороге, и
///   «0,6» вместо «0.6», лишняя буква или сломанное правило контента обязаны
///   останавливать запись ЦЕЛИКОМ. Наполовину применённый баланс хуже
///   неприменённого: его никто не заметит.
void main() {
  late Directory root;

  /// Копия проекта: только то, что нужно таблицам. Тест правит контент, и
  /// делать это в рабочем дереве нельзя.
  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_balance_sheet');
    final target = Directory('${root.path}/assets/content')
      ..createSync(recursive: true);
    for (final file in Directory('assets/content').listSync()) {
      if (file is File) {
        file.copySync('${target.path}/${file.uri.pathSegments.last}');
      }
    }
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows держит дескрипторы дольше, чем идёт тест. Мусор во временной
      // папке — не повод валить проверку.
    }
  });

  String sheet(String name) =>
      File('${root.path}/balance/$name.md').readAsStringSync();

  void writeSheet(String name, String text) =>
      File('${root.path}/balance/$name.md').writeAsStringSync(text);

  Map<String, Object?> content(String name) =>
      jsonDecode(File('${root.path}/assets/content/$name.json')
          .readAsStringSync()) as Map<String, Object?>;

  Object? enemyField(String id, String field) {
    final enemies = content('enemies')['enemies']! as List;
    return (enemies.firstWhere((e) => (e as Map)['id'] == id)
        as Map<String, Object?>)[field];
  }

  test('таблицы собираются из контента и сходятся с ним', () {
    // Если сразу после сборки инструмент видит расхождение, значит одна из
    // сторон врёт — и какая именно, игрок узнает уже по сломанному балансу.
    BalanceSheet.export(root: root.path);

    final report = BalanceSheet.apply(dryRun: true, root: root.path);
    expect(report.errors, isEmpty);
    expect(report.changes, isEmpty,
        reason: 'только что собранные таблицы обязаны совпадать с контентом');
  });

  test('правка в клетке доезжает до JSON', () {
    BalanceSheet.export(root: root.path);
    expect(enemyField('scavenger', 'hpMult'), 0.6);

    writeSheet(
      '02-enemies',
      sheet('02-enemies')
          .replaceFirst('| `scavenger` | Падальщик | 0.6 |',
              '| `scavenger` | Падальщик | 0.75 |'),
    );

    final report = BalanceSheet.apply(dryRun: false, root: root.path);
    expect(report.errors, isEmpty);
    expect(report.changes, hasLength(1));
    expect(report.changes.single, contains('hpMult'));
    expect(enemyField('scavenger', 'hpMult'), 0.75);

    // Соседи не пострадали: правится ровно одна клетка, а не весь файл.
    expect(enemyField('bonebreaker', 'hpMult'), 1.8);
  });

  test('целое остаётся целым', () {
    // «Волн на этаже 3.0» контент не примет, а молча округлить число, которое
    // человек написал руками, — худший из возможных ответов: он увидит одно,
    // а получит другое.
    BalanceSheet.export(root: root.path);

    writeSheet(
      '02-enemies',
      sheet('02-enemies').replaceFirst(
          '| `scavenger` | Падальщик | 0.6 | 0.25 | 1.4 | 0 | 3 | 5 | 30 |',
          '| `scavenger` | Падальщик | 0.6 | 0.25 | 1.4 | 0 | 4 | 5 | 30 |'),
    );

    final report = BalanceSheet.apply(dryRun: false, root: root.path);
    expect(report.errors, isEmpty);
    expect(enemyField('scavenger', 'packMin'), 4);
    expect(enemyField('scavenger', 'packMin'), isA<int>(),
        reason: 'целое поле обязано остаться целым');
  });

  test('запятая как дробная точка понимается', () {
    // Русская раскладка на телефоне даёт запятую. Отказ на этом месте
    // превращает инструмент в загадку.
    BalanceSheet.export(root: root.path);

    writeSheet(
      '02-enemies',
      sheet('02-enemies').replaceFirst('| `scavenger` | Падальщик | 0.6 |',
          '| `scavenger` | Падальщик | 0,8 |'),
    );

    BalanceSheet.apply(dryRun: false, root: root.path);
    expect(enemyField('scavenger', 'hpMult'), 0.8);
  });

  group('порча не проходит', () {
    test('опечатка отменяет ВСЕ правки, а не свою строку', () {
      BalanceSheet.export(root: root.path);

      writeSheet(
        '02-enemies',
        sheet('02-enemies')
            // Правильная правка — она обязана НЕ примениться вместе с плохой.
            .replaceFirst('| `bonebreaker` | Костолом | 1.8 |',
                '| `bonebreaker` | Костолом | 2.1 |')
            .replaceFirst('| `scavenger` | Падальщик | 0.6 |',
                '| `scavenger` | Падальщик | много |'),
      );

      final report = BalanceSheet.apply(dryRun: false, root: root.path);
      expect(report.errors, isNotEmpty);
      expect(report.errors.first, contains('много'));
      expect(enemyField('scavenger', 'hpMult'), 0.6);
      expect(enemyField('bonebreaker', 'hpMult'), 1.8,
          reason: 'половина применённых правок — худший исход из возможных');
    });

    test('число, ломающее правило контента, не пишется', () {
      // Ноль в множителе HP — это враг, которого нельзя убить или который
      // мёртв на месте. Загрузчик такое ловит, и таблицы обязаны спрашивать
      // у него, а не только у себя.
      BalanceSheet.export(root: root.path);

      writeSheet(
        '02-enemies',
        sheet('02-enemies').replaceFirst('| `scavenger` | Падальщик | 0.6 |',
            '| `scavenger` | Падальщик | 0 |'),
      );

      final report = BalanceSheet.apply(dryRun: false, root: root.path);
      expect(report.errors, isNotEmpty);
      expect(report.errors.first, contains('проверку'));
      expect(enemyField('scavenger', 'hpMult'), 0.6);
    });

    test('несуществующий параметр назван, а не проглочен', () {
      BalanceSheet.export(root: root.path);

      writeSheet(
        '02-enemies',
        '${sheet('02-enemies')}\n'
            '<!-- balance: file=enemies path=enemies kind=long -->\n'
            '| id | название | параметр | значение |\n'
            '|---|---|---|---|\n'
            '| `scavenger` | Падальщик | `ловкость` | 7 |\n',
      );

      final report = BalanceSheet.apply(dryRun: false, root: root.path);
      expect(report.errors, isNotEmpty);
      expect(report.errors.first, contains('ловкость'));
    });
  });

  test('заметки вокруг таблиц и переставленные строки ничего не ломают', () {
    // Файл живёт у человека в телефоне: он будет дописывать в него мысли и
    // тасовать строки. Якорь — id и путь параметра, а не место в файле.
    BalanceSheet.export(root: root.path);

    final lines = sheet('02-enemies').split('\n');
    final scavenger =
        lines.indexWhere((l) => l.startsWith('| `scavenger` | Падальщик |'));
    final bonebreaker =
        lines.indexWhere((l) => l.startsWith('| `bonebreaker` | Костолом |'));
    expect(scavenger, lessThan(bonebreaker));

    final row = lines.removeAt(scavenger);
    lines.insert(bonebreaker, row.replaceFirst('| 0.6 |', '| 0.9 |'));
    writeSheet('02-enemies', '${lines.join('\n')}\n\nСюда я пишу мысли.\n');

    final report = BalanceSheet.apply(dryRun: false, root: root.path);
    expect(report.errors, isEmpty);
    expect(enemyField('scavenger', 'hpMult'), 0.9);
  });

  test('проверка ничего не пишет', () {
    BalanceSheet.export(root: root.path);

    writeSheet(
      '02-enemies',
      sheet('02-enemies').replaceFirst('| `scavenger` | Падальщик | 0.6 |',
          '| `scavenger` | Падальщик | 0.9 |'),
    );

    final report = BalanceSheet.apply(dryRun: true, root: root.path);
    expect(report.changes, hasLength(1));
    expect(enemyField('scavenger', 'hpMult'), 0.6,
        reason: '`--check` обязан быть безопасным');
  });
}
