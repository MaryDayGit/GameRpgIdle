import 'dart:convert';

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/content/passive_tree_def.dart';
import 'package:rift/core/model/build_power.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/passive_tree.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/stat_key.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Дерево пассивок — общая прокачка игрока за достигнутую глубину.
///
/// Проверяется не «числа складываются», а три обещания: до узла надо дойти,
/// очков не хватает на всё, и дерево действует на каждого наёмника.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('форма дерева', () {
    test('узлов втрое больше, чем очков', () {
      // Дерево из ста узлов при потолке в 60 очков выкупается больше чем
      // наполовину — это список покупок, а не выбор. Живой прогон назвал это
      // «не глубокое».
      final tree = PassiveTree();
      expect(tree.nodes.length, greaterThan(Curves.passivePointCap * 2.5),
          reason: 'узлов ${tree.nodes.length} при потолке '
              '${Curves.passivePointCap} очков');
    });

    test('три класса узлов, и дорога — самый частый', () {
      // Если крупных узлов столько же, сколько мелких, крупный перестаёт
      // быть наградой: дорога обязана стоить очков.
      final nodes = PassiveTree().nodes;
      int count(PassiveKind kind) =>
          nodes.where((n) => n.kind == kind).length;

      final small = count(PassiveKind.stat);
      final notables = count(PassiveKind.notable);
      final keystones = count(PassiveKind.keystone);

      expect(small, greaterThan(notables * 3));
      expect(notables, greaterThan(keystones * 2),
          reason: 'размен должен быть решением, а не рутиной');
      expect(keystones, greaterThanOrEqualTo(6));
    });

    test('крупные узлы не берут плату', () {
      // «Везде минуса» — так это выглядело, когда каждый заметный узел был
      // разменом. Плата — привилегия ключевых узлов.
      for (final node in PassiveTree().nodes) {
        if (node.kind != PassiveKind.notable) continue;
        expect(node.penaltyStat, isNull, reason: node.name);
      }
    });

    test('в каждом луче есть узел, меняющий правило', () {
      // Дерево из одних процентов — ползунок: любой узел заменяется любым
      // другим той же величины. Правило — то, ради чего строят билд.
      final nodes = PassiveTree().nodes.where((n) => !n.isRoot);
      final clusters = {for (final n in nodes) n.cluster};

      for (final cluster in clusters) {
        final withRule =
            nodes.where((n) => n.cluster == cluster && n.rule != null);
        expect(withRule, isNotEmpty, reason: 'луч «$cluster» без правил');
      }
    });

    test('дорога в луче не из одинаковых узлов', () {
      // Первая версия ставила в луч двадцать копий «+8 % к максимуму HP».
      // Живой прогон назвал это «не разнообразным»: одинаковые узлы — это не
      // дорога, а счётчик.
      final nodes = PassiveTree().nodes.where((n) => !n.isRoot);
      final clusters = {for (final n in nodes) n.cluster};

      for (final cluster in clusters) {
        final names = {
          for (final n in nodes)
            if (n.cluster == cluster && n.kind == PassiveKind.stat) n.name,
        };
        expect(names.length, greaterThanOrEqualTo(3),
            reason: 'луч «$cluster»: мелких узлов всего ${names.length} видов');
      }
    });

    test('крупные узлы луча не повторяют друг друга', () {
      final nodes = PassiveTree().nodes.where((n) => !n.isRoot);
      final clusters = {for (final n in nodes) n.cluster};

      for (final cluster in clusters) {
        final names = [
          for (final n in nodes)
            if (n.cluster == cluster && n.kind != PassiveKind.stat) n.name,
        ];
        expect(names.toSet().length, names.length,
            reason: 'луч «$cluster»: $names');
      }
    });

    test('у каждого узла есть своя иконка', () {
      // Иконка — опознавательный знак: игрок ведёт палец по лучу и видит,
      // что узлы разные, не читая подписей. Одна иконка на всё дерево эту
      // работу не делает.
      final nodes = PassiveTree().nodes.where((n) => !n.isRoot);
      final icons = <String>{};

      for (final node in nodes) {
        expect(node.icon, isNotEmpty, reason: node.name);
        icons.add(node.icon);
      }
      expect(icons.length, greaterThanOrEqualTo(12),
          reason: 'иконок всего ${icons.length}');
    });

    test('каждое правило где-то стоит', () {
      // Правило, объявленное в коде и не выставленное в дереве, — мёртвый
      // механизм: он проверяется тестами и не встречается игроку.
      final used = {
        for (final node in PassiveTree().nodes)
          if (node.rule != null) node.rule!,
      };
      expect(used, containsAll(PassiveRule.values));
    });

    test('есть ключевые узлы, и у каждого своя плата', () {
      final keystones = PassiveTree()
          .nodes
          .where((n) => n.kind == PassiveKind.keystone)
          .toList();

      expect(keystones.length, greaterThanOrEqualTo(6));
      for (final node in keystones) {
        expect(node.penaltyStat, isNotNull, reason: node.name);
        expect(node.penalty, greaterThan(0.0), reason: node.name);
        expect(node.penaltyStat, isNot(node.stat),
            reason: '${node.name}: плата тем же статом — это не размен');
      }
    });

    test('до каждого узла есть дорога от корня', () {
      // Проверяется и валидатором контента, но здесь — на собранном дереве:
      // узел, до которого нельзя дойти, это мёртвый контент.
      final tree = PassiveTree();
      final root = tree.rootId;
      expect(root, isNotNull);

      final seen = <String>{root!};
      final queue = <String>[root];
      while (queue.isNotEmpty) {
        for (final next in tree.neighbours(queue.removeLast())) {
          if (seen.add(next)) queue.add(next);
        }
      }
      expect(seen.length, tree.nodes.length);
    });
  });

  group('дорога стоит очков', () {
    test('далёкий узел нельзя взять первым', () {
      final tree = PassiveTree();
      final far = tree.nodes.firstWhere((n) => n.kind == PassiveKind.keystone);

      expect(tree.canAllocate(far.id, 60), isFalse,
          reason: 'до ключевого узла надо дойти');
    });

    test('сосед корня берётся сразу, следующий — после него', () {
      final tree = PassiveTree();
      final first = tree.neighbours(tree.rootId!).first;

      expect(tree.allocate(first, 60), isTrue);
      final second = tree
          .neighbours(first)
          .firstWhere((id) => id != tree.rootId && !tree.has(id));

      expect(tree.canAllocate(second, 60), isTrue);
      expect(tree.allocate(second, 60), isTrue);
      expect(tree.spent, 2);
    });

    test('очки кончаются', () {
      final tree = PassiveTree();
      var taken = 0;

      // Идём жадно, пока есть куда: с двумя очками дальше двух узлов не уйти.
      for (final node in tree.nodes) {
        if (tree.allocate(node.id, 2)) taken++;
      }
      expect(taken, 2);
      expect(tree.canAllocate(tree.nodes.last.id, 2), isFalse);
    });

    test('до ключевого узла можно дойти в пределах потолка', () {
      // Если дорога до размена длиннее, чем весь бюджет, ключевой узел —
      // украшение.
      final tree = PassiveTree();
      final keystone =
          tree.nodes.firstWhere((n) => n.kind == PassiveKind.keystone);

      final path = _shortestPath(tree, tree.rootId!, keystone.id);
      expect(path, isNotNull);
      expect(path!.length - 1, lessThan(Curves.passivePointCap),
          reason: 'дорога до «${keystone.name}» — ${path.length - 1} узлов');
    });
  });

  group('снятие узлов', () {
    test('середину дороги снять нельзя', () {
      // Иначе конец дороги повис бы: узлы есть, а дойти до них нельзя.
      final tree = PassiveTree();
      final first = tree.neighbours(tree.rootId!).first;
      tree.allocate(first, 60);

      final second = tree
          .neighbours(first)
          .firstWhere((id) => id != tree.rootId && !tree.has(id));
      tree.allocate(second, 60);

      expect(tree.canRefund(first), isFalse, reason: 'на нём держится второй');
      expect(tree.canRefund(second), isTrue);
      expect(tree.refund(second), isTrue);
      expect(tree.canRefund(first), isTrue);
    });

    test('сброс возвращает все очки', () {
      final tree = PassiveTree();
      final first = tree.neighbours(tree.rootId!).first;
      tree.allocate(first, 60);

      tree.reset();
      expect(tree.spent, 0);
    });
  });

  group('очки за глубину', () {
    test('очко за каждые несколько этажей рекорда, с потолком', () {
      // Шаг живёт в контенте, поэтому тест считает по нему, а не по числу
      // из головы: иначе правка баланса роняет тест, ничего не сломав.
      final per = Curves.passivePointPerFloors;

      expect(Curves.passivePoints(0), 0);
      expect(Curves.passivePoints(per - 1), 0);
      expect(Curves.passivePoints(per), 1);
      expect(Curves.passivePoints(per * 10), 10);
      expect(Curves.passivePoints(100000), Curves.passivePointCap);
    });

    test('потолок достижим на той глубине, куда игрок доходит', () {
      // Потолок, до которого нельзя добраться, — это не потолок, а обман:
      // при шаге в 5 этажей 60 очков требовали глубины 300, а прогрессия
      // упиралась в 178 (замер `--campaign 50`).
      final capDepth = Curves.passivePointCap * Curves.passivePointPerFloors;
      expect(capDepth, lessThanOrEqualTo(220),
          reason: 'полное дерево требует глубины $capDepth');
    });

    test('очки считаются от рекорда, а не от суммы спусков', () {
      final profile = PlayerProfile(maxDepthEver: 40);
      expect(profile.passivePoints, Curves.passivePoints(40));
      expect(profile.passivePointsLeft, profile.passivePoints);
    });
  });

  group('дерево действует', () {
    test('взятый узел меняет билд', () {
      final plain = HeroProfile().aggregate();

      final tree = PassiveTree();
      final first = tree.neighbours(tree.rootId!).first;
      tree.allocate(first, 60);

      final buffed = HeroProfile(passives: tree).aggregate();
      expect(_power(buffed), greaterThan(_power(plain)));
    });

    test('размен ключевого узла настоящий: что-то падает', () {
      final tree = PassiveTree();
      final keystone =
          tree.nodes.firstWhere((n) => n.kind == PassiveKind.keystone);

      // Сравнивается ДОРОГА с ключевым узлом и та же дорога без него.
      // Сравнивать с голым героем нельзя: дорога к «Крови за силу» идёт
      // через узлы на HP, и они перекрывают её плату — а это и есть смысл
      // размена «переплавь своё HP в урон», а не ошибка.
      final path = _shortestPath(tree, tree.rootId!, keystone.id)!;
      for (final id in path.skip(1).take(path.length - 2)) {
        tree.allocate(id, 60);
      }
      final road = HeroProfile(
        passives: PassiveTree(allocated: tree.allocated),
      ).aggregate();

      expect(tree.allocate(keystone.id, 60), isTrue);
      final keyed = HeroProfile(passives: tree).aggregate();

      final penalty = keystone.penaltyStat!;
      expect(_stat(keyed, penalty), lessThan(_stat(road, penalty)),
          reason: 'плата ${keystone.name}');
      expect(_stat(keyed, keystone.stat!),
          greaterThan(_stat(road, keystone.stat!)),
          reason: 'выгода ${keystone.name}');
    });

    test('дерево общее: оно достаётся любому наёмнику', () {
      final profile = PlayerProfile.newGame(seed: 3, )..gold = 10000;
      final first = profile.passives.neighbours(profile.passives.rootId!).first;
      profile.passives.allocate(first, 60);

      final contract = profile.deploy(profile.roster.reserve.first, seed: 9);
      expect(contract.passiveNodes, contains(first),
          reason: 'снимок контракта помнит дерево на момент отправки');
    });
  });

  test('дерево переживает сейв', () {
    final profile = PlayerProfile(maxDepthEver: 60);
    final first = profile.passives.neighbours(profile.passives.rootId!).first;
    profile.allocatePassive(first);

    final loaded = SaveData.decode(
      SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile).encode(),
    );

    expect(loaded.profile.passives.allocated, {first});
    expect(loaded.profile.passivePointsLeft,
        loaded.profile.passivePoints - 1);
  });

  test('сейв без дерева открывается пустым деревом', () {
    final profile = PlayerProfile(maxDepthEver: 60);
    final raw = jsonDecode(
      SaveData(lastSeenUtc: DateTime.now().toUtc(), profile: profile).encode(),
    ) as Map<String, dynamic>;
    (raw['profile'] as Map).remove('passiveNodes');

    final loaded = SaveData.decode(jsonEncode(raw));
    expect(loaded.profile.passives.spent, 0);
  });

  test('сила билда на экране считается с деревьями', () {
    // Экран сборки считал свои числа сам и без деревьев: игрок видел силу
    // билда, с которой наёмник вниз не пойдёт. Сборка профиля теперь одна,
    // и этот тест держит её единственной.
    final profile = PlayerProfile(maxDepthEver: 100);
    final merc = profile.roster.reserve.isEmpty
        ? MercFactory.roll(Rng(1), tavernLevel: 0, idPrefix: 'ui')
        : profile.roster.reserve.first;

    final bare = merc.toProfile().aggregate();
    final withoutTrees = BuildPower.of(bare, 40);

    final first = profile.passives.neighbours(profile.passives.rootId!).first;
    profile.allocatePassive(first);

    final asDeployed = profile.heroProfileFor(merc).aggregate();
    expect(BuildPower.of(asDeployed, 40), greaterThan(withoutTrees),
        reason: 'дерево пассивок обязано входить в силу билда');
  });
}

