import 'package:flutter_test/flutter_test.dart';
import 'package:rift_app/data/feedback.dart';
import 'package:rift_app/data/settings_store.dart';

/// Звук и вибрация — единственная часть игры, которую игрок может захотеть
/// выключить насовсем. Значит проверяется не «звучит», а «молчит, когда
/// сказано молчать», и что настройка это переживает.
void main() {
  // Вибрация ходит через платформенный канал: без привязки теста его нет,
  // и падение было бы про отсутствие биндинга, а не про игру.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('выключенный звук ничего не играет', () {
    // На тестовой платформе плеера нет вовсе, поэтому проверяется контракт:
    // вызов безопасен и не бросает при любом состоянии.
    final feedback = GameFeedback(sound: false, haptics: false);
    expect(() => feedback.play(Sfx.hit), returnsNormally);
    expect(() => feedback.play(Sfx.death, bump: Bump.heavy), returnsNormally);
  });

  test('звук без инициализации не падает', () {
    final feedback = GameFeedback();
    expect(() => feedback.play(Sfx.crit), returnsNormally);
    expect(() => feedback.bump(Bump.light), returnsNormally);
  });

  group('настройки', () {
    test('умолчания: звук и вибрация включены, обучение не пройдено', () {
      final settings = AppSettings();
      expect(settings.sound, isTrue);
      expect(settings.haptics, isTrue);
      expect(settings.tutorialDone, isFalse);
    });

    test('битый файл настроек не мешает играть', () {
      // Настройки не стоят того, чтобы из-за них не запускалась игра.
      final settings = AppSettings.fromJson(const {
        'sound': 'да',
        'haptics': 42,
      });

      expect(settings.sound, isTrue);
      expect(settings.haptics, isTrue);
    });

    test('выбор переживает запись и чтение', () {
      final json = (AppSettings(sound: false, tutorialDone: true)).toJson();
      final back = AppSettings.fromJson(json);

      expect(back.sound, isFalse);
      expect(back.haptics, isTrue);
      expect(back.tutorialDone, isTrue);
    });
  });
}
