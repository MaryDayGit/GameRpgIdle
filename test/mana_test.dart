import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Мана — общий бюджет активных способностей.
///
/// Кулдаун ограничивает способность поодиночке, мана — все сразу: это разные
/// вопросы, «как часто» и «сколько их сразу». Тесты держат именно это
/// различие, а не сам факт наличия числа: ресурс, которого всегда хватает,
/// — не ресурс, а украшение.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  group('бюджет живёт', () {
    test('у каждой активки есть цена, у пассивок — нет', () {
      // Бесплатная активка не участвует в бюджете, то есть выпадает из
      // единственного правила, ради которого мана существует.
      for (final def in ContentPack.current.abilities) {
        if (def.isActive) {
          expect(def.manaCost, greaterThan(0.0), reason: def.name);
        } else {
          expect(def.manaCost, 0.0, reason: def.name);
        }
      }
    });

    test('дороже та, что реже: цена идёт за кулдауном', () {
      final actives = [
        for (final def in ContentPack.current.abilities)
          if (def.isActive) def,
      ]..sort((a, b) => a.cooldown.compareTo(b.cooldown));

      for (var i = 1; i < actives.length; i++) {
        expect(actives[i].manaCost,
            greaterThanOrEqualTo(actives[i - 1].manaCost),
            reason: '${actives[i].name} против ${actives[i - 1].name}');
      }
    });

    test('мана не растёт от глубины', () {
      // Цены плоские. Растущий от ilvl запас к сотому этажу перестал бы
      // что-либо ограничивать — и вместе с ним обесценился бы выбор
      // «сколько активок унести вниз».
      for (final def in ContentPack.current.statAffixes) {
        if (def.stat.isManaBudget) {
          expect(def.scales, isFalse, reason: def.id);
        }
      }
    });
  });

  group('мана доживает до боя', () {
    test('преобразования блока статов не теряют ману', () {
      // Ровно эта ошибка и случилась: `scaled` собирал новый блок по полям,
      // про ману не знал, и в бою у героя оказывался пустой запас — то есть
      // способности не кастовались вообще, молча.
      const block = StatBlock(maxMana: 100.0, manaRegen: 5.0, maxHp: 10.0);

      // Мана намеренно НЕ растёт от множителя силы билда: она плоская, как
      // и цены способностей. Но и потеряться при этом не должна.
      expect(block.scaled(2.0).maxMana, 100.0);
      expect(block.scaled(2.0).manaRegen, 5.0);
      expect(block.withFractions(maxHpPct: 0.5).maxMana, 100.0);
      expect((block + block).maxMana, 200.0);
      expect((block + block).manaRegen, 10.0);
    });

    test('собранный билд приносит ману в бой', () {
      final hero = HeroState(HeroProfile().aggregate());

      expect(hero.stats.maxMana, greaterThan(0.0));
      expect(hero.mana, hero.stats.maxMana, reason: 'спуск начинается полным');
    });
  });

  group('бюджет ограничивает', () {
    test('платит целиком или не платит вовсе', () {
      // Половина каста хуже, чем его отсутствие.
      final hero = HeroState(const StatBlock(maxHp: 100, maxMana: 30));

      expect(hero.pay(20), isTrue);
      expect(hero.mana, 10);
      expect(hero.pay(20), isFalse);
      expect(hero.mana, 10, reason: 'не хватило — значит, ничего не списано');
    });

    test('жадная сборка упирается в ману, скромная — нет', () {
      // Главное обещание системы: мана — не налог на всех, а цена жадности.
      // Если обе сборки идут одинаково при любой регенерации, ресурс мёртв.
      // Считается сумма по многим сидам: разница в бюджете стоит около этажа
      // на ран, и один сид её не покажет — как и любой замер баланса здесь.
      int depth(List<String> abilities, double extraRegen) {
        var total = 0;
        for (var seed = 1; seed <= 24; seed++) {
          final profile = HeroProfile(
            abilities: abilities,
            // Регенерация докручивается через `traitStats` — единственная
            // точка, где к собранному билду можно добавить стат снаружи,
            // не подменяя контент на время теста.
            traitStats: (stats) => stats + StatBlock(manaRegen: extraRegen),
          );
          total += DescentSimulator(profile: profile, seed: seed)
              .run(floorCap: 80)
              .maxDepth;
        }
        return total;
      }

      const greedy = ['rift', 'fire_brand', 'totem_of_fury', 'bloodletting'];
      const modest = ['cleave', 'blade_echo', 'fortitude', 'thirst'];

      final greedyPoor = depth(greedy, 0.0);
      final greedyRich = depth(greedy, 100.0);
      final modestPoor = depth(modest, 0.0);
      final modestRich = depth(modest, 100.0);

      expect(greedyRich, greaterThan(greedyPoor),
          reason: 'четыре активки обязаны упираться в бюджет');
      expect(modestRich, modestPoor,
          reason: 'скромной сборке мана не мешает — это не налог на всех');
    });
  });

  test('все способности можно открыть', () {
    // Способность, до которой нельзя дойти, — мёртвый контент. Открывают их
    // теперь ЗАДАНИЯ, по одному за цель: древо Эха давало по одиннадцать
    // одним узлом, и открытие переставало быть событием.
    final rewards = {
      for (final quest in ContentPack.current.quests) quest.rewardAbility,
    };

    for (final def in ContentPack.current.abilities) {
      expect(def.isStarter || rewards.contains(def.id), isTrue,
          reason: '${def.name} не открывается ничем');
    }
  });
}
