import 'dart:convert';
import 'dart:io';

import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/text_overlay.dart';
import 'package:rift/core/model/lang.dart';

/// Чтение контента с диска для тестов и балансировщика.
///
/// Живёт вне `lib/core` намеренно: `dart:io` в ядре закрыл бы веб и притащил
/// платформенную зависимость туда, где её быть не должно. В приложении ту же
/// роль играет `rootBundle` (`app/lib/data/content.dart`).
ContentPack loadContentFromDisk({
  String dir = 'assets/content',
  Lang lang = Lang.ru,
}) =>
    ContentPack.parse(readContentJson(dir: dir, lang: lang));

/// Сырые JSON без разбора — нужны тестам, которые ломают контент нарочно.
///
/// [lang] накладывает перевод на прочитанное. Русский — язык оригинала, для
/// него накладки нет и читать нечего.
Map<String, Object?> readContentJson({
  String dir = 'assets/content',
  Lang lang = Lang.ru,
}) {
  final files = <String, Object?>{};
  for (final name in ContentPack.fileNames) {
    final file = File('$dir/$name.json');
    if (!file.existsSync()) continue;
    files[name] = jsonDecode(file.readAsStringSync());
  }
  if (lang == Lang.ru) return files;
  return TextOverlay.applyAll(files, readOverlays(dir: dir, lang: lang));
}

/// Накладки перевода: `имя файла -> накладка`.
///
/// Отсутствующий файл — не ошибка, а «эта часть контента ещё не переведена»:
/// она покажется по-русски. Перевод доезжает по частям, и игра не должна
/// ждать, пока он дойдёт до конца.
Map<String, TextOverlay> readOverlays({
  String dir = 'assets/content',
  required Lang lang,
}) {
  final out = <String, TextOverlay>{};
  for (final name in ContentPack.fileNames) {
    final file = File('$dir/${lang.code}/$name.json');
    if (!file.existsSync()) continue;
    out[name] = TextOverlay.fromJson(jsonDecode(file.readAsStringSync()));
  }
  return out;
}