double _power(StatBlock stats) => stats.maxHp + stats.attackDamage * 10;

// `key` типизирован намеренно: `.name` у перечислений приходит расширением,
// и через `dynamic` его не видно — падает на ровном месте.
double _stat(StatBlock stats, StatKey key) => switch (key) {
      StatKey.maxHpPct || StatKey.maxHp => stats.maxHp,
      StatKey.armorPct || StatKey.armor => stats.armor,
      StatKey.increasedDamage => stats.increasedDamage,
      StatKey.increasedAttackSpeed => stats.increasedAttackSpeed,
      StatKey.critMulti => stats.critMulti,
      StatKey.critChance => stats.critChance,
      StatKey.cooldownReduction => stats.cooldownReduction,
      StatKey.leech => stats.leech,
      _ => 0.0,
    };

/// Кратчайший путь по дереву — тем же обходом, что и в игре.
List<String>? _shortestPath(PassiveTree tree, String from, String to) {
  final previous = <String, String>{};
  final seen = <String>{from};
  final queue = <String>[from];

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (current == to) {
      final path = <String>[to];
      var step = to;
      while (step != from) {
        step = previous[step]!;
        path.insert(0, step);
      }
      return path;
    }
    for (final next in tree.neighbours(current)) {
      if (seen.add(next)) {
        previous[next] = current;
        queue.add(next);
      }
    }
  }
  return null;

}
