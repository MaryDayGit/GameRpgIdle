import 'dart:convert';
import 'dart:io';

import 'package:rift/core/content/content_pack.dart';

/// Чтение контента с диска для тестов и балансировщика.
///
/// Живёт вне `lib/core` намеренно: `dart:io` в ядре закрыл бы веб и притащил
/// платформенную зависимость туда, где её быть не должно. В приложении ту же
/// роль играет `rootBundle` (`app/lib/data/content.dart`).
ContentPack loadContentFromDisk({String dir = 'assets/content'}) {
  final files = <String, Object?>{};
  for (final name in ContentPack.fileNames) {
    final file = File('$dir/$name.json');
    if (!file.existsSync()) continue;
    files[name] = jsonDecode(file.readAsStringSync());
  }
  return ContentPack.parse(files);
}

/// Сырые JSON без разбора — нужны тестам, которые ломают контент нарочно.
Map<String, Object?> readContentJson({String dir = 'assets/content'}) {
  final files = <String, Object?>{};
  for (final name in ContentPack.fileNames) {
    final file = File('$dir/$name.json');
    if (!file.existsSync()) continue;
    files[name] = jsonDecode(file.readAsStringSync());
  }
  return files;
}
