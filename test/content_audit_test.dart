import 'dart:io';

import 'package:rift/core/content/affix_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/gear.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Каждый аффикс и каждая способность обязаны МЕНЯТЬ ИСХОД боя.
///
/// Этот проект уже трижды находил обратное: множитель «+% к урону с тегом»,
/// который не читала ни одна строка; обещание реликта, доезжавшее из контента
/// до правил и дальше никуда; запрет реликта, который знала симуляция и не
/// знал экран. Общее у всех трёх одно — содержимое выглядело рабочим, пока
/// его никто не прогонял.
///
/// Здесь проверяется не число, а вердикт: `audit_cli` прогоняет два
/// одинаковых боя, отличающихся только проверяемой вещью, и сравнивает
/// отпечаток с порогом собственного шума. Ловится ровно то, что тесты
/// отдельных механик не ловят по определению: контент, который добавили, а
/// подключить забыли.
void main() {
  Future<String> audit(String mode) async {
    final result = await Process.run(
      'dart',
      ['run', 'tool/audit_cli.dart', mode],
      workingDirectory: Directory.current.path,
    );
    expect(result.exitCode, 0,
        reason: 'audit_cli $mode упал:\n${result.stdout}\n${result.stderr}');
    return '${result.stdout}';
  }

  // Вердикт ищется латиницей намеренно: на Windows дочерний процесс отдаёт
  // вывод в кодировке консоли, и проверка, ловившая русскую фразу, падала на
  // кракозябрах при полностью исправном аудите.
  test('каждый аффикс доезжает с предмета до боя', () async {
    expect(await audit('--affixes'), contains('AUDIT-AFFIXES: OK'),
        reason: 'аффикс, которого не видно в бою, — строчка в описании '
            'предмета и ничего больше. Запустите '
            '`dart run tool/audit_cli.dart --affixes`, чтобы увидеть, какой');
  }, timeout: _slow);

  test('каждая способность меняет исход боя', () async {
    expect(await audit('--abilities'), contains('AUDIT-ABILITIES: OK'),
        reason: 'способность без эффекта хуже отсутствующей: игрок тратит '
            'на неё слот и строит вокруг неё сборку. Запустите '
            '`dart run tool/audit_cli.dart --abilities`');
  }, timeout: _slow);

  test('каждый реликт меняет исход', () async {
    expect(await audit('--relics'), contains('AUDIT-RELICS: OK'),
        reason: 'реликт — это правило, и правило без ветки в симуляции '
            'выглядит рабочим ровно до тех пор, пока его никто не прогонит. '
            'Запустите `dart run tool/audit_cli.dart --relics`');
  }, timeout: _slow);

  test('бестиарий: каждая повадка меняет бой, каждая стихия представлена',
      () async {
    expect(await audit('--enemies'), contains('AUDIT-ENEMIES: OK'),
        reason: 'у героя пять сопротивлений, и если по одной из стихий его '
            'никто не бьёт, то пятая часть его защиты не проверяется ничем — '
            'а игрок за неё платит слотами и аффиксами. Запустите '
            '`dart run tool/audit_cli.dart --enemies`');
  }, timeout: _slow);

  test('перед каждым стражем есть о чём подумать', () async {
    expect(await audit('--bosses'), contains('AUDIT-BOSSES: OK'),
        reason: 'страж области — не мешок с HP, а вопрос «чем и как идти». '
            'Проверяется трижды: его ломает хотя бы одна эталонная сборка, '
            'он сдаётся хотя бы одной стихии, и его профиль не совпадает ни '
            'с одним другим стражем — иначе это один босс, надетый дважды. '
            'Запустите `dart run tool/audit_cli.dart --bosses`');
  }, timeout: _slow);

  test('у каждого тега есть и способности, и снаряжение', () async {
    final out = await audit('--tags');
    final line = out
        .split('\n')
        .firstWhere((l) => l.startsWith('AUDIT-TAGS:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'аудит тегов не дошёл до вердикта');

    // Дыр больше нет: «Аура» закрыта аффиксом «+% к силе Аур» и проверяется
    // не уроном, а величиной самой ауры.
    expect(
      line,
      contains('OK'),
      reason: 'каждый тег обязан быть закрыт с обеих сторон. Тег без '
          'способностей — слово в описании; тег без аффикса — сборка, '
          'которую нечем усиливать. Строка: «$line»',
    );
  }, timeout: _slow);

  test('у слота два пула, и защита с атакой вместе не живут', () {
    // Правило дизайна, а не инвариант данных: валидатор контента проверяет,
    // что `kinds` и `pools` сходятся, а вот СКОЛЬКО пулов у слота и каких —
    // решение, и его место здесь.
    //
    // Смысл правила: у слота должен быть характер. До пулов его не было ни у
    // кого — почти каждый слот роллил почти всё, и «мне нужно хорошее кольцо»
    // не значило ничего сверх «мне нужен хороший предмет».
    loadContentFromDisk().apply();

    // Два слота — исключение, и это их единственная роль: только здесь может
    // выпасть что угодно.
    const mixed = {GearKind.ring, GearKind.amulet};

    for (final slot in ContentPack.current.implicits) {
      final open = [
        for (final e in slot.pools.entries)
          if (e.value > 0) e.key,
      ];

      if (mixed.contains(slot.kind)) {
        expect(open, hasLength(3),
            reason: '${slot.kind.name} — свободный слот, у него все три пула');
        continue;
      }

      expect(open, hasLength(2),
          reason: '${slot.kind.name}: пулов ${open.length}, а должно быть два '
              '— один основной и утилита');
      expect(
        open.contains(AffixPool.offence) && open.contains(AffixPool.defence),
        isFalse,
        reason: '${slot.kind.name} принимает и атаку, и защиту. Так можно '
            'только кольцу и амулету — иначе у слота снова нет характера',
      );
    }
  });
}

/// Каждый прогон поднимает свою VM и считает сотни боёв.
const _slow = Timeout(Duration(minutes: 6));
