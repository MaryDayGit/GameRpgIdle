import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:rift/core/content/content_pack.dart';

/// Контент приложения: сырые JSON плюс разобранный и проверенный [ContentPack].
///
/// Сырые данные держим рядом с разобранными намеренно — их придётся отправлять
/// в фоновый изолят, а [ContentPack] туда не отправить: он держит функции и
/// перечисления, и копировать его дороже, чем разобрать заново.
class ContentBundle {
  const ContentBundle({required this.raw, required this.pack});

  /// Карта «имя файла -> результат jsonDecode».
  final Map<String, Object?> raw;

  final ContentPack pack;

  static Future<ContentBundle> load() async {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      final text = await rootBundle.loadString('assets/content/$name.json');
      raw[name] = jsonDecode(text);
    }
    return ContentBundle(raw: raw, pack: ContentPack.parse(raw));
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
