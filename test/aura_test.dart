import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/descent.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Ауры: работают всегда и держат занятой часть запаса маны.
///
/// В этом весь смысл третьего вида способностей. Активка тратит бюджет на
/// секунду и он возвращается; аура забирает его насовсем. Слот и запас маны
/// — две разные цены за одно и то же место, и платить приходится обе.
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  List<String> get3(bool Function(AbilityDef) test) => [
        for (final def in ContentPack.current.abilities)
          if (test(def)) def.id,
      ];

  group('ауры описаны честно', () {
    test('у каждой ауры есть резерв, у остальных его нет', () {
      for (final def in ContentPack.current.abilities) {
        if (def.isAura) {
          expect(def.manaReserve, greaterThan(0.0), reason: def.name);
          expect(def.manaReserve, lessThan(1.0), reason: def.name);
          expect(def.manaCost, 0.0, reason: '${def.name}: аура не кастуется');
          expect(def.cooldown, 0.0, reason: '${def.name}: аура не перезаряжается');
        } else {
          expect(def.manaReserve, 0.0, reason: def.name);
        }
      }
    });

    test('аур больше одной: иначе выбирать нечего', () {
      expect(get3((d) => d.isAura).length, greaterThanOrEqualTo(3));
    });
  });

  group('резерв забирает запас', () {
    test('аура уменьшает доступную ману', () {
      final bare = HeroProfile(abilities: const ['cleave', 'blade_echo']);
      final aura =
          HeroProfile(abilities: const ['cleave', 'war_cry']);

      expect(aura.aggregate().maxMana,
          lessThan(bare.aggregate().maxMana));
    });

    test('резерв — доля, а не число', () {
      // Запас маны растёт только от вложений игрока. Плоский резерв к сотому
      // этажу стал бы бесплатным, и аура перестала бы что-либо стоить.
      final def = ContentPack.current.ability('war_cry')!;
      final loadout = [def];

      expect(auraReservation(loadout), def.manaReserve);
      expect(auraReservation(const []), 0.0);
    });

    test('две ауры дороже одной', () {
      double mana(List<String> abilities) =>
          HeroProfile(abilities: abilities).aggregate().maxMana;

      final one = mana(const ['war_cry', 'cleave']);
      final two = mana(const ['war_cry', 'stone_stance']);
      expect(two, lessThan(one));
    });

    test('резерв не съедает запас целиком', () {
      // Ноль доступной маны означал бы выключенные активки — это не размен,
      // а поломка сборки.
      final all = get3((d) => d.isAura);
      final loadout = [
        for (final id in all) ContentPack.current.ability(id)!,
      ];

      expect(auraReservation(loadout), lessThanOrEqualTo(0.9));
      expect(HeroProfile(abilities: all).aggregate().maxMana,
          greaterThan(0.0));
    });
  });

  group('аура работает', () {
    test('«Клич ярости» поднимает урон', () {
      final bare = HeroProfile(abilities: const ['cleave']).aggregate();
      final buffed =
          HeroProfile(abilities: const ['cleave', 'war_cry']).aggregate();

      expect(buffed.increasedDamage, greaterThan(bare.increasedDamage));
    });

    test('«Каменная стойка» поднимает броню долей, а не числом', () {
      final bare = HeroProfile(abilities: const ['cleave']).aggregate();
      final buffed =
          HeroProfile(abilities: const ['cleave', 'stone_stance']).aggregate();

      expect(buffed.armor, greaterThan(bare.armor));
      expect(buffed.armor / bare.armor, greaterThan(1.2));
    });

    test('аура меняет исход спуска, а не только число на экране', () {
      // Иначе это просто строка в описании: аура обязана дойти до боя.
      int depth(List<String> abilities) {
        var total = 0;
        for (var seed = 1; seed <= 16; seed++) {
          total += DescentSimulator(
            profile: HeroProfile(abilities: abilities),
            seed: seed,
          ).run(floorCap: 80).maxDepth;
        }
        return total;
      }

      expect(depth(const ['cleave', 'blade_echo', 'war_cry']),
          isNot(depth(const ['cleave', 'blade_echo'])));
    });
  });
  group('тег «Аура»', () {
    test('множит силу ауры, а не урон', () {
      // Единственный тег, который усиливает не урон. Аудит содержимого нашёл
      // его единственной дырой из пятнадцати: ауры урона не наносят, значит
      // «+% к урону Аурами» применять было не к чему, и ни один аффикс его не
      // давал. Тег стоял в отборе способностей и не значил ничего.
      const stats = StatBlock(maxHp: 1000.0);
      final runtime = AbilityRuntime.fromIds(const ['frost_shroud']);

      final plain = runtime.auraSlowFor(stats);
      final boosted = runtime.auraSlowFor(
          stats + const StatBlock(tagDamage: {Tag.aura: 1.0}));

      expect(plain, greaterThan(0.0), reason: 'иначе проверять нечего');
      expect(boosted, closeTo(plain * 2.0, 1e-9));
    });

    test('усиливает и статы, которые даёт аура', () {
      const base = StatBlock(maxHp: 1000.0, armor: 100.0);
      final def = ContentPack.current.ability('stone_stance')!;

      final plain = applyPassiveAbilities(base, [def]);
      final boosted = applyPassiveAbilities(
          base + const StatBlock(tagDamage: {Tag.aura: 1.0}), [def]);

      expect(plain.armor, greaterThan(base.armor));
      expect(boosted.armor - base.armor,
          closeTo((plain.armor - base.armor) * 2.0, 1e-6),
          reason: 'вдвое к силе ауры — вдвое к тому, что она даёт');
    });

    test('аура не усиливает сама себя', () {
      // Множитель читается из блока ДО аур. Иначе аура, дающая «+% к силе
      // Аур», подняла бы собственную величину — и порядок слотов начал бы
      // решать, сколько она даёт.
      const base = StatBlock(maxHp: 1000.0, armor: 100.0);
      final stone = ContentPack.current.ability('stone_stance')!;

      final once = applyPassiveAbilities(base, [stone]);
      final twice = applyPassiveAbilities(base, [stone, stone]);

      expect(twice.armor - base.armor,
          closeTo((once.armor - base.armor) * 2.0, 1e-6));
    });
  });

}
