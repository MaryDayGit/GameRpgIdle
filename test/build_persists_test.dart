import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/model/equipment.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Сборка, которую игрок собрал руками, уходит вниз как есть — и вещи
/// возвращаются.
///
/// Живой прогон дал это прямо: «билд, который ты собираешь на наёмника,
/// должен оставаться; вещи, которые ты на него одеваешь и отправляешь в
/// спуск, приходят тебе после окончания». Оказалось, что отправка
/// ПЕРЕСОБИРАЛА снаряжение заново — «наёмник берёт лучшее из сундука», — и
/// надетое игроком заменялось тем, что выше по оценке.
///
/// Правило теперь одно и оно проверяется здесь: **оценка не знает, зачем
/// игрок надел именно это, а игрок знает.** Досбор остался только в пустые
/// слоты.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  PlayerProfile player({int stashSlots = 8}) {
    final profile = PlayerProfile(
      gold: 1e6,
      outpost: Outpost({Building.vault: stashSlots}),
    );
    profile.roster.reserve.add(MercFactory.roll(Rng(1), idPrefix: 'b'));
    return profile;
  }

  Item roll(Rng rng, GearKind kind, {int ilvl = 40, bool relic = false}) =>
      ItemFactory.roll(
          rng: rng, ilvl: ilvl, kind: kind, forceRelic: relic);

  group('сборка уходит вниз как есть', () {
    test('надетое игроком не подменяется на «лучшее из сундука»', () {
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(5);

      // Игрок надел СЛАБОЕ оружие. Причина может быть любой — свойство под
      // его сборку, тег под его умения; игра о ней не знает и знать не может.
      final chosen = roll(rng, GearKind.weapon, ilvl: 5);
      merc.gear.equipTo(0, chosen);

      // А в сундуке лежит оружие вдвое глубже. Раньше оно бы и ушло вниз.
      for (var i = 0; i < 4; i++) {
        profile.stash.add(roll(rng, GearKind.weapon, ilvl: 60));
      }

      final contract = profile.deploy(merc, seed: 1);

      expect(contract.loadout.at(0), same(chosen),
          reason: 'вниз ушло то, что надел игрок');
    });

    test('пустые слоты досбираются: новичок не уходит голым', () {
      // Игрок, ни разу не открывавший сборку, всё равно должен уйти одетым:
      // иначе правило «сборка остаётся» превращается в наказание за то, что
      // человек не нашёл экран.
      final profile = player(stashSlots: 8);
      final merc = profile.roster.reserve.first;
      final rng = Rng(7);

      for (final kind in GearKind.values) {
        profile.stash.add(roll(rng, kind));
      }
      // Наёмник приходит из Таверны с оружием и доспехом — остальное пусто.
      final dressed = merc.gear.filledSlots;

      final contract = profile.deploy(merc, seed: 2);
      expect(contract.loadout.filledSlots, greaterThan(dressed + 4),
          reason: 'пустые слоты дособрались из сундука');
    });

    test('досбор не трогает уже надетое', () {
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(9);

      final helmet = roll(rng, GearKind.helmet, ilvl: 3);
      merc.gear.equipTo(2, helmet);

      for (final kind in GearKind.values) {
        profile.stash.add(roll(rng, kind, ilvl: 70));
      }

      final contract = profile.deploy(merc, seed: 3);

      // Снимок контракта — это то, что ушло вниз, и оно же вернётся:
      // наёмник не переодевается.
      expect(contract.loadout.at(2), same(helmet),
          reason: 'шлем игрока ушёл вниз');
      expect(contract.loadout.filledSlots, greaterThan(2),
          reason: 'остальное всё-таки дособралось');
    });

    test('реликт из сундука сам не надевается', () {
      // Реликт меняет ПРАВИЛО боя: «активок нет», «критов нет», «−65 % HP».
      // Такое решение принимает игрок. Замер уже показывал, чем кончается
      // обратное: наёмник исправно подбирал реликты, ломавшие его же сборку,
      // и точка равновесия кампании падала вдвое.
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(11);

      final relic = roll(rng, GearKind.helmet, ilvl: 60, relic: true);
      expect(relic.isRelic, isTrue);
      profile.stash.add(relic);

      final contract = profile.deploy(merc, seed: 4);

      expect(contract.loadout.at(2), isNot(same(relic)));
      expect(profile.stash, contains(relic),
          reason: 'реликт остался в сундуке и ждёт решения игрока');
    });

    test('надетый игроком реликт уходит вниз', () {
      // Запрет на АВТОМАТИЧЕСКИЙ подбор не должен превращаться в запрет
      // вообще: игрок, надевший реликт руками, сделал выбор.
      final profile = player();
      final merc = profile.roster.reserve.first;
      final relic = roll(Rng(13), GearKind.helmet, ilvl: 60, relic: true);

      merc.gear.equipTo(2, relic);
      final contract = profile.deploy(merc, seed: 5);

      expect(contract.loadout.at(2), same(relic));
    });
  });

  group('вещи возвращаются', () {
    test('всё надетое приходит обратно в сундук', () {
      final profile = player(stashSlots: 8);
      final merc = profile.roster.reserve.first;
      final rng = Rng(17);

      for (final kind in GearKind.values) {
        profile.stash.add(roll(rng, kind));
      }

      final contract = profile.deploy(merc, seed: 6);
      final sent = [
        for (var i = 0; i < 9; i++)
          if (contract.loadout.at(i) case final item?) item,
      ];
      expect(sent, isNotEmpty, reason: 'проверять нечего, если ушёл голым');

      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      profile.collect(contract);

      // Каждая отправленная вещь вернулась — она всё это время была на
      // наёмнике, он её не снимал.
      for (final item in sent) {
        expect(profile.stash, contains(item),
            reason: '${item.kind.ru} ${item.ilvl} ур. не вернулся');
      }
    });

    test('ничего не пропадает: до и после сходится', () {
      // Самая сильная проверка из возможных: сумма вещей на входе и на выходе
      // равна, а всё, чего не хватает, посчитано — рюкзак наёмника и нехватка
      // места в сундуке. Молча исчезнуть не может ничего.
      final profile = player(stashSlots: 8);
      final merc = profile.roster.reserve.first;
      final rng = Rng(19);

      for (final kind in GearKind.values) {
        profile.stash.add(roll(rng, kind));
      }
      // Считаем и то, что уже надето: наёмник приходит из Таверны с оружием
      // и доспехом, и они тоже вернутся в сундук.
      final before = profile.stash.length + merc.gear.filledSlots;

      final contract = profile.deploy(merc, seed: 7);
      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));

      final result = contract.result!;
      final found = result.itemsFound;

      profile.collect(contract);

      // Рюкзак стал бесконечным: наёмник несёт наверх ВСЁ, и в спуске больше
      // ничего не распыляется. Находки ждут в разборе, снаряжение сразу в
      // сундуке — сумма обязана сойтись без единой потери.
      expect(result.haul.salvagedCount, 0,
          reason: 'бесконечный рюкзак ничего не распыляет по дороге');

      final after = profile.stash.length + profile.pendingLoot.length;
      expect(after + profile.lastStashOverflow, before + found,
          reason: 'в сундуке ${profile.stash.length}, в разборе '
              '${profile.pendingLoot.length}, было $before, найдено $found, '
              'не влезло ${profile.lastStashOverflow}');

      // И только после разбора вещи расходятся по решениям игрока.
      profile.autoSortLoot();
      expect(profile.pendingLoot, isEmpty);
      expect(profile.stash.length, lessThanOrEqualTo(profile.outpost.stashSlots));
    });

    test('переполнение сундука не молчит', () {
      // Место кончилось — значит что-то ушло в переплавку. Счётчик существует
      // ровно затем, чтобы экран мог об этом сказать: игрок отправлял
      // наёмника с этими вещами и ждёт их обратно.
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(23);

      // Забиваем сундук под завязку: возвращаться будет некуда.
      while (profile.stash.length < profile.outpost.stashSlots) {
        profile.stash.add(roll(rng, GearKind.ring, ilvl: 60));
      }

      final contract = profile.deploy(merc, seed: 8);
      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      profile.collect(contract);

      expect(profile.lastStashOverflow, greaterThan(0),
          reason: 'сундук был полон — что-то обязано было переплавиться');
      expect(profile.stash.length, profile.outpost.stashSlots);
    });

    test('счётчик переполнения сбрасывается на каждом получении', () {
      final profile = player(stashSlots: 8);
      final merc = profile.roster.reserve.first;
      profile.stash.add(roll(Rng(29), GearKind.ring));

      final contract = profile.deploy(merc, seed: 9);
      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      profile.collect(contract);

      expect(profile.lastStashOverflow, 0,
          reason: 'места хватило — терять было нечего');
    });
  });

  test('наёмник не переодевается в спуске', () {
    // Правило, которое заменило прежнее «профессионал надевает лучшее»:
    // сборка — единственное место, где игрок принимает решения о бое, и
    // автоматика не вправе её править ни до отправки, ни внизу.
    //
    // Проверяется на многих сидах: находки случайны, и на одном спуске
    // подмены могло бы просто не случиться.
    for (var seed = 1; seed <= 40; seed++) {
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(seed * 17);

      for (final kind in GearKind.values) {
        merc.gear.equipTo(Equipment.slotKinds.indexOf(kind),
            roll(rng, kind, ilvl: 2));
      }

      final contract = profile.deploy(merc, seed: seed);
      // Спуск считается отрезками до развилок, и при отправке посчитан только
      // первый. Ждём весь: вопрос теста — что происходит ЗА СПУСК, а не за
      // первые два этажа.
      profile.refreshContracts(
          DateTime.now().toUtc().add(const Duration(days: 1)));

      expect(contract.result!.itemsFound, greaterThan(0),
          reason: 'сид $seed: проверять нечего, если он ничего не нашёл');

      for (var i = 0; i < Equipment.slotCount; i++) {
        expect(merc.gear.at(i), same(contract.loadout.at(i)),
            reason: 'сид $seed, слот $i: снаряжение изменилось за спуск');
      }
    }
  });

  test('на сотне спусков не теряется ни одна вещь', () {
    // Один сид проверяет один спуск. Потеря, случающаяся в трети случаев,
    // на одном сиде не видна — а именно такой она и была, пока наёмник ещё
    // переодевался внизу. Проверка остаётся и после того, как подмены не
    // стало: она сторожит весь путь вещи домой, а не одну её причину.
    var sentTotal = 0;
    var lost = 0;

    for (var seed = 1; seed <= 100; seed++) {
      final profile = player();
      final merc = profile.roster.reserve.first;
      final rng = Rng(seed * 31);

      // Одеваем ЗАВЕДОМО СЛАБЫМ: такая вещь первой идёт под нож, если
      // рюкзак решает по уровню. Именно её и надо уберечь — низкоуровневая
      // вещь с нужным свойством теперь осмысленный выбор.
      for (final kind in GearKind.values) {
        merc.gear.equipTo(Equipment.slotKinds.indexOf(kind),
            roll(rng, kind, ilvl: 3 + seed % 5));
      }

      final contract = profile.deploy(merc, seed: seed);
      final sent = [
        for (var i = 0; i < Equipment.slotCount; i++)
          if (contract.loadout.at(i) case final item?) item,
      ];

      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      profile.collect(contract);

      expect(profile.lastStashOverflow, 0,
          reason: 'сундук большой — проверяется возврат, а не переполнение');

      sentTotal += sent.length;
      for (final item in sent) {
        if (!profile.stash.any((s) => identical(s, item))) lost++;
      }
    }

    expect(sentTotal, greaterThan(500), reason: 'проверка должна быть весомой');
    expect(lost, 0, reason: 'потеряно $lost вещей из $sentTotal');
  });

  test('оценка вещи знает, чем бьёт наёмник', () {
    // Досбор пустых слотов всё равно опирается на оценку, а она обязана
    // считать сборку целиком: иначе наёмник со сборкой на чарах уйдёт вниз с
    // пустой левой рукой, потому что сила чар стоит для неё ноль.
    final profile = player();
    final merc = profile.roster.reserve.first;
    merc.abilities
      ..clear()
      ..addAll(['spark_bolt', 'ember_burst']);

    final rng = Rng(31);
    for (var i = 0; i < 6; i++) {
      profile.stash.add(roll(rng, GearKind.offhand, ilvl: 50));
    }

    profile.deploy(merc, seed: 10);
    final stats = profile.heroProfileFor(merc).aggregate();

    expect(stats.spellPower, greaterThan(Tuning.heroBase.spellPower),
        reason: 'левая рука даёт силу чар, и сборка на чарах её получила');
  });
}
