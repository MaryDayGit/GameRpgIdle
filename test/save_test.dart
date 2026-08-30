import 'package:rift/core/balance/tuning.dart';
import 'dart:convert';

import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/quest_log.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/relic_effect.dart';
import 'package:rift/core/model/shard.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/save/migrations.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Сейв — единственное место, где ошибка стоит игроку всего прогресса.
/// Поэтому проверяется и то, что состояние переживает круг, и то, что сейв
/// открывается, когда контент под ним изменился.

/// Играем несколько контрактов, чтобы в профиле было что терять: наёмники
/// живые и павшие, снаряжение, сундук, Застава, незабранная добыча.
PlayerProfile _played({int contracts = 3}) {
  final profile = PlayerProfile();
  final rng = Rng(42);

  for (var i = 0; i < contracts; i++) {
    profile.refreshTavern(rng);
    final candidate = profile.roster.candidates.first;
    profile.gold += Roster.hireCost(candidate.rank);
    profile.hire(candidate);

    final contract = profile.deploy(candidate, seed: 100 + i);
    if (i < contracts - 1) {
      // Перематываем до предсказанной гибели: раньше добычу не забрать.
      profile.refreshContracts(
          DateTime.now().toUtc().add(const Duration(days: 30)));
      profile.collect(contract);
      profile.autoSpendEcho();
    }
  }

  profile.upgradeBuilding(Building.vault);
  return profile;
}

SaveData _roundTrip(PlayerProfile profile) {
  final saved = SaveData(
    lastSeenUtc: DateTime.utc(2026, 3, 14, 15, 9, 26),
    profile: profile,
  );
  return SaveData.decode(saved.encode());
}

