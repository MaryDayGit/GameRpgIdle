import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/text_overlay.dart';
import 'package:rift/core/model/lang.dart';

/// Контент приложения: сырые JSON плюс разобранный и проверенный [ContentPack].
///
/// Сырые данные держим рядом с разобранными намеренно — их придётся отправлять
/// в фоновый изолят, а [ContentPack] туда не отправить: он держит функции и
/// перечисления, и копировать его дороже, чем разобрать заново.
class ContentBundle {
  const ContentBundle({
    required this.raw,
    required this.pack,
    this.lang = Lang.ru,
  });

  /// Карта «имя файла -> результат jsonDecode», уже с наложенным переводом.
  ///
  /// Именно переведённые, а не исходные: в фоновый изолят уезжает эта карта,
  /// и разбор там обязан дать тот же текст, что видит экран. Иначе журнал
  /// спуска, посчитанный в изоляте, приехал бы на русском в английскую игру.
  final Map<String, Object?> raw;

  final ContentPack pack;

  /// На каком языке собран этот пакет. Хранится, чтобы было чем ответить на
  /// вопрос «надо ли перезагружать контент» при смене языка в настройках.
  final Lang lang;

  static Future<ContentBundle> load({Lang lang = Lang.ru}) async {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      final text = await rootBundle.loadString('assets/content/$name.json');
      raw[name] = jsonDecode(text);
    }

    final translated = lang == Lang.ru
        ? raw
        : TextOverlay.applyAll(raw, await _overlays(lang));

    return ContentBundle(
      raw: translated,
      pack: ContentPack.parse(translated),
      lang: lang,
    );
  }

  /// Накладки перевода из ассетов.
  ///
  /// Отсутствующий файл — не ошибка, а «эта часть ещё не переведена»: она
  /// покажется по-русски. Поэтому чтение обёрнуто, а не проверено заранее:
  /// у `rootBundle` нет способа спросить «есть ли такой ассет», кроме как
  /// попробовать его прочитать.
  static Future<Map<String, TextOverlay>> _overlays(Lang lang) async {
    final out = <String, TextOverlay>{};
    for (final name in ContentPack.fileNames) {
      try {
        final text =
            await rootBundle.loadString('assets/content/${lang.code}/$name.json');
        out[name] = TextOverlay.fromJson(jsonDecode(text));
      } on FlutterError {
        continue;
      }
    }
    return out;
  }

  /// Разбирает контент и применяет его к статикам ядра.
  ///
  /// ВАЖНО: статики в Dart живут в пределах изолята. Вызов в `main()` НЕ
  /// настраивает фоновый изолят — там останутся значения по умолчанию, и
  /// симуляция молча посчитает не тот баланс. Поэтому та же функция
  /// вызывается на входе в изолят (`dev/sim_runner.dart`).
  static ContentPack apply(Map<String, Object?> raw) {
    final pack = ContentPack.parse(raw);
    pack.apply();
    return pack;
  }
}
