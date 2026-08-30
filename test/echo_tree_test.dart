import 'dart:convert';

import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/echo_tree_def.dart';
import 'package:rift/core/model/echo_tree.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/sim/crafting.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Древо Эха (GDD §8.3) — единственная прогрессия, переживающая смерть
/// наёмника. Главная проверка тут одна: узел, которого не читает симуляция,
/// — это текст на экране. Поэтому у каждого правила есть свой тест.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('порядок и цена', () {
    test('ветка открывается по порядку', () {
      final tree = EchoTree();
      final blood = tree.branches.firstWhere((b) => b.id == 'blood');

      expect(tree.isAvailable(blood.nodes.first.id), isTrue);
      expect(tree.isAvailable(blood.nodes[1].id), isFalse,
          reason: 'второй узел закрыт первым');

      expect(tree.buy(blood.nodes.first.id, 1000), isNotNull);
      expect(tree.isAvailable(blood.nodes[1].id), isTrue);
      expect(tree.isAvailable(blood.nodes.first.id), isFalse,
          reason: 'купленный узел не покупается второй раз');
    });

    test('первый узел каждой ветки доступен сразу', () {
      // Иначе выбора нет: игрок вынужден идти той веткой, что открыта.
      final tree = EchoTree();
      for (final branch in tree.branches) {
        expect(tree.isAvailable(branch.nodes.first.id), isTrue,
            reason: branch.name);
      }
    });

    test('цена растёт от числа купленных, а не от ветки', () {
      final tree = EchoTree();
      final first = tree.nextNodeCost;

      tree.buy(tree.branches.first.nodes.first.id, 100000);
      final second = tree.nextNodeCost;

      expect(second, greaterThan(first));
      expect(tree.buy(tree.branches[1].nodes.first.id, second.floor() - 1),
          isNull,
          reason: 'узел другой ветки стоит столько же');
    });

    test('не по карману — не покупается', () {
      final tree = EchoTree();
      expect(tree.buy(tree.branches.first.nodes.first.id, 0), isNull);
      expect(tree.nodesBought, 0);
    });
  });

  group('правила действуют в симуляции', () {
    test('стартовая глубина сдвигает спуск', () {
      final profile = _profileWith(['abyss_depth_1']);
      expect(profile.startDepthBonus, 5);

      final driver = DescentDriver(
        profile: HeroProfile(
            tree: EchoTree(bought: const ['abyss_depth_1']),
            startDepthBonus: profile.startDepthBonus),
        seed: 3,
      );

      expect(driver.snapshot.depth, 6,
          reason: 'спуск начинается на пять этажей глубже');
    });

    test('пятый слот способностей открывается узлом', () {
      final plain = PlayerProfile();
      expect(plain.abilitySlots, Tuning.abilitySlots);

      final upgraded = _profileWith(const [
        'abyss_depth_1', 'abyss_depth_2', 'abyss_depth_3',
        'abyss_ability_slot',
      ]);
      expect(upgraded.abilitySlots, Tuning.abilitySlots + 1);
    });

    test('древо Эха способностей больше не открывает', () {
      // Узлы «Отголоски» давали по одиннадцать умений одним нажатием, и живой
      // прогон дал приговор: «умений мало, и они все сразу открыты». Теперь
      // умения открывают задания, а древо занимается правилами спуска —
      // и это разделение проверяется здесь, чтобы не вернуться назад тихо.
      final plain = PlayerProfile();
      final starters = plain.availableAbilities.length;

      final bought = _profileWith(const [
        'abyss_depth_1', 'abyss_depth_2', 'abyss_depth_3',
        'abyss_ability_slot', 'abyss_affix_slot', 'abyss_keep_shard',
      ]);

      expect(bought.availableAbilities.length, starters,
          reason: 'вся ветка Бездны не должна открыть ни одного умения');
    });

    test('«Печать мастера» даёт слот аффикса всем предметам', () {
      final item = Item(
        kind: GearKind.amulet,
        ilvl: 20,
        rarity: Rarity.common,
        affixes: const [],
      );

      expect(Crafting.affixCapacity(item),
          Tuning.affixSlotsByRarity[Rarity.common]);
      expect(Crafting.affixCapacity(item, treeBonus: 1),
          Tuning.affixSlotsByRarity[Rarity.common]! + 1);
    });

    test('«Порог» срабатывает один раз за спуск', () {
      // Узел, из-за которого наёмник переживает смертельный удар. Если бы он
      // сбрасывался на каждой волне, это было бы бессмертие, а не порог.
      final profile = HeroProfile(
        tree: EchoTree(bought: const [
          'blood_hp_1', 'blood_hp_2', 'blood_armor',
          'blood_regen', 'blood_resist', 'blood_threshold',
        ]),
      );

      final driver = DescentDriver(profile: profile, seed: 11);
      while (!driver.finished) {
        driver.tick();
      }

      expect(driver.mods.deathThresholdUsed, isTrue,
          reason: 'за целый спуск порог обязан был пригодиться');
      expect(driver.result.ending, RunEnding.death,
          reason: 'порог оттягивает смерть, а не отменяет её');
    });

    test('статы древа входят в билд как доля от собранного', () {
      final plain = HeroProfile().aggregate();
      final blooded =
          HeroProfile(tree: EchoTree(bought: const ['blood_hp_1'])).aggregate();

      expect(blooded.maxHp, closeTo(plain.maxHp * 1.08, 0.001));
      expect(blooded.attackDamage, plain.attackDamage,
          reason: 'узел выживания не трогает урон');
    });
  });

  group('сейв', () {
    test('именованные узлы переживают сохранение', () {
      final profile = _profileWith(const ['blood_hp_1', 'blade_damage_1']);

      final loaded = SaveData.decode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
            .encode(),
      );

      expect(loaded.profile.tree.bought,
          {'blood_hp_1', 'blade_damage_1'});
    });

    test('сейв со старым счётчиком узлов превращается в именованные', () {
      // До раунда 20 древо было числом одинаковых узлов. Отобрать купленное
      // молча нельзя, поэтому счётчик становится первыми N узлами.
      final profile = PlayerProfile();
      final raw = jsonDecode(
        SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile)
            .encode(),
      ) as Map<String, dynamic>;

      raw['version'] = 2;
      (raw['profile'] as Map)
        ..remove('echoNodes')
        ..['nodesBought'] = 3
        ..['startDepthBonus'] = 5;

      final loaded = SaveData.decode(jsonEncode(raw));

      expect(loaded.version, SaveData.currentVersion);
      expect(loaded.profile.tree.nodesBought, 3);
      expect(loaded.profile.tree.bought,
          {'blood_hp_1', 'blade_damage_1', 'abyss_depth_1'},
          reason: 'по узлу в каждую ветку — как их покупала автоматика');
      expect(loaded.profile.startDepthBonus, 5,
          reason: 'узел «Знакомая тропа» даёт ту же прибавку, что старое поле');
    });
  });

  test('автозакупка раскладывает узлы поровну по веткам', () {
    // Политика замера, а не совет игроку: перекос в одну ветку мерил бы её,
    // а не древо.
    // Эха хватает на часть древа: на выкупленном целиком перекос показывал
    // бы только разный размер веток, а не работу политики.
    final profile = PlayerProfile(echo: 700);
    profile.autoSpendEcho();

    final counts = {
      for (final branch in profile.tree.branches)
        branch.name: branch.nodes.where((n) => profile.tree.has(n.id)).length,
    };

    expect(profile.tree.complete, isFalse,
        reason: 'проверка имеет смысл, только пока древо не выкуплено');

    final values = counts.values.toList()..sort();
    expect(values.last - values.first, lessThanOrEqualTo(2), reason: '$counts');
  });

  test('контент древа согласован с кодом', () {
    // Узел, чьё правило симуляция не читает, — текст на экране. Список правил
    // закрыт, и здесь проверяется, что каждое из них кем-то используется.
    final tree = EchoTree();
    final rules = <EchoRule>{};
    for (final branch in tree.branches) {
      for (final node in branch.nodes) {
        if (node.rule != null) rules.add(node.rule!);
      }
    }

    expect(rules, EchoRule.values.toSet(),
        reason: 'правило без узла — мёртвый код, узел без правила — текст');
    // Число узлов растёт вместе с контентом (третьи «Отголоски» появились
    // вместе с удвоением списка способностей). Держим порядок величины, а
    // не цифру: узлов должно быть заметно больше, чем веток.
    expect(tree.totalNodes, greaterThanOrEqualTo(20),
        reason: 'древо не должно усыхать');
  });
}

PlayerProfile _profileWith(List<String> nodes) =>
    PlayerProfile(tree: EchoTree(bought: nodes), echo: 100000);
