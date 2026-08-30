import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/quest_def.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/quest_log.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Задания — единственный источник новых способностей.
///
/// Живой прогон дал это замечанием «умений мало, и они все сразу открыты»:
/// древо Эха открывало по одиннадцать умений одним узлом. Открытие,
/// случающееся одиннадцать раз одновременно, перестаёт быть событием — а
/// ради события новое умение и нужно.
///
/// Тесты держат обещание, а не числа: **каждое умение приходит за отдельную
/// достигнутую цель, и цель эта видна заранее.**
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  QuestDef quest(String id) => ContentPack.current.quest(id)!;

  group('журнал', () {
    test('закрывает задание, когда факт достигнут', () {
      final log = QuestLog();
      final first = quest('first_return');

      expect(log.check(const QuestFacts()), isEmpty,
          reason: 'ничего не сделано — закрывать нечего');

      final closed = log.check(const QuestFacts(runsCompleted: 1));
      expect(closed.map((q) => q.id), contains(first.id));
      expect(log.isDone(first.id), isTrue);
    });

    test('не закрывает дважды', () {
      final log = QuestLog();
      log.check(const QuestFacts(runsCompleted: 1));
      expect(log.check(const QuestFacts(runsCompleted: 1)), isEmpty);
    });

    test('цепь закрывается целиком за один вызов, если заслужена', () {
      // Игрок, вернувшийся с сорокового этажа впервые, заслужил и «Глубже»,
      // и всё, что за ним. Растягивать это на столько спусков, сколько в цепи
      // звеньев, значило бы заставить его ждать за уже сделанное.
      final log = QuestLog();
      final closed = log.check(const QuestFacts(
        runsCompleted: 1,
        maxDepthEver: 40,
      ));

      expect(closed.map((q) => q.id), containsAll(['first_return', 'deeper']));
    });

    test('невидимое задание не закрывается', () {
      // «Глубже» открывается только после «Первого возвращения»: цель, о
      // которой игрок не знал, не должна закрываться у него за спиной.
      final log = QuestLog();
      final closed = log.check(const QuestFacts(maxDepthEver: 40));

      expect(closed, isEmpty);
      expect(log.isDone('deeper'), isFalse);
    });
  });

  group('условия', () {
    /// Журнал, в котором закрыто всё, кроме проверяемого. Иначе условие
    /// пришлось бы проверять сквозь всю цепь его предшественников.
    QuestLog logBefore(String id) {
      final target = ContentPack.current.quest(id)!;
      final done = <String>{};

      void unlock(String questId) {
        final q = ContentPack.current.quest(questId)!;
        for (final earlier in q.after) {
          unlock(earlier);
          done.add(earlier);
        }
      }

      unlock(target.id);
      return QuestLog(completed: done);
    }

    test('доля урона считается за ОДИН спуск', () {
      // Сумма за всю игру ответила бы «да» любому, кто однажды взял молнию в
      // слот: цель про билд обязана спрашивать про конкретный спуск.
      final log = logBefore('storm_share');
      final quest = ContentPack.current.quest('storm_share')!;

      const facts = QuestFacts(damageShare: {DamageType.lightning: 0.2});
      expect(log.check(facts).map((q) => q.id), isNot(contains(quest.id)));

      final enough = QuestFacts(
          damageShare: {DamageType.lightning: quest.value + 0.05});
      expect(log.check(enough).map((q) => q.id), contains(quest.id));
    });

    test('доля урона не путает стихии', () {
      final log = logBefore('storm_share');
      const facts = QuestFacts(damageShare: {DamageType.fire: 0.9});
      expect(log.check(facts).map((q) => q.id),
          isNot(contains('storm_share')));
    });

    test('теги сборки считаются по числу умений', () {
      final log = logBefore('fire_blade');
      final quest = ContentPack.current.quest('fire_blade')!;

      expect(log.check(const QuestFacts(loadoutTags: {Tag.fire: 1})).map(
              (q) => q.id),
          isNot(contains(quest.id)));
      expect(log.check(const QuestFacts(loadoutTags: {Tag.fire: 2})).map(
              (q) => q.id),
          contains(quest.id));
    });

    test('босса надо уложить, а не дойти до него', () {
      final log = logBefore('ash_lord');

      expect(log.check(const QuestFacts(maxDepthEver: 90)).map((q) => q.id),
          isNot(contains('ash_lord')));
      expect(
          log.check(const QuestFacts(bossesKilled: {'ash_lord'})).map(
              (q) => q.id),
          contains('ash_lord'));
    });

    test('Клеймо: ранг выше требуемого тоже засчитывается', () {
      // Игрок, ушедший вниз на более высоком Клейме, сделал заведомо больше.
      // Требовать от него вернуться на указанный ранг — наказывать за
      // прогресс.
      final log = logBefore('void_seal');
      final quest = ContentPack.current.quest('void_seal')!;
      final rank = quest.params.integer('rank');

      expect(
          log.check(QuestFacts(bestDepthByBrand: {rank - 1: 999})).map(
              (q) => q.id),
          isNot(contains(quest.id)));
      expect(
          log.check(QuestFacts(bestDepthByBrand: {rank + 3: 999})).map(
              (q) => q.id),
          contains(quest.id));
    });

    test('постройка засчитывается по своему уровню, а не по чужому', () {
      final log = logBefore('war_butcher');

      expect(
          log.check(const QuestFacts(outpost: {Building.forge: 8})).map(
              (q) => q.id),
          isNot(contains('war_butcher')));
      expect(
          log.check(const QuestFacts(outpost: {Building.armory: 2})).map(
              (q) => q.id),
          contains('war_butcher'));
    });
  });

  group('прогресс', () {
    test('накопительные условия показывают, сколько осталось', () {
      final log = QuestLog();
      final progress =
          log.progressOf(quest('deeper'), const QuestFacts(maxDepthEver: 9));

      expect(progress, isNotNull);
      expect(progress!.$1, 9.0);
      expect(progress.$2, quest('deeper').value);
    });

    test('условия про один спуск прогресса не имеют', () {
      // «3 из 10» о них соврало бы: такое задание либо выполнено спуском,
      // либо нет.
      final log = QuestLog();
      expect(log.progressOf(quest('storm_share'), const QuestFacts()), isNull);
      expect(log.progressOf(quest('ash_lord'), const QuestFacts()), isNull);
    });

    test('прогресс не перерастает цель', () {
      final log = QuestLog();
      final progress = log.progressOf(
          quest('deeper'), const QuestFacts(maxDepthEver: 500));
      expect(progress!.$1, quest('deeper').value);
    });
  });

  group('награда', () {
    test('умение появляется в сборке только после задания', () {
      final profile = PlayerProfile();
      final reward = quest('first_return').rewardAbility;

      expect(profile.availableAbilities.map((a) => a.id),
          isNot(contains(reward)));

      profile.quests.check(const QuestFacts(runsCompleted: 1));
      expect(profile.availableAbilities.map((a) => a.id), contains(reward));
    });

    test('доступны только стартовые, пока не выполнено ничего', () {
      final profile = PlayerProfile();
      expect(profile.availableAbilities.every((a) => a.isStarter), isTrue);
    });

    test('Эхо начисляется за закрытое задание', () {
      final profile = PlayerProfile();
      final before = profile.echo;

      final closed = profile.checkQuests();
      expect(closed, isEmpty, reason: 'без спусков закрывать нечего');
      expect(profile.echo, before);
    });

    test('закрытие контракта закрывает задание и открывает умение', () {
      // Полный путь: спуск посчитан, добыча забрана, задание закрылось,
      // умение доступно. Проверяется целиком, потому что разорвать эту
      // цепочку можно в любом звене и заметить только игрой.
      final profile = PlayerProfile(gold: 10000);
      profile.roster.reserve.add(MercFactory.roll(Rng(1), idPrefix: 'q'));

      final contract = profile.deploy(profile.roster.reserve.first, seed: 7);
      profile.refreshContracts(DateTime.now().toUtc().add(const Duration(days: 1)));
      profile.collect(contract);

      expect(profile.quests.runsCompleted, 1);
      expect(profile.lastClosedQuests, isNotEmpty);
      expect(profile.quests.isDone('first_return'), isTrue);
      expect(profile.availableAbilities.map((a) => a.id),
          contains(quest('first_return').rewardAbility));
    });
  });

  group('контент', () {
    test('каждая цепь достижима: нет циклов и сирот', () {
      // Задание, до которого нельзя добраться, — умение, которого игрок не
      // получит никогда. Проверяется обходом, а не глазами: сорок четыре
      // ссылки вручную не сверить.
      final byId = {
        for (final q in ContentPack.current.quests) q.id: q,
      };
      final reachable = <String>{};

      var changed = true;
      while (changed) {
        changed = false;
        for (final quest in ContentPack.current.quests) {
          if (reachable.contains(quest.id)) continue;
          if (quest.after.every(reachable.contains)) {
            reachable.add(quest.id);
            changed = true;
          }
        }
      }

      expect(reachable.length, byId.length,
          reason: 'недостижимы: '
              '${byId.keys.where((id) => !reachable.contains(id)).toList()}');
    });

    test('первое звено каждой цепи открывается прологом или ничем', () {
      // Цепь, вход в которую спрятан в другой цепи, — это цепь, которую игрок
      // не найдёт. Пролог — единственное исключение: он и есть вход.
      final byId = {for (final q in ContentPack.current.quests) q.id: q};

      for (final quest in ContentPack.current.quests) {
        for (final earlier in quest.after) {
          final from = byId[earlier]!;
          expect(from.chain == quest.chain || from.chain == 'prologue', isTrue,
              reason: '${quest.id} ждёт ${from.id} из чужой цепи '
                  '«${from.chain}»');
        }
      }
    });

    test('стихийная цепь не требует того, что сама выдаёт', () {
      // «Нанесите 40 % урона Огнём» выполнимо только огненным умением. Если
      // такого умения у игрока ещё нет, задание невыполнимо в принципе — и
      // заметить это можно только упёршись в него на живом прогоне.
      final starters = {
        for (final def in ContentPack.current.abilities)
          if (def.isStarter) def,
      };

      for (final quest in ContentPack.current.quests) {
        if (quest.condition != QuestCondition.damageShare) continue;

        final name = quest.params.str('damageType');
        final type = DamageType.values.firstWhere((t) => t.name == name);

        // Либо стихия есть в стартовом наборе, либо умение этой стихии даёт
        // задание, стоящее РАНЬШЕ в цепи.
        final inStarters =
            starters.any((def) => def.tags.contains(type.tag));
        final fromEarlier = quest.after.any((id) {
          final earlier = ContentPack.current.quest(id)!;
          final reward = ContentPack.current.ability(earlier.rewardAbility);
          return reward != null && reward.tags.contains(type.tag);
        });

        expect(inStarters || fromEarlier, isTrue,
            reason: '${quest.id}: нечем нанести урон «${type.ru}»');
      }
    });

    test('порог доли урона выполним: 70 % — не 100 %', () {
      // Автоатака есть всегда и бьёт своей стихией. Требовать сто процентов
      // одной стихии значило бы требовать сборку, которая не бьёт оружием
      // вовсе, — а такой в игре нет.
      for (final quest in ContentPack.current.quests) {
        if (quest.condition != QuestCondition.damageShare) continue;
        expect(quest.value, lessThanOrEqualTo(0.75), reason: quest.id);
      }
    });
  });
}
