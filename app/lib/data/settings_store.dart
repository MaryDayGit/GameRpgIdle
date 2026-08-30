import 'dart:convert';
import 'dart:io';

/// Настройки приложения: звук, вибрация, пройдено ли обучение.
///
/// Отдельный файл, а не поле в сейве, потому что это не состояние игры.
/// Сейв описывает Заставу и наёмников — он переживает переустановку, его
/// мигрируют версиями. Выключенный звук такой судьбы не заслуживает, и
/// хранить его вместе с профилем значило бы гонять миграцию из-за галочки.
class AppSettings {
  AppSettings({
    this.sound = true,
    this.haptics = true,
    this.tutorialDone = false,
  });

  bool sound;
  bool haptics;

  /// Обучение пройдено или пропущено. Показывать его второй раз — худшее,
  /// что можно сделать с игроком, который уже разобрался.
  bool tutorialDone;

  Map<String, dynamic> toJson() => {
        'sound': sound,
        'haptics': haptics,
        'tutorialDone': tutorialDone,
      };

  /// Читает настройки, прощая всё. Испорченный файл настроек не повод не
  /// пустить игрока в игру: непонятое поле берётся по умолчанию.
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        sound: j['sound'] is bool ? j['sound'] as bool : true,
        haptics: j['haptics'] is bool ? j['haptics'] as bool : true,
        tutorialDone:
            j['tutorialDone'] is bool ? j['tutorialDone'] as bool : false,
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
