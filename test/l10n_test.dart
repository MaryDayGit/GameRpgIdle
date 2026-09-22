import 'package:rift/core/content/text_overlay.dart';
import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/model/tags.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

void main() {
  // Язык — статик, как контент и ручки баланса. Тест, оставивший после себя
  // английский, ломал бы соседние тесты через файл, а не через код, — и
  // искать это пришлось бы по порядку запуска.
  tearDown(() => Lang.current = Lang.ru);

  group('накладка перевода', () {
    test('подменяет текст и не трогает числа', () {
      final overlay = TextOverlay.fromJson({
        'entries': {
          'max_hp_flat': {'name': '+{value} maximum HP'},
        },
      });

      final source = {
        'affixes': [
          {
            'id': 'max_hp_flat',
            'ru': '+{value} к максимуму HP',
            'base': 30.0,
            'weight': 12,
          },
        ],
      };

      final out = overlay.applyTo(source)! as Map<String, Object?>;
      final affix = (out['affixes']! as List).first as Map<String, Object?>;

      expect(affix['ru'], '+{value} maximum HP');
      expect(affix['base'], 30.0, reason: 'накладка не касается баланса');
      expect(affix['weight'], 12);
      expect(source['affixes'], isNotEmpty,
          reason: 'исходник остаётся нетронутым — он уезжает в изолят');
    });

    test('запись без перевода остаётся на языке оригинала', () {
      final overlay = TextOverlay.fromJson({
        'entries': {
          'known': {'name': 'Known'},
        },
      });

      final out = overlay.applyTo({
        'items': [
          {'id': 'known', 'ru': 'Известный'},
          {'id': 'unknown', 'ru': 'Неизвестный'},
        ],
      })! as Map<String, Object?>;

      final items = (out['items']! as List).cast<Map<String, Object?>>();
      expect(items[0]['ru'], 'Known');
      expect(items[1]['ru'], 'Неизвестный',
          reason: 'перевод доезжает по частям, игра не ждёт его целиком');
    });

    test('находит записи на любой глубине вложения', () {
      // Способности лежат списком, узлы дерева — внутри веток, задания —
      // внутри цепей. Накладка не знает форму файлов и не должна знать.
      final overlay = TextOverlay.fromJson({
        'entries': {
          'deep': {'name': 'Deep', 'text': 'Deep text'},
        },
      });

      final out = overlay.applyTo({
        'branches': [
          {
            'id': 'branch',
            'nodes': [
              {'id': 'deep', 'ru': 'Глубокий', 'text': 'Глубокий текст'},
            ],
          },
        ],
      })! as Map<String, Object?>;

      final branch = (out['branches']! as List).first as Map<String, Object?>;
      final node = (branch['nodes']! as List).first as Map<String, Object?>;
      expect(node['ru'], 'Deep');
      expect(node['text'], 'Deep text');
    });
  });

  group('контент на каждом языке', () {
    // Главная проверка этого файла. Перевод — обычный контент, и он обязан
    // проходить тот же валидатор: шаблон, из которого переводчик выронил
    // `{value}`, покажет игроку описание без числа, и заметить это иначе
    // можно только глазами на нужном экране.
    for (final lang in Lang.values) {
      test('${lang.code}: разбирается и проходит валидатор', () {
        // `ContentPack.parse` бросает на первой же проблеме: игра с битым
        // контентом стартовать не должна. Значит проверка — «не бросил».
        expect(() => loadContentFromDisk(lang: lang), returnsNormally,
            reason: 'контент не проходит валидацию на языке ${lang.code}');
      });
    }

    for (final lang in Lang.values) {
      test('${lang.code}: у каждого существа своё имя', () {
        // Валидатор проверяет, что строка есть, но не что она своя. Так в
        // английской версии Ледяной и Громовой стражи из бездны получили имена
        // стражей логов — два разных существа с одним именем на одном экране.
        final pack = loadContentFromDisk(lang: lang);
        final creatures = [...pack.enemies, ...pack.bosses, ...pack.guardians];
        final byName = <String, List<String>>{};
        for (final c in creatures) {
          (byName[c.name] ??= []).add(c.id);
        }
        final clashes = {
          for (final e in byName.entries)
            if (e.value.length > 1) e.key: e.value,
        };
        expect(clashes, isEmpty,
            reason: 'одно имя у разных существ (${lang.code})');

        final skills = <String, List<String>>{};
        for (final g in pack.guardians) {
          for (final s in g.skills) {
            (skills[s.name] ??= []).add(s.id);
          }
        }
        expect(
          {for (final e in skills.entries) if (e.value.length > 1) e.key: e.value},
          isEmpty,
          reason: 'одно имя у разных умений стражей (${lang.code})',
        );
      });
    }

    test('перевод сохраняет плейсхолдеры шаблонов', () {
      final ru = loadContentFromDisk();
      final en = loadContentFromDisk(lang: Lang.en);

      for (final affix in ru.statAffixes) {
        final translated = en.statAffix(affix.id);
        expect(translated, isNotNull, reason: 'аффикс ${affix.id} потерялся');
        expect(
          TextTemplate.namesIn(translated!.template).toSet(),
          TextTemplate.namesIn(affix.template).toSet(),
          reason: 'в переводе «${affix.id}» другой набор чисел, чем в '
              'оригинале — на экране будет либо пустое место, либо '
              'неподставленный плейсхолдер',
        );
      }
    });
  });

  group('язык меняет сборку строки, а не только слова', () {
    test('проценты и секунды набираются по правилам языка', () {
      Lang.current = Lang.ru;
      expect(TextTemplate.percent(0.08), '8 %');
      expect(TextTemplate.seconds(4.0), '4 с');

      Lang.current = Lang.en;
      expect(TextTemplate.percent(0.08), '8%');
      expect(TextTemplate.seconds(4.0), '4s');
    });

    test('редкость согласуется по-русски и не согласуется по-английски', () {
      Lang.current = Lang.ru;
      expect(Rarity.rare.forKind(GearKind.ring), 'Редкое');
      expect(Rarity.rare.forKind(GearKind.gloves), 'Редкие');
      expect(Rarity.rare.forKind(GearKind.helmet), 'Редкий');

      Lang.current = Lang.en;
      for (final kind in GearKind.values) {
        expect(Rarity.rare.forKind(kind), 'Rare',
            reason: 'английскому род не нужен, и спрашивать его не о чем');
      }
    });

    test('черта наёмника согласуется с родом только по-русски', () {
      Lang.current = Lang.ru;
      expect(MercTrait.hardy.forGender(Gender.masculine), 'Живучий');
      expect(MercTrait.hardy.forGender(Gender.feminine), 'Живучая');

      Lang.current = Lang.en;
      expect(MercTrait.hardy.forGender(Gender.masculine), 'Hardy');
      expect(MercTrait.hardy.forGender(Gender.feminine), 'Hardy');
    });

    test('словарь ядра переключается целиком', () {
      Lang.current = Lang.en;
      expect(Tag.fire.title, 'Fire');
      expect(Tag.fire.damage, 'Fire damage');
      expect(StatKey.maxHp.label, 'maximum HP');
      expect(Building.tavern.title, 'Tavern');
      expect(MercRank.legend.title, 'Legend');
      expect(GearKind.gloves.title, 'Gloves');
    });

    test('эффект постройки считается одинаково, а читается на своём языке', () {
      // Число одно и то же на обоих языках: описание берётся из той же
      // формулы, что и бой. Разойдись они — экран соврал бы игроку ровно
      // на одном из языков, и заметил бы это только он.
      Lang.current = Lang.ru;
      final ru = Outpost.effectAt(Building.vault, 3);
      Lang.current = Lang.en;
      final en = Outpost.effectAt(Building.vault, 3);

      final slots = Outpost({Building.vault: 3}).stashSlots.toString();
      expect(ru, contains(slots));
      expect(en, contains(slots));
      expect(ru, isNot(en));
    });
  });

  test('неизвестный код языка откатывается на русский, а не падает', () {
    // Сейв из будущей версии с языком, которого здесь ещё нет, обязан
    // открыться: язык — это настройка, а не данные, и терять из-за неё
    // прогресс не за что.
    expect(Lang.byCode('ru'), Lang.ru);
    expect(Lang.byCode('en'), Lang.en);
    expect(Lang.byCode('kl'), Lang.ru);
    expect(Lang.byCode(null), Lang.ru);
  });

  test('тег системной локали обрезается до языка', () {
    // Телефон называет локаль целиком — со страной, кодировкой и вариантом.
    // Игре нужен только язык: `ru_RU` и `ru-Cyrl-BY` — один и тот же русский,
    // и сравнение целой строки с кодом не нашло бы ни того, ни другого.
    expect(Lang.byTag('ru'), Lang.ru);
    expect(Lang.byTag('ru_RU'), Lang.ru);
    expect(Lang.byTag('ru_RU.UTF-8'), Lang.ru);
    expect(Lang.byTag('EN-us'), Lang.en);

    // Язык, которого в игре нет, — это `null`, а не русский: ответ «не знаю»
    // нужен вызывающему, чтобы перебрать остальные предпочтения телефона.
    expect(Lang.byTag('pt_BR'), isNull);
    expect(Lang.byTag(''), isNull);
  });
}
