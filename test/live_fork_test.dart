import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/floor_modifier_def.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/fork_cost.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Развилка — единственный момент, когда игра спрашивает игрока ВО ВРЕМЯ
/// спуска.
///
/// До этого между отправкой и гибелью не происходило ничего: спуск считался
/// целиком, приказ решал все тридцать шесть развилок, и живой прогон назвал
/// это «захожу, собираю билд, отправляю в бой и выхожу».
///
/// Проверяется три вещи, и каждая ломает механику по-своему:
///
/// * **выбор что-то меняет** — иначе развилка это лишний экран;
/// * **спуск воспроизводится по списку решений** — на этом стоит и повтор
///   боя, и сохранение: состояние симуляции не хранится нигде;
/// * **отсутствие игрока не останавливает игру** — иначе idle перестаёт быть
///   idle.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  PlayerProfile player() => PlayerProfile.newGame(seed: 5)..gold = 50000;

  DateTime far() => DateTime.now().toUtc().add(const Duration(days: 1));

  group('развилка в симуляции', () {
    RunResult segment(List<int> choices) => DescentSimulator(
          profile: HeroProfile(powerMultiplier: 6.0),
          seed: 777,
          forkChoices: choices,
          pauseAtUnchosenFork: true,
        ).run();

    test('спуск встаёт на развилке, а не проходит её сам', () {
      final first = segment(const []);

      expect(first.awaitingFork, isTrue);
      expect(first.ending, RunEnding.atFork);
      expect(first.pendingFork, isNotNull);
      expect(first.pendingFork!.options, hasLength(2));
      expect(first.pendingFork!.options.first.id,
          isNot(first.pendingFork!.options.last.id),
          reason: 'развилка из двух одинаковых путей — это не выбор');
    });

    test('на стартовом этаже наёмник не встаёт', () {
      // Верёвка спускает сразу на глубину, кратную трём, и развилка выпадала
      // бы в ту же секунду, что и отправка: журнал пуст, уведомление
      // мгновенное, а спуска ещё не было.
      for (var bonus = 0; bonus < 6; bonus++) {
        final r = DescentSimulator(
          profile: HeroProfile(powerMultiplier: 6.0, startDepthBonus: bonus),
          seed: 31,
          forkChoices: const [],
          pauseAtUnchosenFork: true,
        ).run();

        expect(r.floors, isNotEmpty,
            reason: 'старт +$bonus: встал, не пройдя ни одного этажа');
      }
    });

    test('выбор пути меняет спуск, и заметно', () {
      List<int> walk(int option) {
        final choices = <int>[];
        var r = segment(choices);
        while (r.awaitingFork && choices.length < 200) {
          choices.add(option);
          r = segment(choices);
        }
        return choices;
      }

      final alwaysFirst = walk(0);
      final alwaysSecond = walk(1);

      final a = segment(alwaysFirst).maxDepth;
      final b = segment(alwaysSecond).maxDepth;

      expect(alwaysFirst.length, greaterThan(5),
          reason: 'развилок за спуск должно быть много, иначе выбор редок');
      expect(a, isNot(b),
          reason: 'если пути дают одно и то же, развилка косметическая');
    });

    test('спуск воспроизводится по списку решений тик в тик', () {
      // На этом стоит всё остальное: повтор боя, сохранение и пересчёт
      // отрезков. Состояние симуляции не хранится нигде — только решения.
      final choices = <int>[];
      var r = segment(choices);
      while (r.awaitingFork && choices.length < 200) {
        choices.add(choices.length % 2);
        r = segment(choices);
      }

      final again = segment(choices);
      expect(again.maxDepth, r.maxDepth);
      expect(again.totalSeconds, r.totalSeconds);
      expect(again.gold, r.gold);
      expect(again.echo, r.echo);
      expect(again.floors.length, r.floors.length);
    });
  });

  group('развилка в контракте', () {
    test('наёмник доходит, встаёт и ждёт', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);

      expect(contract.descending, isTrue);
      expect(contract.result!.awaitingFork, isTrue);

      p.refreshContracts(contract.segmentEndsAtUtc!);
      expect(contract.atFork, isTrue);
      expect(contract.pendingFork, isNotNull);
      expect(contract.awaitingCollection, isFalse,
          reason: 'он жив и стоит — забирать нечего');
    });

    test('решение игрока продолжает спуск с того же места', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      final arrivedAt = contract.segmentEndsAtUtc!;
      final depthAtFork = contract.result!.maxDepth;

      p.refreshContracts(arrivedAt);
      expect(p.chooseFork(contract, 1, arrivedAt), isTrue);

      expect(contract.forkChoices, [1]);
      expect(contract.descending, isTrue);
      expect(contract.result!.maxDepth, greaterThan(depthAtFork),
          reason: 'после решения спуск обязан продвинуться');
    });

    test('третий путь: обе награды и НИ ОДНОЙ платы', () {
      // Платой за него служит присутствие игрока, а не минус в бою. Так и
      // задумано: тот, кто зашёл и нажал, получает больше, чем наёмник,
      // решавший сам.
      //
      // Проверялось иначе дважды, и оба раза замер кампании говорил «хуже»:
      // с обеими платами — 103 этажа против 143, с более мягкой из двух —
      // 130. Обе версии были ловушкой, а не наградой.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      p.refreshContracts(contract.segmentEndsAtUtc!);

      final fork = contract.pendingFork!;
      final a = fork.options[0];
      final b = fork.options[1];
      final bold = fork.bold;

      expect(fork.allOptions, hasLength(3));
      expect(bold.penalties, isEmpty,
          reason: 'у третьего пути платы нет по определению');
      expect(bold.plus, contains(a.plus));
      expect(bold.plus, contains(b.plus));

      // Награды обоих на месте, и ни один минус не просочился.
      for (final source in [a, b]) {
        for (final e in source.rewards.entries) {
          expect(bold.value(e.key), isNot(0.0),
              reason: 'награда ${e.key.name} потерялась');
        }
        for (final e in source.penalties.entries) {
          expect(FloorModifierDef.isPenalty(e.key, bold.value(e.key)), isFalse,
              reason: 'плата ${e.key.name} просочилась в третий путь');
        }
      }
    });

    test('прибавка к редкости на третьем пути выключена', () {
      // Не осторожность, а замер: с прибавкой в два ранга третий путь
      // становился ВРЕДНЫМ — 135 этажей против 180. Редкие вещи это реликты,
      // автосборка их не надевает, а сундук ограничен: поток реликтов
      // вытеснял из него обычные вещи, которыми наёмник и одевается.
      //
      // Награда, которую некуда надеть, — это не награда.
      expect(Tuning.boldForkRarityBonus, 0,
          reason: 'прибавка к редкости травит сундук реликтами');
    });

    test('третий путь берётся только игроком, приказ его не видит', () {
      // Правило держится на устройстве кода, а не на договорённости: смелый
      // путь лежит отдельным полем, и у политики выбора его просто нет в
      // руках. Будь он третьим элементом `options`, приказ рано или поздно
      // выбрал бы его — не сегодня, так после правки оценок.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      final arrivedAt = contract.segmentEndsAtUtc!;

      p.refreshContracts(arrivedAt);
      expect(p.chooseFork(contract, Fork.boldIndex, arrivedAt), isTrue,
          reason: 'игрок вправе рискнуть');
      expect(contract.forkChoices, [Fork.boldIndex]);

      // А отсутствующий игрок его не получает: спуск, досчитанный приказом,
      // не содержит ни одного смелого решения.
      final absent = player();
      final theirs = absent.deploy(absent.roster.reserve.first, seed: 42);
      absent.refreshContracts(far());
      expect(theirs.forkChoices, isEmpty,
          reason: 'приказ решает, не записывая решений игрока');

      for (var depth = 3; depth < 60; depth += 3) {
        final rolled = ForkChooser.roll(theirs.seed, depth, theirs.forkPolicy);
        expect(rolled.chosen.id, isNot(rolled.bold.id),
            reason: 'приказ выбрал смелый путь на этаже $depth');
      }
    });

    test('плата оценивается против сборки, а не вообще', () {
      // Ради этого третий путь и существует как решение, а не как монетка:
      // приказ не знает, что у наёмника нет сопротивления огню, а игрок
      // видит. Замер показал, что «всегда смело» проигрывает по глубине —
      // значит выигрывать должно «смело там, где плата мимо».
      final fire = ContentPack.current.floorModifiers
          .firstWhere((m) => m.value(FloorEffect.resistFire) < 0.0);

      const bare = StatBlock();
      final naked = ForkCost.of(fire, bare, const []);
      expect(naked.harmless, isTrue,
          reason: 'терять нечего тому, у кого сопротивления нет');
      expect(naked.text, contains('огню'));

      const resistant = StatBlock(resistFire: 60.0);
      final costly = ForkCost.of(fire, resistant, const []);
      expect(costly.harmless, isFalse,
          reason: 'шестьдесят пунктов сопротивления — это потеря');
    });

    test('бесплатной названа только та плата, что мимо ЦЕЛИКОМ', () {
      // Один бесплатный минус из двух — это по-прежнему плата. Подсветить её
      // зелёным значило бы уговаривать игрока рискнуть.
      final hunger = ContentPack.current.floorModifiers
          .firstWhere((m) => m.disablesRegen);
      final fire = ContentPack.current.floorModifiers
          .firstWhere((m) => m.value(FloorEffect.resistFire) < 0.0);
      final both = FloorModifierDef.combine(hunger, fire);

      // Регена нет — половина платы мимо; сопротивление есть — вторая бьёт.
      const half = StatBlock(resistFire: 60.0);
      final cost = ForkCost.of(both, half, const []);

      expect(cost.text, isNotNull, reason: 'про бесплатную половину сказать надо');
      expect(cost.harmless, isFalse, reason: 'вторая половина всё ещё стоит');
    });

    test('решение вне развилки не принимается', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);

      expect(p.chooseFork(contract, 0, DateTime.now().toUtc()), isFalse,
          reason: 'он ещё идёт, спрашивать нечего');

      p.refreshContracts(contract.segmentEndsAtUtc!);
      expect(p.chooseFork(contract, 7, contract.segmentEndsAtUtc!), isFalse,
          reason: 'такого пути ему не предлагали');
    });

    test('простой не считается спуском', () {
      // Пока наёмник стоит, игровое время не идёт. Иначе журнал, полоска и
      // экран боя разошлись бы ровно на время раздумий игрока.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      final arrivedAt = contract.segmentEndsAtUtc!;

      p.refreshContracts(arrivedAt);
      final depth = contract.depthAt(arrivedAt);

      final thoughtLong = arrivedAt.add(const Duration(seconds: 30));
      expect(contract.depthAt(thoughtLong), depth,
          reason: 'наёмник стоит, а не спускается');

      p.chooseFork(contract, 0, thoughtLong);
      expect(contract.waitedSeconds, closeTo(30.0, 0.1));

      // И главное: простой вычитается только из времени ПОСЛЕ него. Иначе
      // журнал на пятой минуте показывал бы этаж, до которого наёмник дойдёт
      // только на шестой.
      final early = contract.startedAtUtc.add(const Duration(seconds: 1));
      expect(contract.waitedAt(early), 0.0);
    });

    test('не дождавшись, наёмник доходит спуск сам', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      final arrivedAt = contract.segmentEndsAtUtc!;

      p.refreshContracts(arrivedAt);
      expect(contract.atFork, isTrue);

      p.refreshContracts(arrivedAt
          .add(Duration(seconds: Tuning.forkWaitSeconds.round() + 1)));

      expect(contract.atFork, isFalse);
      expect(contract.result!.awaitingFork, isFalse,
          reason: 'остаток решает приказ, новых остановок не будет');
      expect(contract.waitedSeconds, closeTo(Tuning.forkWaitSeconds, 0.01),
          reason: 'отсутствие стоит ровно один простой за спуск');
    });

    test('за ночь офлайна контракт доходит до «забрать добычу»', () {
      // Догон делается циклом: за ночь случается три перехода подряд —
      // дошёл, простоял, доспустился. Любой пропущенный оставил бы контракт
      // в состоянии, которого не было.
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);

      final finished = p.refreshContracts(far());
      expect(finished, [contract]);
      expect(contract.awaitingCollection, isTrue);
      expect(contract.runFinished, isTrue);
    });

    test('стоящий на развилке занимает слот отправки', () {
      final p = player();
      final contract = p.deploy(p.roster.reserve.first, seed: 42);
      p.refreshContracts(contract.segmentEndsAtUtc!);

      expect(contract.atFork, isTrue);
      expect(p.hasActiveDescent, isTrue,
          reason: 'он в бездне, просто стоит');
    });

    test('приказ решает так же, как решил бы политикой весь спуск', () {
      // Отсутствующий игрок обязан получить РОВНО тот спуск, который был до
      // живых развилок: иначе правка молча сдвинула бы весь баланс.
      final p = player();
      final contract =
          p.deploy(p.roster.reserve.first, seed: 91, forkPolicy: ForkPolicy.safety);
      p.refreshContracts(far());

      final whole = DescentSimulator(
        profile: contract.replayProfile(),
        seed: contract.seed,
        brandRank: contract.brandRank,
        backpackCapacityOverride: contract.mercenary.backpackSlots,
        salvageRate: contract.outpost.salvageRate,
        outpostLootQuality: contract.outpost.lootQuality,
        outpostLootQuantity: contract.outpost.lootQuantity,
        restHealBonus: contract.outpost.restHealBonus,
        forkPolicy: contract.forkPolicy,
      ).run();

      expect(contract.result!.maxDepth, whole.maxDepth);
      expect(contract.result!.totalSeconds, whole.totalSeconds);
      expect(contract.result!.gold, whole.gold);
    });
  });
}
