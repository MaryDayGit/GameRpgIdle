import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Игра говорит по-русски грамотно.
///
/// Живой прогон дал это замечанием «иногда странные слова», и слова были
/// такие: «Кольцо · Редкий», «Мирена Последний», «Перчатки распылён»,
/// «„Кровавая пиявка“ пал». Каждое — согласование, которого не было: строка
/// собиралась из кусков, а род кусков никто не спрашивал.
///
/// Тесты держат правило, а не конкретные слова: **если строка собирается из
/// частей, род берётся у той части, которая задаёт смысл.**
///
/// Согласование осталось русским и после перевода игры: английскому оно не
/// нужно. Имена наёмников — исключение в другую сторону: они английские на
/// обоих языках, потому что лежат в сейве, а не собираются при показе. Род у
/// них при этом читается по-прежнему — им пользуются ранг, черта и исход
/// спуска.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('вещи', () {
    test('редкость согласована с типом вещи', () {
      for (final kind in GearKind.values) {
        for (final rarity in Rarity.values) {
          final word = rarity.forKind(kind);
          expect(word, isNotEmpty, reason: '${kind.title} · ${rarity.name}');

          // Признак женского и среднего рода — окончание. Проверяется не
          // словарь, а то, что форма ВООБЩЕ выбирается по роду.
          if (rarity == Rarity.relic) continue;
          final tail = word.substring(word.length - 2);
          switch (kind.gender) {
            case Gender.feminine:
              expect(['ая', 'яя'], contains(tail), reason: kind.title);
            case Gender.neuter:
              expect(['ое', 'ее'], contains(tail), reason: kind.title);
            case Gender.plural:
              expect(['ые', 'ие'], contains(tail), reason: kind.title);
            case Gender.masculine:
              expect(['ый', 'ий', 'ой'], contains(tail), reason: kind.title);
          }
        }
      }
    });

    test('заголовок вещи читается целиком', () {
      final ring = Item(
        kind: GearKind.ring,
        ilvl: 30,
        rarity: Rarity.rare,
        affixes: const [],
      );
      final gloves = Item(
        kind: GearKind.gloves,
        ilvl: 30,
        rarity: Rarity.common,
        affixes: const [],
      );

      expect(ItemText.title(ring), contains('Редкое'));
      expect(ItemText.title(gloves), contains('Обычные'));
    });
  });

  group('наёмники', () {
    test('имя не зависит от языка', () {
      // Ради этого имена и сделаны английскими на обоих языках. Имя ЛЕЖИТ В
      // СЕЙВЕ, а не собирается при показе: будь пул переводимым, наёмник,
      // нанятый по-английски, остался бы английским и после переключения на
      // русский — и в одном отряде оказалась бы половина имён на одном языке,
      // половина на другом.
      for (var seed = 1; seed <= 50; seed++) {
        Lang.current = Lang.ru;
        final ru = MercFactory.roll(Rng(seed), idPrefix: 'g').name;
        Lang.current = Lang.en;
        final en = MercFactory.roll(Rng(seed), idPrefix: 'g').name;

        expect(ru, en, reason: 'имя на сиде $seed разъехалось с языком');
      }
      Lang.current = Lang.ru;
    });

    test('в пуле примерно поровну мужских и женских имён', () {
      // Половина пула женские: род нужен рангу, черте, исходу спуска и
      // уведомлению о гибели.
      var feminine = 0;
      for (var seed = 1; seed <= 200; seed++) {
        final merc = MercFactory.roll(Rng(seed), idPrefix: 'g');
        if (merc.gender == Gender.feminine) feminine++;
      }
      expect(feminine, greaterThan(50),
          reason: 'женских имён в пуле должно быть примерно половина');
    });

    test('ранг и черта согласованы с наёмником', () {
      final she = MercFactory.roll(Rng(1), idPrefix: 'f');
      expect(she.gender, Gender.feminine, reason: 'сид подобран под женское имя');

      for (final trait in MercTrait.values) {
        expect(trait.forGender(Gender.feminine), isNotEmpty);
      }
      expect(MercRank.ragged.forGender(Gender.feminine), 'Оборванка');
      expect(MercRank.ragged.forGender(Gender.masculine), 'Оборванец');
    });

    test('род берётся из имени, а не хранится полем', () {
      // Имя уже лежит в сейве: второе поле означало бы смену формата ради
      // того, что и так однозначно выводится. Незнакомое имя — мужской род,
      // как в старых сейвах и в тестах.
      expect(MercFactory.genderOf('Mirena the Blind'), Gender.feminine);
      expect(MercFactory.genderOf('Corwin the Lame'), Gender.masculine);
      expect(MercFactory.genderOf('Nobody Nameless'), Gender.masculine);

      // Сейв, сделанный до перевода имён, обязан читаться так же. Иначе у
      // всех нанятых раньше наёмниц сменился бы род, и первое же уведомление
      // сказало бы «Мирена Слепая погиб».
      expect(MercFactory.genderOf('Мирена Последняя'), Gender.feminine);
      expect(MercFactory.genderOf('Корвин Хромой'), Gender.masculine);
    });
  });

  group('бестиарий', () {
    test('у каждого моба и босса указан род', () {
      final all = [
        ...ContentPack.current.enemies,
        ...ContentPack.current.bosses,
      ];
      expect(all, isNotEmpty);

      for (final e in all) {
        // Женский род должен где-то встречаться: иначе поле есть, а толку
        // от него нет, и «повержена» не покажется никогда.
        expect(Gender.values, contains(e.gender), reason: e.name);
      }
      expect(all.any((e) => e.gender == Gender.feminine), isTrue,
          reason: 'в бестиарии обязан быть кто-то женского рода');
    });

    test('род совпадает с названием', () {
      // Опечатка в роде ловится здесь: «Кровавая пиявка» женского рода,
      // «Падальщик» — мужского, и «Мирена погиб» в журнале не появится.
      //
      // Сначала спрашиваем ПРИЛАГАТЕЛЬНОЕ: его окончание однозначно, а
      // существительное — нет. «Инеевая тварь» женского рода, но «тварь»
      // кончается мягким знаком, как и мужской «зверь»; прежняя проверка
      // смотрела только на последнее слово и требовала переименовать моба
      // вместо того, чтобы научиться читать.
      for (final e in ContentPack.current.enemies) {
        final words = e.name.toLowerCase().split(' ');
        final first = words.first;

        final bool feminine;
        if (first.endsWith('ая') || first.endsWith('яя')) {
          feminine = true;
        } else if (first.endsWith('ый') ||
            first.endsWith('ий') ||
            first.endsWith('ой')) {
          feminine = false;
        } else {
          // Без прилагательного судим по существительному — оно же первое:
          // «Кузнец пепла» это кузнец, а не пепел.
          feminine = first.endsWith('а') || first.endsWith('я');
        }

        expect(e.gender == Gender.feminine, feminine, reason: e.name);
      }
    });
  });
}
