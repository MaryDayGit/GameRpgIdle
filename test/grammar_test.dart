import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Игра говорит по-русски.
///
/// Живой прогон дал это замечанием «иногда странные слова», и слова были
/// такие: «Кольцо · Редкий», «Мирена Последний», «Перчатки распылён»,
/// «„Кровавая пиявка“ пал». Каждое — согласование, которого не было: строка
/// собиралась из кусков, а род кусков никто не спрашивал.
///
/// Тесты держат правило, а не конкретные слова: **если строка собирается из
/// частей, род берётся у той части, которая задаёт смысл.**
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('вещи', () {
    test('редкость согласована с типом вещи', () {
      for (final kind in GearKind.values) {
        for (final rarity in Rarity.values) {
          final word = rarity.forKind(kind);
          expect(word, isNotEmpty, reason: '${kind.ru} · ${rarity.name}');

          // Признак женского и среднего рода — окончание. Проверяется не
          // словарь, а то, что форма ВООБЩЕ выбирается по роду.
          if (rarity == Rarity.relic) continue;
          final tail = word.substring(word.length - 2);
          switch (kind.gender) {
            case Gender.feminine:
              expect(['ая', 'яя'], contains(tail), reason: kind.ru);
            case Gender.neuter:
              expect(['ое', 'ее'], contains(tail), reason: kind.ru);
            case Gender.plural:
              expect(['ые', 'ие'], contains(tail), reason: kind.ru);
            case Gender.masculine:
              expect(['ый', 'ий', 'ой'], contains(tail), reason: kind.ru);
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
    test('прозвище согласовано с именем', () {
      // Половина имён в пуле женские. «Мирена Последний» — не колорит,
      // а несогласованная строка.
      for (var seed = 1; seed <= 200; seed++) {
        final merc = MercFactory.roll(Rng(seed), idPrefix: 'g');
        final epithet = merc.name.split(' ').last;

        // Женские окончания прозвищ: «Хромая», «Последняя», «Молчунья».
        final tail = epithet.substring(epithet.length - 2);
        final feminine = ['ая', 'яя', 'ья'].contains(tail);

        expect(feminine, merc.gender == Gender.feminine, reason: merc.name);
      }
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
      expect(MercFactory.genderOf('Мирена Последняя'), Gender.feminine);
      expect(MercFactory.genderOf('Корвин Хромой'), Gender.masculine);
      expect(MercFactory.genderOf('Некто Безымянный'), Gender.masculine);
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
