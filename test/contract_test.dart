import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

Mercenary _merc([MercRank rank = MercRank.ragged]) => Mercenary(
      id: 'm',
      name: 'Тестовый',
      rank: rank,
      trait: MercTrait.hardy,
    );

PlayerProfile _player() {
  final p = PlayerProfile();
  p.roster.reserve.add(_merc());
  return p;
}

/// Предмет-болванка нужного уровня для наполнения сундука.
Item _item(int ilvl) => Item(
      kind: GearKind.ring,
      ilvl: ilvl,
      rarity: Rarity.common,
      affixes: const [],
    );

/// Ждём, пока наёмник дойдёт до своей гибели: контракт открывается для забора
/// не раньше предсказанного времени смерти.
void _waitOut(PlayerProfile p) => _waitOutReturning(p);

/// Перематывает часы на месяц вперёд и возвращает контракты, закончившиеся
/// именно сейчас.
///
/// Месяц, а не «до конца спуска»: конца у спуска нет, пока игрок не принял
/// решения на развилках. Перемотка проходит всю цепочку «дошёл до развилки —
/// не дождался — доспустился по приказу».
List<Contract> _waitOutReturning(PlayerProfile p) =>
    p.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 30)));

void main() {
  // Инварианты баланса должны проверяться на ТОМ контенте, который попадёт в
  // игру. Значения по умолчанию в коде — бестиарий из одного моба; проверять
  // кривые на нём значит проверять не ту игру.
  setUpAll(() => loadContentFromDisk().apply());

  group('цикл контракта', () {
    test('до забора добычи игрок не получает НИЧЕГО', () {
      // Это сердце нового цикла: возврат в игру — обязательное действие,
      // а не привычка. Если золото или Эхо начислятся раньше, повод
      // возвращаться исчезнет.
      final p = _player();
      final m = p.roster.reserve.first;

      p.deploy(m, seed: 42);

      _waitOut(p);

      expect(p.gold, 0.0);
      expect(p.echo, 0);
      expect(p.stash, isEmpty);
      expect(p.maxDepthEver, 0);
      expect(p.hasUncollectedHaul, isTrue);
    });

    test('забор добычи закрывает контракт целиком', () {
      final p = _player();
      final m = p.roster.reserve.first;
      final contract = p.deploy(m, seed: 42);
      _waitOut(p);
      final result = contract.result!;

      final haul = p.collect(contract);

      expect(haul.collected, isTrue);
      expect(p.gold, greaterThan(0.0));
      // Эхо рана плюс награды за задания, которые этот ран закрыл: первый
      // возвращённый контракт закрывает «Первое возвращение» и всё, что за
      // ним открылось. Складывается явно — иначе тест ловил бы не «Эхо не
      // урезано», а «заданий не существует».
      final questEcho = p.lastClosedQuests
          .fold<int>(0, (sum, q) => sum + q.rewardEcho);
      expect(p.echo, result.echo + questEcho);
      expect(p.maxDepthEver, result.maxDepth);
      expect(p.hasUncollectedHaul, isFalse);
      expect(p.roster.fallen, contains(m));
      expect(p.contracts, isEmpty);
    });

    test('повторный забор невозможен', () {
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      _waitOut(p);
      p.collect(contract);
      expect(() => p.collect(contract), throwsStateError);
    });

    test('конец отрезка известен сразу — на него ставится уведомление', () {
      // Раньше здесь проверялось «время гибели известно сразу»: спуск
      // считался целиком, и дата смерти была известна при отправке. С живыми
      // развилками конца спуска не существует, пока игрок не принял решения —
      // известен конец ОТРЕЗКА, до ближайшей развилки. Уведомление ставится
      // на него, и зовёт оно к развилке, а не к добыче.
      final p = _player();
      final start = DateTime.utc(2026, 1, 1, 12);
      final contract = p.deploy(p.roster.reserve.first, seed: 42, now: start);

      expect(contract.segmentEndsAtUtc, isNotNull);
      expect(contract.segmentEndsAtUtc!.isAfter(start), isTrue);
      expect(contract.result!.awaitingFork, isTrue,
          reason: 'первый отрезок обязан упереться в развилку');

      final planned = contract.segmentEndsAtUtc!.difference(start).inSeconds;
      expect(planned, closeTo(contract.result!.totalSeconds, 1.0));

      // А после того как никто не ответил — это уже дата гибели.
      _waitOut(p);
      expect(contract.result!.awaitingFork, isFalse);
      expect(contract.awaitingCollection, isTrue);
    });
  });

  group('снаряжение переживает наёмника', () {
    test('осколки с переплавки доезжают до Верстака и упираются в его размер',
        () {
      // Осколок — то, ради чего переплавка вообще существует. Раньше он
      // появлялся сам, когда находка не влезала в рюкзак; рюкзак стал
      // бесконечным, и теперь осколок появляется от РЕШЕНИЯ игрока — он же
      // единственное, чем «переплавить» отличается от «продать».
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 1);
      _waitOut(p);
      p.collect(contract);

      final meltable = [
        for (final item in p.pendingLoot)
          if (item.rarity.rank >= Rarity.rare.rank && item.affixes.isNotEmpty)
            item,
      ];
      expect(meltable, isNotEmpty,
          reason: 'за спуск находится не только обычное');

      final before = p.shards.length;
      final room = p.outpost.shardCapacity - before;
      for (final item in meltable) {
        expect(p.meltLoot(item), isTrue);
      }

      expect(p.shards.length - before,
          meltable.length < room ? meltable.length : room,
          reason: 'Верстак ограничен, и сверх него осколки не кладутся');
    });

    test('продажа платит больше переплавки, но осколка не даёт', () {
      // Иначе «продать» было бы переплавкой без осколка, то есть строго
      // худшим вариантом. Строго худший вариант — не выбор, а лишняя кнопка.
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 1);
      _waitOut(p);
      p.collect(contract);

      final item = p.pendingLoot.first;
      final value = p.salvageValue(item);
      final before = p.gold;

      expect(p.sellLoot(item), isTrue);
      expect(p.gold - before, closeTo(value * Tuning.sellBonus, 0.01));
      expect(Tuning.sellBonus, greaterThan(1.0));
    });

    test('надетое возвращается в сундук вместе с добычей', () {
      final p = _player();
      final c1 = p.deploy(p.roster.reserve.first, seed: 42);
      _waitOut(p);
      p.collect(c1);

      final stashAfterFirst = List<Item>.from(p.stash);
      expect(stashAfterFirst, isNotEmpty);

      // Второй наёмник экипируется из сундука — и уходит глубже.
      p.roster.reserve.add(_merc());
      final c2 = p.deploy(p.roster.reserve.first, seed: 43);
      _waitOut(p);
      p.collect(c2);

      expect(c2.result!.maxDepth, greaterThan(c1.result!.maxDepth));
    });

    test('экипировка изымается из сундука на время спуска', () {
      final p = _player();
      p.stash.addAll([50, 48, 46, 44].map(_item));
      final before = p.stash.length;

      p.deploy(p.roster.reserve.first, seed: 42);

      _waitOut(p);

      expect(p.stash.length, lessThan(before));
    });

    test('сундук ограничен, излишек уходит в золото', () {
      final p = PlayerProfile();
      p.roster.reserve.add(_merc(MercRank.legend));
      p.stash.addAll(List.generate(200, (_) => _item(30)));

      final c = p.deploy(p.roster.reserve.first, seed: 42);

      _waitOut(p);
      p.collect(c);

      expect(p.stash.length, lessThanOrEqualTo(p.outpost.stashSlots));
      expect(p.gold, greaterThan(0.0));
    });
  });

  group('экономика', () {
    test('наём списывает золото и только при достатке', () {
      final p = PlayerProfile(gold: 100.0);
      final rich = _merc(MercRank.legend);
      expect(p.hire(rich), isFalse);
      expect(p.gold, 100.0);

      p.gold = Roster.hireCost(MercRank.ragged);
      expect(p.hire(_merc()), isTrue);
      expect(p.gold, 0.0);
    });

    test('улучшение постройки списывает золото', () {
      // Рекорд нужен, потому что уровень открывает глубина, а не кошелёк.
      final p = PlayerProfile(maxDepthEver: Outpost.depthGate(1));
      final cost = p.outpost.upgradeCost(Building.tavern);
      p.gold = cost;
      expect(p.upgradeBuilding(Building.tavern), isTrue);
      expect(p.outpost.levelOf(Building.tavern), 1);
      expect(p.gold, closeTo(0.0, 1e-9));
      expect(p.upgradeBuilding(Building.tavern), isFalse,
          reason: 'денег нет, да и следующий уровень ждёт своей глубины');
    });

    test('уровень Таверны увеличивает число кандидатов', () {
      final p = PlayerProfile();
      p.refreshTavern(Rng(1));
      final base = p.roster.candidates.length;

      p.outpost.upgrade(Building.tavern);
      p.refreshTavern(Rng(1));

      expect(p.roster.candidates.length, base + 1);
    });

    test('ранг наёмника поднимает глубину контракта', () {
      int depthFor(MercRank rank) {
        final p = PlayerProfile();
        final m = _merc(rank);
        p.roster.reserve.add(m);
        final c = p.deploy(m, seed: 42);
        _waitOut(p);
        return c.result!.maxDepth;
      }

      expect(depthFor(MercRank.legend), greaterThan(depthFor(MercRank.ragged)));
    });
  });

  group('ожидание спуска', () {
    test('до предсказанной гибели добычу забрать нельзя', () {
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);

      expect(contract.descending, isTrue);
      expect(p.hasActiveDescent, isTrue);
      expect(p.hasUncollectedHaul, isFalse);
      expect(() => p.collect(contract), throwsStateError);
    });

    test('время вышло — наёмник встаёт на развилке, потом идёт сам', () {
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);

      // За секунду до конца отрезка ничего не меняется.
      final almost =
          contract.segmentEndsAtUtc!.subtract(const Duration(seconds: 1));
      expect(p.refreshContracts(almost), isEmpty);
      expect(contract.descending, isTrue);

      // Дошёл до развилки и встал. Контракт НЕ закончен: добычу забирать
      // нечего, наёмник жив и ждёт.
      final atFork = contract.segmentEndsAtUtc!;
      expect(p.refreshContracts(atFork), isEmpty);
      expect(contract.atFork, isTrue);
      expect(contract.pendingFork, isNotNull);
      expect(contract.pendingFork!.options, hasLength(2));

      // Не дождавшись, наёмник перестаёт стоять и идёт дальше сам. Спуск при
      // этом ещё НЕ кончен: впереди весь остаток пути, просто решать его
      // будет приказ.
      p.refreshContracts(
          atFork.add(Duration(seconds: Tuning.forkWaitSeconds.round() + 1)));
      expect(contract.descending, isTrue);
      expect(contract.result!.awaitingFork, isFalse,
          reason: 'остаток спуска решён приказом, остановок больше не будет');
      expect(contract.waitedSeconds, closeTo(Tuning.forkWaitSeconds, 0.01),
          reason: 'простой засчитан ровно один раз');

      // И только когда время дошло до конца — контракт ждёт получения.
      final finished = _waitOutReturning(p);
      expect(finished, [contract]);
      expect(contract.awaitingCollection, isTrue);

      // Повторный вызов не должен сообщать о том же событии дважды.
      expect(_waitOutReturning(p), isEmpty);
    });

    test('журнал открывается по ходу времени, а не весь сразу', () {
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      _waitOut(p);
      final full = contract.result!.maxDepth;

      expect(contract.depthAt(contract.startedAtUtc), 0);
      expect(contract.progressAt(contract.startedAtUtc), 0.0);

      // Середина ИГРОВОГО времени, а не настенного: между ними теперь стоит
      // простой на развилке, и «половина ожидания» — это уже не «половина
      // спуска». Пауза случилась до середины, поэтому её надо прибавить.
      final middle = contract.startedAtUtc.add(Duration(
        milliseconds: (contract.result!.totalSeconds * 500).round() +
            (contract.waitedSeconds * 1000).round(),
      ));
      final half = contract.depthAt(middle);
      expect(half, greaterThan(0));
      expect(half, lessThan(full));
      expect(contract.progressAt(middle), closeTo(0.5, 0.01));

      expect(contract.depthAt(contract.segmentEndsAtUtc!), full);
      expect(contract.remainingAt(contract.segmentEndsAtUtc!), Duration.zero);
    });
  });

  group('повтор спуска', () {
    test('снимок лоадаута воспроизводит ран тик в тик', () {
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first, seed: 4242);
      // Повтор сверяется с ЗАКОНЧЕННЫМ спуском: при отправке посчитан только
      // отрезок до первой развилки, и сравнивать целый спуск с двумя этажами
      // значит проверять не то.
      _waitOut(p);
      final original = contract.result!;

      // Тот же сид плюс снимок снаряжения обязаны дать ТОТ ЖЕ спуск.
      // Иначе боевая сцена показывала бы один бой, а журнал — другой.
      final replay = DescentSimulator(
        profile: contract.replayProfile(),
        seed: contract.seed,
        brandRank: contract.brandRank,
        backpackCapacityOverride: contract.mercenary.backpackSlots,
        salvageRate: p.outpost.salvageRate,
      ).run();

      expect(replay.maxDepth, original.maxDepth);
      expect(replay.ending, original.ending);
      expect(replay.totalSeconds, original.totalSeconds);
      expect(replay.echo, original.echo);
      expect(replay.killedBy, original.killedBy);
      expect(replay.floors.length, original.floors.length);
      for (var i = 0; i < replay.floors.length; i++) {
        expect(replay.floors[i].seconds, original.floors[i].seconds,
            reason: 'этаж ${replay.floors[i].depth}');
        expect(replay.floors[i].lowestHpFraction,
            original.floors[i].lowestHpFraction);
      }
    });

    test('приказ на развилку — часть снимка', () {
      // Политика меняет выбранные модификаторы, а с ними и весь спуск.
      // Повтор с политикой по умолчанию показал бы бой, которого не было,
      // и заметить это можно было бы только глазами.
      final p = _player();
      final contract = p.deploy(p.roster.reserve.first,
          seed: 777, forkPolicy: ForkPolicy.safety);
      expect(contract.forkPolicy, ForkPolicy.safety);

      // Спуск доводится до конца приказом — ровно тот случай, который повтор
      // и обязан воспроизвести: игрока не было, решала политика.
      _waitOut(p);

      RunResult replay(ForkPolicy policy) => DescentSimulator(
            profile: contract.replayProfile(),
            seed: contract.seed,
            brandRank: contract.brandRank,
            backpackCapacityOverride: contract.mercenary.backpackSlots,
            salvageRate: p.outpost.salvageRate,
            forkPolicy: policy,
          ).run();

      final same = replay(contract.forkPolicy);
      expect(same.maxDepth, contract.result!.maxDepth);
      expect(same.totalSeconds, contract.result!.totalSeconds);

      // И обратное: политика — не украшение. С другим приказом спуск другой,
      // иначе весь рычаг был бы косметикой.
      final other = replay(ForkPolicy.loot);
      expect(other.totalSeconds, isNot(same.totalSeconds));
    });

    test('находки в спуске не трогают снаряжение наёмника', () {
      // Правило, которое заменило прежнее «наёмник надевает лучшее»: он не
      // переодевается вовсе. Сборка, ушедшая вниз, и есть та, что вернётся.
      final p = _player();
      final merc = p.roster.reserve.first;
      final contract = p.deploy(merc, seed: 11);
      _waitOut(p);

      expect(merc.gear.filledSlots, greaterThan(0));
      expect(contract.result!.itemsFound, greaterThan(0),
          reason: 'проверять нечего, если он ничего не нашёл');

      for (var i = 0; i < Equipment.slotCount; i++) {
        expect(merc.gear.at(i), same(contract.loadout.at(i)),
            reason: 'слот $i изменился за спуск');
      }
    });
  });
}