void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('круг сохранения', () {
    test('состояние игрока переживает запись и чтение', () {
      final before = _played();
      final after = _roundTrip(before).profile;

      expect(after.gold, closeTo(before.gold, 1e-9));
      expect(after.echo, before.echo);
      expect(after.maxDepthEver, before.maxDepthEver);
      expect(after.startDepthBonus, before.startDepthBonus);
      expect(after.tree.nodesBought, before.tree.nodesBought);
      expect(after.tree.bought, before.tree.bought,
          reason: 'узлы древа именованные — важно КАКИЕ, а не сколько');

      for (final building in Building.values) {
        expect(after.outpost.levelOf(building), before.outpost.levelOf(building),
            reason: building.name);
      }

      expect(after.roster.reserve.length, before.roster.reserve.length);
      expect(after.roster.deployed.length, before.roster.deployed.length);
      expect(after.roster.fallen.length, before.roster.fallen.length);
      expect(after.stash.length, before.stash.length);

      // Снаряжение наёмников — отдельной проверкой. Списки одинаковой длины
      // не значат ничего: ростер может приехать целиком, а вещи на нём —
      // пропасть, и заметить это по количеству наёмников невозможно.
      for (var i = 0; i < before.roster.deployed.length; i++) {
        final a = before.roster.deployed[i].gear;
        final b = after.roster.deployed[i].gear;
        expect(b.filledSlots, a.filledSlots, reason: 'слотов занято');
        expect(b.bestIlvl, a.bestIlvl);
        expect(b.triggerIds, a.triggerIds);
      }
      expect(after.contracts.length, before.contracts.length);
      expect(after.hasUncollectedHaul, before.hasUncollectedHaul);
    });

    test('журнал заданий переживает круг', () {
      // Журнал — единственный источник открытых умений. Потеряться ему нельзя
      // молча: игрок откроет игру и обнаружит, что у него снова стартовый
      // набор, а сорок закрытых целей исчезли.
      final before = _played();
      before.quests.check(const QuestFacts(runsCompleted: 1, maxDepthEver: 40));
      before.quests.relicsFound = 3;

      expect(before.quests.doneCount, greaterThan(0),
          reason: 'проверять нечего, если ничего не закрыто');

      final after = _roundTrip(before).profile;

      expect(after.quests.completed, before.quests.completed,
          reason: 'задания именованные — важно КАКИЕ, а не сколько');
      expect(after.quests.runsCompleted, before.quests.runsCompleted);
      expect(after.quests.relicsFound, before.quests.relicsFound);
      expect(after.availableAbilities.map((a) => a.id),
          before.availableAbilities.map((a) => a.id));
    });

    test('сейв без заданий открывается со стартовым набором', () {
      // Старые сейвы журнала не знают, и это правда: у них всё открывало
      // древо Эха. Пустой журнал вернёт их к стартовому набору — зато цепочки
      // пройдутся заново и в правильном порядке.
      final saved = SaveData(
        lastSeenUtc: DateTime.utc(2026),
        profile: PlayerProfile(),
      );
      final raw = jsonDecode(saved.encode()) as Map<String, dynamic>;
      (raw['profile'] as Map).remove('quests');

      final loaded = SaveData.decode(jsonEncode(raw));
      expect(loaded.profile.quests.doneCount, 0);
      expect(loaded.profile.availableAbilities.every((a) => a.isStarter),
          isTrue);
    });

    test('время хранится в UTC и не плывёт', () {
      final saved = SaveData(
        lastSeenUtc: DateTime.utc(2026, 3, 14, 15, 9, 26),
        profile: PlayerProfile(),
      );
      final loaded = SaveData.decode(saved.encode());

      expect(loaded.lastSeenUtc.isUtc, isTrue);
      expect(loaded.lastSeenUtc, saved.lastSeenUtc);
    });

    test('предметы переживают круг целиком', () {
      final before = _played();
      expect(before.stash, isNotEmpty);

      final after = _roundTrip(before).profile;
      for (var i = 0; i < before.stash.length; i++) {
        final a = before.stash[i];
        final b = after.stash[i];
        expect(b.kind, a.kind);
        expect(b.ilvl, a.ilvl);
        expect(b.rarity, a.rarity);
        expect(b.twoHanded, a.twoHanded);
        expect(b.triggerAffixId, a.triggerAffixId);
        expect(b.relicId, a.relicId);
        expect(b.affixes.length, a.affixes.length);
        expect(b.stats.maxHp, closeTo(a.stats.maxHp, 1e-9));
        expect(b.stats.attackDamage, closeTo(a.stats.attackDamage, 1e-9));
        expect(b.implicit?.value, a.implicit?.value);
      }
    });

    test('решения на развилках переживают перезапуск', () {
      // Спуск — функция от снимка, сида и списка решений. Состояние симуляции
      // не хранится нигде, и потерять этот список значит потерять спуск: он
      // пересчитался бы приказом и разошёлся бы с тем, что игрок уже видел.
      final before = PlayerProfile.newGame(seed: 4)..gold = 50000;
      final contract = before.deploy(before.roster.reserve.first, seed: 77);
      final arrivedAt = contract.segmentEndsAtUtc!;

      before.refreshContracts(arrivedAt);
      expect(contract.atFork, isTrue, reason: 'проверять нечего без развилки');

      final decidedAt = arrivedAt.add(const Duration(seconds: 12));
      expect(before.chooseFork(contract, 1, decidedAt), isTrue);

      final after = _roundTrip(before).profile;
      final restored = after.contracts.first;

      expect(restored.forkChoices, [1]);
      expect(restored.waitedSeconds, closeTo(12.0, 0.01));
      expect(restored.pauses, hasLength(1));
      expect(restored.result!.maxDepth, contract.result!.maxDepth);
      expect(restored.result!.totalSeconds, contract.result!.totalSeconds);
    });

    test('наёмник, застигнутый на развилке, стоит там же после загрузки', () {
      final before = PlayerProfile.newGame(seed: 4)..gold = 50000;
      final contract = before.deploy(before.roster.reserve.first, seed: 77);
      before.refreshContracts(contract.segmentEndsAtUtc!);
      expect(contract.atFork, isTrue);

      final after = _roundTrip(before).profile;
      final restored = after.contracts.first;

      expect(restored.atFork, isTrue);
      expect(restored.pendingFork, isNotNull);
      expect(
        restored.pendingFork!.options.map((o) => o.id),
        contract.pendingFork!.options.map((o) => o.id),
        reason: 'после загрузки ему обязаны предложить те же два пути',
      );
      expect(restored.forkArrivedAtUtc, contract.forkArrivedAtUtc,
          reason: 'иначе после загрузки отсчёт ожидания пошёл бы заново');
    });

    test('не дождавшийся наёмник после загрузки не встаёт снова', () {
      // Флаг «терпение кончилось» — отдельный факт в сохранении. Без него
      // пересчёт после загрузки снова остановил бы спуск на той же развилке,
      // и наёмник, уже отказавшийся ждать, ждал бы снова — каждый раз, когда
      // игрок открывает приложение.
      final before = PlayerProfile.newGame(seed: 4)..gold = 50000;
      final contract = before.deploy(before.roster.reserve.first, seed: 77);
      final arrivedAt = contract.segmentEndsAtUtc!;

      before.refreshContracts(arrivedAt);
      before.refreshContracts(arrivedAt
          .add(Duration(seconds: Tuning.forkWaitSeconds.round() + 1)));
      expect(contract.forkWaitingSpent, isTrue);
      expect(contract.descending, isTrue);

      final restored = _roundTrip(before).profile.contracts.first;
      expect(restored.forkWaitingSpent, isTrue);
      expect(restored.result!.awaitingFork, isFalse,
          reason: 'спуск досчитан приказом, остановок больше нет');
      expect(restored.result!.maxDepth, contract.result!.maxDepth);
    });

    test('наёмник в контракте — тот же объект, что в ростере', () {
      final before = _played();
      final after = _roundTrip(before).profile;

      expect(after.contracts, isNotEmpty);
      final contract = after.contracts.first;
      expect(
        after.roster.deployed.any((m) => identical(m, contract.mercenary)),
        isTrue,
        reason: 'иначе снаряжение вернётся одному, а погибнет другой',
      );
    });

    test('добыча не распыляется заново при каждой загрузке', () {
      final before = _played();
      final haulBefore = before.contracts.first.haul!;
      final goldBefore = haulBefore.gold;
      final countBefore = haulBefore.salvagedCount;

      var profile = before;
      for (var i = 0; i < 3; i++) {
        profile = _roundTrip(profile).profile;
      }

      final haulAfter = profile.contracts.first.haul!;
      expect(haulAfter.gold, closeTo(goldBefore, 1e-6));
      expect(haulAfter.salvagedCount, countBefore);
      expect(haulAfter.items.length, haulBefore.items.length);
    });

    test('журнал этажей сохраняется вместе с результатом', () {
      final before = _played();
      final resultBefore = before.contracts.first.result!;
      expect(resultBefore.floors, isNotEmpty);

      final after = _roundTrip(before).profile;
      final resultAfter = after.contracts.first.result!;

      expect(resultAfter.maxDepth, resultBefore.maxDepth);
      expect(resultAfter.ending, resultBefore.ending);
      expect(resultAfter.floors.length, resultBefore.floors.length);
      expect(resultAfter.floors.last.depth, resultBefore.floors.last.depth);
      expect(resultAfter.floors.last.modifierId,
          resultBefore.floors.last.modifierId);
    });

    test('перечисления пишутся именами, а не номерами', () {
      // Перестановка значений в enum не должна превращать «Легенду»
      // в «Оборванца».
      final profile = PlayerProfile();
      profile.roster.reserve.add(Mercenary(
        id: 'm',
        name: 'Тест',
        rank: MercRank.legend,
        trait: MercTrait.lucky,
      ));

      final text =
          SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
              .encode();
      expect(text, contains('"rank":"legend"'));
      expect(text, contains('"trait":"lucky"'));
    });
  });

  group('снисходительность к изменившемуся контенту', () {
    Map<String, dynamic> _rawOf(PlayerProfile profile) => jsonDecode(
          SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
              .encode(),
        ) as Map<String, dynamic>;

    test('исчезнувший реликт снимается, предмет остаётся', () {
      final profile = PlayerProfile();
      profile.stash.add(Item(
        kind: GearKind.ring,
        ilvl: 40,
        rarity: Rarity.relic,
        affixes: [
          const AffixRoll(
            affixId: 'max_hp_flat',
            stat: StatKey.maxHp,
            percentile: 0.9,
            value: 123.0,
          )
        ],
        relicId: 'seal_of_thousand_eyes',
        relicEffect: RelicEffect.eternalCurse,
      ));

      final raw = _rawOf(profile);
      (raw['profile']['stash'][0] as Map)['relic'] = 'вырезан_в_патче';

      final loaded = SaveData.decode(jsonEncode(raw));
      final item = loaded.profile.stash.single;

      expect(item.relicId, isNull);
      expect(item.stats.maxHp, 123.0, reason: 'статы предмета не пострадали');
      expect(loaded.issues!.isNotEmpty, isTrue);
    });

    test('исчезнувший аффикс выбрасывается, остальные живут', () {
      final profile = PlayerProfile();
      profile.stash.add(Item(
        kind: GearKind.amulet,
        ilvl: 20,
        rarity: Rarity.rare,
        affixes: const [
          AffixRoll(
            affixId: 'a',
            stat: StatKey.maxHp,
            percentile: 1.0,
            value: 50.0,
          ),
          AffixRoll(
            affixId: 'b',
            stat: StatKey.armor,
            percentile: 1.0,
            value: 10.0,
          ),
        ],
      ));

      final raw = _rawOf(profile);
      ((raw['profile']['stash'][0] as Map)['affixes'] as List)[0]['stat'] =
          'мана';

      final loaded = SaveData.decode(jsonEncode(raw));
      final item = loaded.profile.stash.single;

      expect(item.affixes, hasLength(1));
      expect(item.stats.armor, 10.0);
      expect(loaded.issues!.isNotEmpty, isTrue);
    });

    test('наёмник без ранга выбрасывается вместе со своим контрактом', () {
      final profile = _played(contracts: 1);
      final raw = _rawOf(profile);
      (raw['profile']['roster']['deployed'][0] as Map)['rank'] = 'полубог';

      final loaded = SaveData.decode(jsonEncode(raw));

      expect(loaded.profile.roster.deployed, isEmpty);
      expect(loaded.profile.contracts, isEmpty,
          reason: 'контракт без наёмника нечем закрывать');
      expect(loaded.issues!.length, greaterThanOrEqualTo(2));
    });

    test('предмет в чужом слоте не надевается', () {
      final profile = _played(contracts: 1);
      final raw = _rawOf(profile);
      final gear = raw['profile']['roster']['deployed'][0]['gear'] as List;

      // Кладём шлем в слот оружия.
      gear[0] = {
        'kind': 'helmet',
        'ilvl': 10,
        'rarity': 'common',
        'twoHanded': false,
        'affixes': <dynamic>[],
      };

      final loaded = SaveData.decode(jsonEncode(raw));
      expect(loaded.profile.roster.deployed.first.gear.at(0), isNull);
      expect(loaded.issues!.isNotEmpty, isTrue);
    });
  });

  group('отказы', () {
    test('битый JSON, отсутствующая версия и версия из будущего', () {
      expect(() => SaveData.decode('не json'), throwsA(isA<SaveException>()));
      expect(() => SaveData.decode('[]'), throwsA(isA<SaveException>()));
      expect(() => SaveData.decode('{"profile":{}}'),
          throwsA(isA<SaveException>()));
      expect(
        () => SaveData.decode('{"version":999,"profile":{}}'),
        throwsA(isA<SaveException>()),
        reason: 'сейв новее игры читать нельзя — молча потеряем данные',
      );
    });

    test('разорванная цепочка миграций — отказ, а не догадки', () {
      const migrations = SaveMigrations([]);
      expect(
        () => SaveData.decode(
          '{"version":1,"profile":{}}',
          migrations: migrations,
          targetVersion: 3,
        ),
        throwsA(isA<SaveException>()),
      );
    });
  });

  group('миграции', () {
    test('ступени применяются по одной и по порядку', () {
      final applied = <int>[];
      final migrations = SaveMigrations([
        SaveMigration(1, (raw) {
          applied.add(1);
          return {...raw, 'version': 2};
        }),
        SaveMigration(2, (raw) {
          applied.add(2);
          return {...raw, 'version': 3, 'profile': {'gold': 777}};
        }),
      ]);

      final loaded = SaveData.decode(
        '{"version":1,"profile":{"gold":1}}',
        migrations: migrations,
        targetVersion: 3,
      );

      expect(applied, [1, 2], reason: 'прыжок через ступень не проверяем ничем');
      expect(loaded.profile.gold, 777.0);
      expect(loaded.version, 3);
    });

    test('сейв первой версии получает приказ, который у него был', () {
      // Первая настоящая ступень цепочки. До второй версии политика была
      // одна, и старый контракт обязан открыться именно с ней: спуск в нём
      // посчитан, и повтор с другим приказом показал бы другой бой.
      final player = PlayerProfile.newGame(seed: 31337);
      final contract = player.deploy(player.roster.reserve.first,
          seed: 31337, forkPolicy: ForkPolicy.echo);

      final raw = jsonDecode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: player)
            .encode(),
      ) as Map<String, dynamic>;

      // Откатываем сейв к первой версии: поля приказа тогда не было.
      raw['version'] = 1;
      for (final c in (raw['profile'] as Map)['contracts'] as List) {
        (c as Map).remove('forkPolicy');
      }

      final loaded = SaveData.decode(jsonEncode(raw));
      expect(loaded.version, SaveData.currentVersion);
      expect(loaded.profile.contracts.single.forkPolicy, ForkPolicy.loot,
          reason: 'старому контракту нельзя приписать приказ, которого не было');

      // А новый сейв доносит приказ как есть.
      final again = SaveData.decode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: player).encode(),
      );
      expect(again.profile.contracts.single.forkPolicy, contract.forkPolicy);
    });
  });

  group('крафт переживает сейв', () {
    test('осколки и следы крафта на предмете сохраняются', () {
      final profile = PlayerProfile(gold: 1e9, maxDepthEver: 100);
      profile.stash.add(Item(
        kind: GearKind.amulet,
        ilvl: 40,
        rarity: Rarity.rare,
        affixes: const [
          AffixRoll(
            affixId: 'max_hp_flat',
            stat: StatKey.maxHp,
            percentile: 0.93,
            value: 500.0,
            rerolls: 3,
          ),
        ],
        deepenings: 2,
        bonusAffixSlots: 1,
      ));
      profile.shards.add(const Shard(
        affixId: 'crit_chance',
        stat: StatKey.critChance,
        percentile: 0.88,
      ));

      final loaded = SaveData.decode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
            .encode(),
      ).profile;

      final item = loaded.stash.single;
      expect(item.affixes.single.rerolls, 3,
          reason: 'иначе цена реролла сбрасывается при каждой загрузке');
      expect(item.deepenings, 2);
      expect(item.bonusAffixSlots, 1);

      final shard = loaded.shards.single;
      expect(shard.affixId, 'crit_chance');
      expect(shard.percentile, closeTo(0.88, 1e-9));
      expect(shard.quality, 88);
    });
  });
}
