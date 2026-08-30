// Зеркалирует ../assets/content -> app/assets/content.
//
// Источник истины — контент в корневом пакете `rift`: его читают юнит-тесты
// и балансировщик `tool/sim_cli.dart`, которым Flutter не нужен. Flutter же
// не разрешает объявлять ассеты выше корня пакета, поэтому единственный
// честный вариант без раздвоения источника — копия, собираемая скриптом.
//
//   dart run tool/sync_content.dart
//
// Скрипт идемпотентен: файлы с совпадающим содержимым не перезаписываются.
import 'dart:io';

void main(List<String> args) {
  final src = Directory('../assets/content');
  final dst = Directory('assets/content');

  if (!src.existsSync()) {
    stderr.writeln('Нет каталога ${src.path}. Запускать из app/.');
    exitCode = 2;
    return;
  }
  dst.createSync(recursive: true);

  var copied = 0;
  var skipped = 0;
  final seen = <String>{};

  for (final entity in src.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final name = entity.uri.pathSegments.last;
    seen.add(name);

    final target = File('${dst.path}/$name');
    final bytes = entity.readAsBytesSync();
    if (target.existsSync() &&
        _sameBytes(target.readAsBytesSync(), bytes)) {
      skipped++;
      continue;
    }
    target.writeAsBytesSync(bytes);
    copied++;
  }

  // Удаляем осиротевшие копии: иначе переименование файла в источнике
  // оставляет в сборке старую версию, и APK живёт с контентом-призраком.
  var removed = 0;
  for (final entity in dst.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name.endsWith('.json') && !seen.contains(name)) {
      entity.deleteSync();
      removed++;
    }
  }

  stdout.writeln('content: +$copied  =$skipped  -$removed');
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
