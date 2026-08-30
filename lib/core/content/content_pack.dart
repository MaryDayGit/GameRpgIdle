import 'dart:math' as math;
import '../balance/curve_config.dart';
import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../model/enemy.dart';
import '../model/gear.dart';
import '../model/outpost.dart';
import 'ability_def.dart';
import 'affix_def.dart';
import 'content_issue.dart';
import 'enemy_def.dart';
import 'echo_tree_def.dart';
import 'floor_modifier_def.dart';
import 'implicit_def.dart';
import 'json_node.dart';
import 'passive_tree_def.dart';
import 'quest_def.dart';
import 'relic_def.dart';
import '../sim/fork.dart';

/// Весь контент игры, загруженный и проверенный.
///
/// Единственная точка входа. Ядро не умеет читать файлы — и не должно:
/// `dart:io` закрыл бы веб, а `rootBundle` затащил бы Flutter в `core`
/// (`docs/02-TECH.md` §1). Снаружи приходят уже разобранные JSON, откуда —
/// дело вызывающего: ассеты в приложении, файлы в тестах и балансировщике.
class ContentPack {
  const ContentPack({
    required this.curves,
    required this.tuning,
    required this.enemies,
    required this.bosses,
    required this.abilities,
    required this.statAffixes,
    required this.triggerAffixes,
    required this.relics,
    required this.floorModifiers,
    required this.implicits,
    required this.echoTree,
    required this.passiveTree,
    required this.quests,
  });

  final CurveConfig curves;
  final TuningConfig tuning;
  final List<EnemyArchetype> enemies;
  final List<EnemyArchetype> bosses;
  final List<AbilityDef> abilities;
  final List<StatAffixDef> statAffixes;
  final List<TriggerAffixDef> triggerAffixes;
  final List<RelicDef> relics;
  final List<FloorModifierDef> floorModifiers;

  /// Базовые статы типов предметов, по одному на тип.
  final List<ImplicitDef> implicits;

  /// Ветки древа Эха (GDD §8.3).
  final List<EchoBranchDef> echoTree;

  /// Дерево пассивок: общая прокачка игрока за достигнутую глубину.
  final PassiveTreeDef passiveTree;

  /// Задания — единственный источник новых способностей.
  final List<QuestDef> quests;

  /// Версия схемы, которую понимает этот код. Расхождение с `version` в файле —
  /// повод для миграции контента, а не для тихой загрузки.
  static const int schemaVersion = 1;

  /// Имена файлов без расширения. Порядок не важен, полнота — важна.
  static const List<String> fileNames = [
    'balance',
    'enemies',
    'abilities',
    'affixes_stat',
    'affixes_trigger',
    'relics',
    'floor_modifiers',
    'items',
    'echo_tree',
    'passive_tree',
    'quests',
  ];

  // --- Поиск по id -----------------------------------------------------------

  AbilityDef? ability(String id) => _find(abilities, id, (a) => a.id);
  QuestDef? quest(String id) => _find(quests, id, (q) => q.id);
  StatAffixDef? statAffix(String id) => _find(statAffixes, id, (a) => a.id);
  TriggerAffixDef? triggerAffix(String id) =>
      _find(triggerAffixes, id, (a) => a.id);
  RelicDef? relic(String id) => _find(relics, id, (r) => r.id);
  /// Модификатор этажа по id — включая СОСТАВНЫЕ, которых в паке нет.
  ///
  /// Спуск записывает в журнал id того, что действовало на этаже, а
  /// действовать может пара: путь развилки вместе с разломом дня, или смелый
  /// путь — оба варианта развилки сразу. Разбирать их обратно приходится
  /// здесь, потому что журнал знает про этаж только id. Без этого разбора
  /// поиск возвращал бы `null`, и журнал разлома молчал бы про разлом.
  FloorModifierDef? floorModifier(String id) {
    final direct = _find(floorModifiers, id, (m) => m.id);
    if (direct != null) return direct;

    final pair = id.split(FloorModifierDef.composedMark);
    if (pair.length == 2) {
      final a = floorModifier(pair[0]);
      final b = floorModifier(pair[1]);
      return a == null || b == null ? null : FloorModifierDef.combine(a, b);
    }

    final bold = id.split(FloorModifierDef.boldMark);
    if (bold.length == 2) {
      final a = floorModifier(bold[0]);
      final b = floorModifier(bold[1]);
      return a == null || b == null ? null : ForkChooser.boldPath(a, b);
    }

    return null;
  }

