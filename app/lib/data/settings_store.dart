import 'dart:convert';
import 'dart:io';

import 'package:rift/core/model/lang.dart';

/// Настройки приложения: язык, звук, вибрация, пройдено ли обучение.
///
/// Отдельный файл, а не поле в сейве, потому что это не состояние игры.
/// Сейв описывает Заставу и наёмников — он переживает переустановку, его
/// мигрируют версиями. Выключенный звук такой судьбы не заслуживает, и
/// хранить его вместе с профилем значило бы гонять миграцию из-за галочки.
class AppSettings {
  AppSettings({
    this.lang = Lang.ru,
    this.sound = true,
    this.haptics = true,
    this.tutorialDone = false,
    Set<String>? tutorialSeen,
  }) : tutorialSeen = tutorialSeen ?? <String>{};

  /// Язык игры.
  ///
  /// Здесь, а не в сейве, по той же причине, что и звук: это настройка
  /// устройства, а не состояние игры. Но следствие важнее — язык читается
  /// ДО контента (`GameController.boot`), потому что от него зависит, какие
  /// накладки грузить, а сейв к этому моменту ещё не открыт.
  Lang lang;

  bool sound;
  bool haptics;

  /// Обучение пройдено или пропущено. Показывать его второй раз — худшее,
  /// что можно сделать с игроком, который уже разобрался.
  ///
  /// Раньше поле поднималось сразу после вступительного окна, и означало
  /// «вступление прочитано». Теперь оно означает то, что написано: сценарий
  /// первого запуска пройден целиком или пропущен кнопкой. Старые сейвы от
  /// этого не страдают — у них поле уже `true`, и обучение к ним не лезет.
  bool tutorialDone;

  /// Шаги обучения, которые игрок уже прошёл — или которые опоздали.
  ///
  /// Множество, а не номер шага: сценарий не линеен. Игрок, разобравший
  /// добычу раньше, чем ему про неё сказали, не должен упереться в подсказку,
  /// которой нечего показать, — а с номером шага упёрся бы.
  final Set<String> tutorialSeen;

  Map<String, dynamic> toJson() => {
        'lang': lang.code,
        'sound': sound,
        'haptics': haptics,
        'tutorialDone': tutorialDone,
        'tutorialSeen': tutorialSeen.toList(),
      };

  /// Читает настройки, прощая всё. Испорченный файл настроек не повод не
  /// пустить игрока в игру: непонятое поле берётся по умолчанию.
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        // Неизвестный код языка — русский, а не отказ: файл настроек,
        // написанный будущей версией с ещё одним языком, обязан открыться.
        lang: Lang.byCode(j['lang'] is String ? j['lang'] as String : null),
        sound: j['sound'] is bool ? j['sound'] as bool : true,
        haptics: j['haptics'] is bool ? j['haptics'] as bool : true,
        tutorialDone:
            j['tutorialDone'] is bool ? j['tutorialDone'] as bool : false,
        // Незнакомый шаг не выбрасывается: файл, написанный будущей версией
        // с другим сценарием, обязан открыться, а лишний идентификатор в
        // множестве не стоит ничего.
        tutorialSeen: {
          for (final id in (j['tutorialSeen'] is List
              ? j['tutorialSeen'] as List
              : const []))
            if (id is String) id,
        },
      );
}

/// Файл настроек рядом с сейвом.
class SettingsStore {
  SettingsStore(this.directory, {this.fileName = 'rift.settings.json'});

  final Directory directory;
  final String fileName;

  File get _file => File('${directory.path}/$fileName');

  AppSettings load() {
    try {
      if (!_file.existsSync()) return AppSettings();
      final raw = jsonDecode(_file.readAsStringSync());
      if (raw is! Map) return AppSettings();
      return AppSettings.fromJson(raw.cast<String, dynamic>());
    } on Object {
      // Настройки не стоят того, чтобы из-за них не запускалась игра.
      return AppSettings();
    }
  }

  void save(AppSettings settings) {
    try {
      _file.writeAsStringSync(jsonEncode(settings.toJson()));
    } on FileSystemException {
      // Не записались — переживём: в следующий раз спросим заново.
    }
  }
}
