import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/model/tags.dart';
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

  test('у каждого звука есть файл, и каждому назначена громкость', () {
    // Имя в перечислении — это имя файла. Звук, добавленный в код и забытый
    // в генераторе, молчит ровно так же, как выключенный, и заметить это на
    // слух невозможно: в бою и так не тишина.
    for (final sfx in Sfx.values) {
      final file = File('assets/audio/${sfx.name}.wav');
      expect(file.existsSync(), isTrue,
          reason: 'нет ${file.path} — запустите '
              '`dart run tool/make_sounds.dart`');
      expect(file.lengthSync(), greaterThan(1000),
          reason: '${file.path} подозрительно короткий');
    }
  });

  test('у частых звуков три дубля, и все на месте', () {
    // Один файл на удар, повторённый сотню раз за спуск, слышен метрономом.
    // Дубль, забытый в генераторе, молча выпадает из ротации — и снова
    // остаётся метроном, только реже.
    for (final sfx in GameFeedback.takes) {
      for (var take = 0; take < 3; take++) {
        final file = File('assets/audio/${GameFeedback.fileFor(sfx, take)}');
        expect(file.existsSync(), isTrue, reason: 'нет ${file.path}');
      }
    }
    for (final sfx in Sfx.values) {
      expect(GameFeedback.volumeOf(sfx), isNotNull,
          reason: 'у ${sfx.name} нет громкости — он звучал бы в полную силу');
    }
  });

  test('каждая стихия звучит по-своему', () {
    // Пять стихий, за которые игрок платит слотами и целым «Проводником»,
    // звучали одним «тук». Два одинаковых звука здесь означают, что на слух
    // выбор стихии снова неразличим.
    final byType = {
      for (final type in DamageType.values) sfxForDamage(type),
    };
    expect(byType, hasLength(DamageType.values.length));
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