  ImplicitDef? implicitFor(GearKind kind) {
    for (final def in implicits) {
      if (def.kind == kind) return def;
    }
    return null;
  }

  static T? _find<T>(List<T> list, String id, String Function(T) key) {
    for (final item in list) {
      if (key(item) == id) return item;
    }
    return null;
  }

  static ContentPack? _current;

  /// Загруженный контент текущего изолята.
  ///
  /// Бросает, а не подставляет пустышку: игра, стартовавшая без контента,
  /// сроллит предметы без единого аффикса и будет выглядеть работающей.
  static ContentPack get current =>
      _current ??
      (throw StateError(
          'Контент не загружен: ContentPack.apply() в этом изоляте не вызывался'));

  static bool get isLoaded => _current != null;

  /// Применяет контент к статикам ядра.
  ///
  /// Статики в Dart изолятно-локальны: вызов здесь настраивает ТОЛЬКО текущий
  /// изолят. Фоновый расчёт обязан вызвать это у себя, иначе посчитает на
  /// значениях по умолчанию — правдоподобно и неправильно
  /// (`docs/05-ANDROID-PORT.md` §3.2).
  void apply() {
    _current = this;
    Curves.configure(curves);
    Tuning.configure(tuning);
    Bestiary.configure(enemies: enemies, bosses: bosses);
  }

