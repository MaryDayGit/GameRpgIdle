import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/floor_modifier_def.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/daily_rift.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/forecast.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Разлом дня отвечает на единственный вопрос, которого у игры не было: **чем
/// завтра отличается от сегодня.**
///
/// Всё остальное в ней — накопление, а накопление одинаково в любой день.
/// Поэтому проверяется не «разлом работает», а ровно три обещания, каждое из
/// которых по-своему ломает саму идею:
///
/// * **день у всех один** — иначе это не событие, а личный случайный спуск;
/// * **перекатить нельзя** — иначе «сегодняшний разлом» становится «любым
///   разломом, пока не понравится»;
/// * **раз в сутки** — иначе завтра снова ничем не отличается.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  PlayerProfile player() => PlayerProfile.newGame(seed: 5)..gold = 50000;

  DateTime day(int n) => DateTime.utc(2026, 1, 1).add(Duration(days: n));

  group('расписание', () {
    test('в одни сутки разлом один и тот же', () {
      final morning = DailyRift.on(DateTime.utc(2026, 3, 7, 6));
      final evening = DailyRift.on(DateTime.utc(2026, 3, 7, 23, 59));

      expect(morning.day, evening.day);
      expect(morning.seed, evening.seed);
      expect(morning.modifier.id, evening.modifier.id);
    });

    test('в разные сутки — разный', () {
      // Не «обязательно другой модификатор» (их восемь, совпадения бывают), а
      // другой СПУСК: сид обязан смениться, иначе завтра буквально повторяет
      // сегодня.
      final seeds = {
        for (var i = 0; i < 30; i++) DailyRift.on(day(i)).seed,
      };
      expect(seeds.length, greaterThan(25),
          reason: 'сид дня почти всегда обязан быть новым');
    });

    test('сутки считаются по UTC, а не по местному времени', () {
      // Игрок, летящий через часовые пояса, иначе получал бы два разлома в
      // день или ни одного. «Сегодня» — это то, что одинаково для всех.
      final a = DailyRift.dayOf(DateTime.utc(2026, 5, 1, 0, 30));
      final b = DailyRift.dayOf(DateTime.utc(2026, 5, 1, 23, 30));
      final c = DailyRift.dayOf(DateTime.utc(2026, 5, 2, 0, 30));

      expect(a, b);
      expect(c, a + 1);
    });
  });

  group('спуск в разлом', () {
    test('модификатор действует на КАЖДОМ этаже', () {
      // В обычном спуске модификатор меняется на развилках, и между ними есть
      // этажи без него вовсе. В разломе он один от начала до конца — в этом и
      // состоит лицо дня.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 1, rift: true);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      final floors = contract.result!.floors;
      expect(floors, isNotEmpty);
      expect(floors.every((f) => f.modifierId != null), isTrue,
          reason: 'этаж без модификатора в разломе — это обычный этаж');
    });

    test('перекатить разлом нельзя: сид общий, а не свой', () {
      // Сид приходит от дня, а не от вызова. Закрыть приложение и отправить
      // заново — тот же спуск.
      final a = player();
      final b = player();
      final at = day(3);

      final first = a.deploy(a.roster.reserve.first,
          seed: 111, now: at, rift: true);
      final second = b.deploy(b.roster.reserve.first,
          seed: 999, now: at, rift: true);

      expect(first.seed, second.seed,
          reason: 'сид разлома выводится из дня, а не из вызова');
      expect(first.riftDay, DailyRift.dayOf(at));
    });

    test('обычный спуск разлома не касается', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 7);

      expect(contract.isRift, isFalse);
      expect(contract.riftDay, isNull);
      expect(p.riftAvailable(DateTime.now().toUtc()), isTrue,
          reason: 'обычный спуск не тратит сегодняшний разлом');
    });
  });

  group('экран не врёт про разлом', () {
    // Разлом виден игроку в двух местах: в прогнозе на боевом экране и в
    // журнале после спуска. Оба читают не симуляцию, а собственный расчёт —
    // и оба до этого разлома не знали.

    test('прогноз показывает то же, что записал спуск', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 1, rift: true);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      final predicted = {
        for (final floor in Forecast.ahead(
          seed: contract.seed,
          fromDepth: contract.startDepth,
          floors: 40,
          policy: contract.forkPolicy,
          rift: contract.riftModifier,
          choices: contract.forkChoices,
          startDepth: contract.startDepth,
        ))
          floor.depth: floor.modifier?.id,
      };

      for (final floor in contract.result!.floors.take(40)) {
        expect(predicted[floor.depth], floor.modifierId,
            reason: 'этаж ${floor.depth}');
        expect(predicted[floor.depth], isNotNull,
            reason: '«ровный путь» в разломе — обещание, которого спуск '
                'не выполнит');
      }
    });

    test('составной модификатор читается обратно по id', () {
      // Журнал знает про этаж только id, а действовала на нём пара: путь и
      // разлом. Не разобрав её, журнал молча пропускал бы строку — и спуск
      // выглядел бы обычным.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 4, rift: true);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      final ids =
          contract.result!.floors.map((f) => f.modifierId!).toSet();
      expect(ids, isNotEmpty);
      expect(ids.any((id) => id.contains(FloorModifierDef.composedMark)), isTrue,
          reason: 'без развилки внутри разлома проверять нечего');

      for (final id in ids) {
        final def = ContentPack.current.floorModifier(id);
        expect(def, isNotNull, reason: 'id «$id» не читается обратно');
        expect(def!.name, isNotEmpty);
      }
    });

    test('отзыв из разлома возвращает наёмника ИЗ РАЗЛОМА', () {
      // Отзыв пересчитывает спуск заново. Забудь он про разлом — игрок
      // смотрел бы один спуск, а принёс бы добычу из другого.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 8, rift: true);

      expect(
          p.recall(contract,
              contract.startedAtUtc.add(const Duration(minutes: 3))),
          isTrue);

      final floors = contract.result!.floors;
      expect(floors, isNotEmpty);
      expect(contract.result!.ending, RunEnding.recalled);
      expect(floors.every((f) => f.modifierId != null), isTrue,
          reason: 'отозванный спуск обязан остаться спуском в разлом');
    });
  });

  group('раз в сутки', () {
    test('второй разлом в тот же день недоступен', () {
      final p = player();
      final at = day(10);

      expect(p.riftAvailable(at), isTrue);
      p.deploy(p.roster.reserve.first, seed: 1, now: at, rift: true);
      expect(p.riftAvailable(at), isFalse);
    });

    test('сутки засчитываются при ОТПРАВКЕ, а не при заборе добычи', () {
      // Иначе игрок, не забравший вчерашний разлом, сегодня попал бы в него
      // второй раз: контракт-то ещё открыт.
      final p = player();
      final at = day(11);
      p.deploy(p.roster.reserve.first, seed: 1, now: at, rift: true);

      expect(p.riftDoneOn, DailyRift.dayOf(at));
      expect(p.riftAvailable(at), isFalse,
          reason: 'добыча ещё не забрана, а сутки уже потрачены');
    });

    test('завтра разлом снова доступен', () {
      final p = player();
      p.deploy(p.roster.reserve.first, seed: 1, now: day(12), rift: true);

      expect(p.riftAvailable(day(12)), isFalse);
      expect(p.riftAvailable(day(13)), isTrue);
    });
  });

  group('награда', () {
    test('Эхо за разлом удваивается, и глубина ведёт свою запись', () {
      final p = player();
      final contract =
          p.deploy(p.roster.reserve.first, seed: 1, rift: true);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      final result = contract.result!;
      final before = p.echo;
      p.collect(contract);

      // Не равенство: закрытые задания тоже платят Эхом, и «ровно вдвое»
      // ломалось бы от первой же закрытой цели. Проверяется удвоение самого
      // спуска.
      expect(p.echo - before, greaterThanOrEqualTo(result.echo * 2),
          reason: 'Эхом, а не золотом: оно идёт в древо и остаётся навсегда, '
              'а «зайти завтра» должно окупаться тем, что не упирается ни в '
              'сундук, ни в выкупленную Заставу');
      expect(p.riftBestDepth, result.maxDepth);
    });

    test('запись разлома отдельная от общего рекорда', () {
      // Разлом идёт под модификатором на каждом этаже, и сравнивать его с
      // обычным рекордом значило бы сравнивать разные игры.
      final p = player();
      final ordinary = p.deploy(p.roster.reserve.first, seed: 3);
      p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      p.collect(ordinary);
      p.autoSortLoot();

      expect(p.maxDepthEver, greaterThan(0));
      expect(p.riftBestDepth, 0,
          reason: 'обычный спуск не пишется в запись разлома');
    });
  });
}
