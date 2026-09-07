import 'dart:io';

/// Зеркалит `assets/content` в `app/assets/content`.
///
/// Flutter не умеет брать ассеты выше корня пакета, поэтому клиент возит
/// копию контента. Копия — не второй источник правды: править её руками
/// нельзя, она собирается отсюда.
///
///   dart run tool/sync_content.dart            обновить зеркало
///   dart run tool/sync_content.dart --check    сверить, не расходится ли
///
/// `--check` существует потому, что расхождение зеркала не ловится ничем
/// другим до самой сборки APK: ядро считает баланс по `assets/content`, а
/// игрок играет в то, что лежит в `app/assets/content`. Однажды это уже
/// случилось — коммит a261c99 чинил зеркало отдельной правкой, руками.
void main(List<String> args) {
  final check = args.contains('--check');

  final source = Directory('assets/content');
  final mirror = Directory('app/assets/content');

  if (!source.existsSync()) {
    stderr.writeln('Нет каталога ${source.path} — запускать из корня репозитория.');
    exit(2);
  }

  final wanted = _filesIn(source);
  final present = mirror.existsSync() ? _filesIn(mirror) : <String>{};

  final differing = <String>[];
  final missing = <String>[];
  final extra = present.difference(wanted).toList()..sort();

  for (final relative in wanted) {
    final from = File('${source.path}/$relative');
    final to = File('${mirror.path}/$relative');
    if (!to.existsSync()) {
      missing.add(relative);
      continue;
    }
    // Сравниваем байты, а не длину и не дату: правка одного числа на другое
    // той же ширины не двигает ни то, ни другое.
    if (!_sameBytes(from, to)) differing.add(relative);
  }

  if (check) {
    final broken = [
      for (final f in missing) 'нет в зеркале: $f',
      for (final f in differing) 'расходится: $f',
      for (final f in extra) 'лишний в зеркале: $f',
    ];
    if (broken.isEmpty) {
      stdout.writeln('Зеркало совпадает с ${source.path} '
          '(${wanted.length} файлов).');
      stdout.writeln('SYNC-CONTENT: OK');
      return;
    }
    stdout.writeln('Зеркало разошлось с ${source.path}:');
    for (final line in broken) {
      stdout.writeln('  $line');
    }
    stdout.writeln('Починить: dart run tool/sync_content.dart');
    stdout.writeln('SYNC-CONTENT: РАСХОЖДЕНИЕ');
    exit(1);
  }

  for (final relative in wanted) {
    final to = File('${mirror.path}/$relative');
    to.parent.createSync(recursive: true);
    File('${source.path}/$relative').copySync(to.path);
  }
  for (final relative in extra) {
    File('${mirror.path}/$relative').deleteSync();
  }

  stdout.writeln('Зеркало обновлено: ${wanted.length} файлов, '
      'изменено ${missing.length + differing.length}, '
      'удалено лишних ${extra.length}.');
}

/// Пути всех `.json` относительно каталога, включая подкаталоги языков.
Set<String> _filesIn(Directory dir) {
  final prefix = '${dir.path}/';
  return {
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.json'))
        entity.path.replaceAll(r'\', '/').substring(prefix.length),
  };
}

bool _sameBytes(File a, File b) {
  final left = a.readAsBytesSync();
  final right = b.readAsBytesSync();
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