  /// Разбирает и проверяет весь контент. Бросает [ContentException] со ВСЕМ
  /// списком проблем — чинить контент по одной опечатке за прогон невозможно.
  ///
  /// `files` — карта «имя файла без расширения -> результат `jsonDecode`».
  static ContentPack parse(Map<String, Object?> files) {
    final issues = ContentIssues();

    for (final name in fileNames) {
      if (!files.containsKey(name)) {
        issues.add(name, 'файл контента отсутствует');
      }
    }

    JsonNode root(String name) {
      final node = JsonNode.root(files[name], name, issues);
      final version = node.integer('version', or: 0);
      if (version != schemaVersion) {
        issues.add('$name.version',
            'версия схемы $version, поддерживается $schemaVersion');
      }
      return node;
    }

    // --- balance.json --------------------------------------------------------
    final balance = root('balance');
    balance.checkKeys({
      'version', 'curves', 'hero', 'combat', 'loot', 'traits', 'crafting',
      'outpost',
    });
    _requireExactKeys(balance, 'curves', _curveKeys);
    _requireExactKeys(balance, 'hero', _heroKeys);
    _requireExactKeys(balance, 'combat', _combatKeys);
    _requireExactKeys(balance, 'loot', _lootKeys);
    _requireExactKeys(balance, 'traits', _traitKeys);
    _requireExactKeys(balance, 'crafting', _craftingKeys);
    balance
        .child('crafting')
        .child('rerollRarityMultiplier', required: true)
        .asEnumDoubleMap(Rarity.values, unknownMessage: 'неизвестная редкость');
    _requireExactKeys(balance, 'outpost', _outpostKeys);

    final loot = balance.child('loot');
    loot.child('rarityWeights', required: true).asEnumDoubleMap(Rarity.values,
        unknownMessage: 'неизвестная редкость');
    loot.child('affixSlotsByRarity', required: true)
        .asEnumDoubleMap(Rarity.values, unknownMessage: 'неизвестная редкость');

    final rawBalance = files['balance'];
    final balanceMap = rawBalance is Map
        ? rawBalance.cast<String, dynamic>()
        : const <String, dynamic>{};
    final curvesMap = balanceMap['curves'];

    final curves = CurveConfig.fromJson(
      curvesMap is Map ? curvesMap.cast<String, dynamic>() : const {},
    );
    final tuning = TuningConfig.fromJson(balanceMap);

    // --- enemies.json --------------------------------------------------------
    final enemiesRoot = root('enemies');
    enemiesRoot.checkKeys({'version', 'enemies', 'bosses'});
    final enemies = [
      for (final n in enemiesRoot.children('enemies'))
        EnemyParser.parseEnemy(n),
    ];
    final bosses = [
      for (final n in enemiesRoot.children('bosses')) EnemyParser.parseBoss(n),
    ];

    // --- остальные файлы -----------------------------------------------------
    final questsRoot = root('quests');
    questsRoot.checkKeys({'version', '_comment', 'quests'});
    final quests = [
      for (final n in questsRoot.children('quests')) QuestDef.parse(n),
    ];

    final abilitiesRoot = root('abilities');
    abilitiesRoot.checkKeys({'version', 'abilities'});
    final abilities = [
      for (final n in abilitiesRoot.children('abilities')) AbilityDef.parse(n),
    ];

    final statRoot = root('affixes_stat');
    statRoot.checkKeys({'version', 'affixes'});
    final statAffixes = [
      for (final n in statRoot.children('affixes')) StatAffixDef.parse(n),
    ];

    final triggerRoot = root('affixes_trigger');
    triggerRoot.checkKeys({'version', 'affixes'});
    final triggerAffixes = [
      for (final n in triggerRoot.children('affixes'))
        TriggerAffixDef.parse(n),
    ];

    final relicsRoot = root('relics');
    relicsRoot.checkKeys({'version', 'relics'});
    final relics = [
      for (final n in relicsRoot.children('relics')) RelicDef.parse(n),
    ];

    final modsRoot = root('floor_modifiers');
    modsRoot.checkKeys({'version', 'modifiers'});
    final floorModifiers = [
      for (final n in modsRoot.children('modifiers'))
        FloorModifierDef.parse(n),
    ];

    final itemsRoot = root('items');
    itemsRoot.checkKeys({'version', 'implicits'});
    final implicits = [
      for (final n in itemsRoot.children('implicits')) ImplicitDef.parse(n),
    ];

    final treeRoot = root('echo_tree');
    treeRoot.checkKeys({'version', 'branches'});
    final echoTree = EchoTreeParser.parse(treeRoot);

    final passiveRoot = root('passive_tree');
    passiveRoot.checkKeys({'version', 'nodes', 'links'});
    final passiveTree = PassiveTreeParser.parse(passiveRoot);

    _checkTreeLayout(issues, passiveTree);

    // --- перекрёстные проверки ----------------------------------------------
    _uniqueIds(issues, 'enemies', [...enemies, ...bosses].map((e) => e.id));
    _uniqueIds(issues, 'abilities', abilities.map((a) => a.id));
    _uniqueIds(issues, 'affixes_stat', statAffixes.map((a) => a.id));
    _uniqueIds(issues, 'affixes_trigger', triggerAffixes.map((a) => a.id));
    _uniqueIds(issues, 'relics', relics.map((r) => r.id));
    _uniqueIds(issues, 'floor_modifiers', floorModifiers.map((m) => m.id));

    // Пустой бестиарий — это спуск без единого боя: герой уходит на дно
    // за секунды, и ни один инвариант кривых этого не ловит.
    if (enemies.isEmpty) {
      issues.add('enemies', 'ни одного обычного моба');
    }
    if (bosses.isEmpty) {
      issues.add('enemies', 'ни одного босса');
    }

    // Стартовых способностей обязано быть БОЛЬШЕ, чем слотов.
    //
    // Раньше их было ровно две на четыре слота, и это ловил замер на
    // телефоне: «умений нет, только какие-то стандартные». Четыре гнезда и
    // два умения — обещание выбора, которого нет. Ровно по числу слотов тоже
    // не выбор: сборка собирается сама.
    final starters = abilities.where((a) => a.isStarter).length;
    if (starters <= Tuning.abilitySlots) {
      issues.add(
          'abilities',
          'стартовых способностей $starters при ${Tuning.abilitySlots} '
              'слотах — выбирать не из чего');
    }

    // --- Две неравенства, на которых стоит вся прогрессия ------------------
    //
    // Они выведены, а не назначены (см. `Curves.itemGrowth`), и нарушение
    // любого из них ломает игру целиком, а не «немного сдвигает баланс».
    // Заметить это можно было только прогоном на шестьдесят спусков — теперь
    // это ошибка загрузки.
    final a = curves.mobHpGrowth;
    final b = curves.mobDpsGrowth;
    final g = curves.itemGrowth;
    final geometric = math.sqrt(a * b);

    if (g <= geometric) {
      issues.add(
          'balance.curves.itemGrowth',
          'добыча не двигает прогресс: itemGrowth ${g.toStringAsFixed(4)} '
              'должен быть больше sqrt(mobHpGrowth·mobDpsGrowth) = '
              '${geometric.toStringAsFixed(4)}. Иначе снаряжение, добытое на '
              'глубине D, хватает лишь на ${(2 * math.log(g) / math.log(a * b)).toStringAsFixed(2)}·D, '
              'и цикл «нашёл вещь — прошёл дальше» перестаёт быть двигателем');
    }
    if (g >= b) {
      issues.add(
          'balance.curves.itemGrowth',
          'спуск будет обрываться таймаутом, а не смертью: itemGrowth '
              '${g.toStringAsFixed(4)} должен быть меньше mobDpsGrowth '
              '${b.toStringAsFixed(4)}. Снаряжение обгоняет урон мобов, герой '
              'не гибнет, а упирается в бесконечно медленные этажи');
    }
    if (a >= b) {
      issues.add(
          'balance.curves.mobHpGrowth',
          'HP мобов растут не медленнее их урона ($a против $b), и тогда оба '
              'условия выше невыполнимы одновременно: sqrt(a·b) оказывается '
              'больше b, и места для itemGrowth не остаётся');
    }

    _uniqueIds(issues, 'quests', quests.map((q) => q.id));

    // Задание, награда которого не существует, — цель, ведущая в пустоту.
    for (final quest in quests) {
      if (!abilities.any((a) => a.id == quest.rewardAbility)) {
        issues.add('quests.${quest.id}',
            'награда «${quest.rewardAbility}» — не существующая способность');
      }
      if (abilities.any((a) => a.id == quest.rewardAbility && a.isStarter)) {
        issues.add('quests.${quest.id}',
            'награда «${quest.rewardAbility}» и так в стартовом наборе');
      }
      if (quest.condition == QuestCondition.defeatBoss) {
        final boss = quest.params.str('boss');
        if (!bosses.any((b) => b.id == boss)) {
          issues.add('quests.${quest.id}.params.boss',
              'нет такого босса: «$boss»');
        }
      }
      if (quest.condition == QuestCondition.outpostLevel) {
        final name = quest.params.str('building');
        if (!Building.values.any((b) => b.name == name)) {
          issues.add('quests.${quest.id}.params.building',
              'нет такой постройки: «$name»');
        }
        if (quest.value > Tuning.maxBuildingLevel) {
          issues.add('quests.${quest.id}.value',
              'уровень выше потолка построек — задание невыполнимо');
        }
      }
      for (final earlier in quest.after) {
        if (!quests.any((q) => q.id == earlier)) {
          issues.add('quests.${quest.id}.after',
              'ссылка на несуществующее задание «$earlier»');
        }
      }
    }

    // Две награды на одно умение — это второе задание, которое ничего не
    // даёт: способность уже открыта, и игрок этого не поймёт.
    final byReward = <String, String>{};
    for (final quest in quests) {
      final prev = byReward[quest.rewardAbility];
      if (prev != null) {
        issues.add('quests.${quest.id}',
            'способность «${quest.rewardAbility}» уже открывает «$prev»');
      }
      byReward[quest.rewardAbility] = quest.id;
    }

    // Способность, которую не открывает ни одно задание и которой нет в
    // стартовом наборе, лежит в файле мёртвым грузом. Пересчитать это вручную
    // нельзя — список умений в игре показывает открытое, а не всё, что есть.
    for (final def in abilities) {
      if (def.isStarter) continue;
      if (byReward.containsKey(def.id)) continue;
      issues.add('abilities',
          'способность «${def.id}» не открывается ничем: '
              'ни стартовый набор, ни задание');
    }

    // Стартовый набор из одних активок или одних пассивок — это не выбор
    // рисунка боя, а один и тот же билд с разными числами.
    final starterActives =
        abilities.where((a) => a.isStarter && a.isActive).length;
    if (starters > 0 && (starterActives == 0 || starterActives == starters)) {
      issues.add(
          'abilities',
          'стартовые способности одного вида: $starterActives активных '
              'из $starters');
    }

    // Тип предмета без имплицита перестаёт быть апгрейдом сам по себе:
    // побеждать надетое сможет только удачный редкий ролл, и снаряжение
    // начнёт отставать от глубины (см. `implicit_def.dart`).
    for (final kind in GearKind.values) {
      final matches = implicits.where((i) => i.kind == kind).length;
      if (matches == 0) {
        issues.add('items.implicits', 'нет имплицита для ${kind.name}');
      } else if (matches > 1) {
        issues.add('items.implicits', 'больше одного имплицита для ${kind.name}');
      }
    }

    // Каждый вид снаряжения обязан иметь хотя бы один реликт.
    //
    // Раньше правило было обратным — «не больше одного на вид», — и это было
    // следствием того, что реликтов было ровно восемь, по числу слотов. С
    // двадцатью пятью такое правило запрещает саму идею выбора: два реликта
    // на один слот и есть решение игрока, какое правило ему важнее. А вот
    // слот БЕЗ реликта — дыра: игрок, собравший сборку вокруг перчаток, не
    // находит для них ничего.
    //
    // Одновременно надеть два реликта на один слот нельзя физически, так что
    // «два взаимоисключающих правила без указания, какое сильнее» здесь не
    // возникает.
    final byKind = <GearKind, int>{};
    for (final r in relics) {
      byKind[r.kind] = (byKind[r.kind] ?? 0) + 1;
    }
    for (final kind in GearKind.values) {
      if ((byKind[kind] ?? 0) == 0) {
        issues.add('relics',
            'для ${kind.name} нет ни одного реликта — сборка вокруг этого '
            'слота не сможет получить правило');
      }
    }

    for (final r in relics) {
      for (final other in r.exclusiveWith) {
        final target = _find(relics, other, (x) => x.id);
        if (target == null) {
          issues.add('relics.${r.id}.exclusiveWith',
              'ссылка на несуществующий реликт «$other»');
        } else if (!target.exclusiveWith.contains(r.id)) {
          // Односторонняя несовместимость — это порядок надевания, решающий,
          // сработает правило или нет.
          issues.add('relics.$other.exclusiveWith',
              'несовместимость с «${r.id}» не объявлена в обратную сторону');
        }
      }
    }

    // Тип предмета, на который не выпадает ни один аффикс, роллится пустым.
    for (final kind in GearKind.values) {
      if (!statAffixes.any((a) => a.kinds.contains(kind))) {
        issues.add('affixes_stat',
            'на ${kind.name} не выпадает ни один статовый аффикс');
      }
    }

    issues.throwIfAny();

    return ContentPack(
      curves: curves,
      tuning: tuning,
      enemies: enemies,
      bosses: bosses,
      abilities: abilities,
      statAffixes: statAffixes,
      triggerAffixes: triggerAffixes,
      relics: relics,
      floorModifiers: floorModifiers,
      implicits: implicits,
      echoTree: echoTree,
      passiveTree: passiveTree,
      quests: quests,
    );
  }

  static void _requireExactKeys(
      JsonNode root, String section, Set<String> keys) {
    final node = root.child(section, required: true);
    node.checkKeys(keys);
    for (final key in keys) {
      if (!node.has(key)) {
        node.issues.add('${node.path}.$key', 'поле отсутствует');
      }
    }
  }

  /// Кружки узлов не должны пересекаться на экране.
  ///
  /// Координаты в контенте условные, а рисуются узлы кружками постоянного
  /// радиуса — то есть просвет между ними зависит от масштаба экрана, и
  /// проверить его можно только зная обе величины. Раскладку считает
  /// `tool/make_passive_tree.dart` по тем же числам, но проверка сделана
  /// независимо от генератора нарочно: разъехаться они могут порознь, а
  /// чинить придётся всё равно вместе.
  ///
  /// Живой прогон: «в дереве пассивок ветки и ноды наезжают друг на друга».
  /// Разброс веток задавался УГЛОМ, а расстояние на экране — это угол на
  /// радиус: на девятом кольце тот же угол давал просторный веер, а на
  /// втором — 13 единиц между центрами при радиусе кружка в 14.5.
  static void _checkTreeLayout(ContentIssues issues, PassiveTreeDef tree) {
    double radiusOf(PassiveKind kind) => switch (kind) {
          PassiveKind.root => 17.0,
          PassiveKind.keystone => 16.0,
          PassiveKind.notable => 13.0,
          PassiveKind.stat => 9.0,
        };

    final nodes = tree.nodes;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        final dx = (a.x - b.x) * treeScreenScale;
        final dy = (a.y - b.y) * treeScreenScale;
        final distance = math.sqrt(dx * dx + dy * dy);
        final needed = radiusOf(a.kind) + radiusOf(b.kind);

        if (distance < needed) {
          issues.add(
            'passive_tree.nodes.${a.id}',
            'кружок налезает на «${b.id}»: между центрами '
            '${distance.toStringAsFixed(1)} пикселя при '
            '${needed.toStringAsFixed(1)} на два радиуса. '
            'Правьте tool/make_passive_tree.dart, а не JSON',
          );
          return; // одной пары достаточно: раскладка считается целиком
        }
      }
    }
  }

  static void _uniqueIds(
      ContentIssues issues, String where, Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (!seen.add(id)) issues.add(where, 'повторяющийся id «$id»');
    }
  }

  static const _curveKeys = {
    'tau', 'mobHpGrowth', 'mobDpsGrowth', 'mobHpBase', 'mobDpsBase',
    'itemGrowth', 'armorConstantBase', 'armorDrCap', 'resistCap',
    'echoBase', 'echoGrowth', 'goldBase', 'brandMobStatsPerRank',
    'brandLootPerRank', 'brandEchoPerRank', 'brandMaxRank',
    'brandUnlockDepths', 'brandProofDepth', 'hireScaleFromDepth',
    'startDepthShare',
    'passivePointPerFloors', 'passivePointCap',
    'echoNodeBaseCost', 'echoNodeCostGrowth',
  };

  static const _heroKeys = {
    'maxHp', 'hpRegen', 'maxMana', 'manaRegen',
    'armor', 'attackDamage', 'spellPower', 'attackSpeed', 'critChance',
    'critMulti',
  };

  static const _combatKeys = {
    'tickSeconds', 'wavesPerFloor', 'wavesPerBossFloor',
    'restSecondsBetweenFloors', 'restHealFraction', 'waveTimeoutSeconds',
    'stallCheckSeconds', 'stallProgressThreshold', 'abilitySlots',
    'forkEveryFloors', 'forkWaitSeconds', 'boldForkLootBonus',
    'boldForkRarityBonus', 'boldForkEchoBonus', 'sellBonus',
    'spellReferenceRate',
    'chillSeconds',
  };

  static const _lootKeys = {
    'chestItemChance', 'onboardingFloors', 'onboardingChestItemChance',
    'bossItems', 'bigBossItems', 'relicPityFloors', 'percentileMin',
    'percentileMax', 'extractionPercentilePenalty', 'twoHandedRollBonus',
    'twoHandedChance',
    'rarityWeights', 'affixSlotsByRarity', 'maxTriggerAffixesPerItem',
    'itemPowerScale',
  };

  static const _traitKeys = {
    'slowFraction', 'shredFraction', 'lifestealFraction', 'rampPerSecond',
    'explosionFraction', 'manaDrainPerHit', 'allyHealPerSecond',
    'reflectFraction', 'hardenPerSecond', 'hardenCap',
    'rampCap',
  };

  static const _craftingKeys = {
    'rerollCostBase', 'rerollCostGrowth', 'rerollRarityMultiplier',
    'deepenCostBase', 'deepenCostGrowth', 'deepenIlvlStep',
    'shardCapacityBase', 'shardCapacityPerLevel',
  };

  static const _outpostKeys = {
    'baseHireCost', 'baseTavernCandidates', 'baseSalvageRate',
    'maxBuildingLevel', 'depthGatePerLevel',
    'upgradeCostFloors', 'stashSlotsBase', 'stashSlotsPerLevel',
    'lootQualityPerLevel', 'lootQuantityPerLevel', 'rerollFloorPerLevel',
    'shardSalvageLevel', 'shardSalvageChance', 'salvageRatePerLevel',
    'forecastFloorsBase', 'forecastFloorsPerLevel',
    'restHealPerLevel',
  };
}
