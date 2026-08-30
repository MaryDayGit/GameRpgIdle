import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/hero.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/abilities.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/events.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Две оси силы и теги, которые их связывают со снаряжением.
///
/// Живой прогон дал приговор: «выбор без выбора, одна автоатака, очень мало
/// тегов у скилов, игроку не с чего строить билд». Разбор показал причину:
/// ВСЕ способности росли от одного и того же стата — урона оружия. Значит
/// никакое снаряжение не могло подходить одной сборке лучше, чем другой, и
/// «подобрать вещи под умения» было физически не из чего.
///
/// Тесты держат обещание, а не числа: **выбор способности обязан менять то,
/// какое снаряжение игроку нужно.**
void main() {
  setUpAll(() => loadContentFromDisk().apply());

  final dummy = EnemyArchetype(
    id: 'dummy',
    name: 'Болванчик',
    hpMult: 4000.0,
    dpsMult: 0.0,
    attackSpeed: 1.0,
    weight: 1.0,
  );

  /// Мешок с HP, у которого высокое сопротивление одной стихии. Нужен, чтобы
  /// проверить, каким УРОНОМ бьёт удар, а не сколько его.
  EnemyArchetype warded(DamageType type) => EnemyArchetype(
        id: 'warded',
        name: 'Оберег',
        hpMult: 4000.0,
        dpsMult: 0.0,
        attackSpeed: 1.0,
        weight: 1.0,
        resists: {type: 75.0},
      );

  StatBlock stats({
    double attackDamage = 0.0,
    double spellPower = 0.0,
    double increasedDamage = 0.0,
    Map<Tag, double> tagDamage = const {},
  }) =>
      StatBlock(
        maxHp: 1e6,
        maxMana: 1e6,
        manaRegen: 1000.0,
        armor: 0.0,
        attackDamage: attackDamage,
        spellPower: spellPower,
        attackSpeed: 1.0,
        increasedDamage: increasedDamage,
        tagDamage: tagDamage,
      );

  WaveRunner fight(
    List<String> abilities, {
    required StatBlock hero,
    EnemyArchetype? enemy,
    int enemies = 1,
  }) =>
      WaveRunner(
        bus: EventBus(),
        depth: 5,
        hero: HeroState(hero),
        enemies: [
          for (var i = 0; i < enemies; i++)
            EnemyInstance.spawn(enemy ?? dummy, 5),
        ],
        rng: Rng(7),
        abilities: AbilityRuntime.fromIds(abilities),
      );

  /// Урон, нанесённый волне за [ticks] тиков.
  double dealt(WaveRunner runner, {int ticks = 100}) {
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }
    return runner.outcome.damageDealt;
  }

  group('две оси', () {
    test('Чары растут от силы чар, а Атаки — от урона оружия', () {
      // Это и есть весь ответ на «выбор без выбора»: пока обе формы росли из
      // одного стата, любая вещь одинаково годилась любой сборке.
      const spell = ['spark_bolt'];
      const attack = ['flame_lash'];

      final spellOnWeapon =
          dealt(fight(spell, hero: stats(attackDamage: 200.0)));
      final spellOnPower =
          dealt(fight(spell, hero: stats(spellPower: 200.0)));

      expect(spellOnPower, greaterThan(spellOnWeapon),
          reason: 'Чары обязаны расти от силы чар');

      // Автоатака есть всегда и растёт от оружия, поэтому «Чары на оружии»
      // не ноль. Важно другое: вложение в СВОЮ ось даёт больше.
      final attackOnWeapon =
          dealt(fight(attack, hero: stats(attackDamage: 200.0)));
      final attackOnPower =
          dealt(fight(attack, hero: stats(spellPower: 200.0)));

      expect(attackOnWeapon, greaterThan(attackOnPower),
          reason: 'Атаки обязаны расти от урона оружия');
    });

    test('у каждой наносящей урон способности ровно одна форма', () {
      // Способность без формы не растёт ни от чего, с двумя — растёт от обеих
      // осей сразу и обесценивает выбор между ними. Проверяется на контенте,
      // а не на выдуманном примере: валидатор ловит это на загрузке, а здесь
      // видно, что правило выполнено на всех пятидесяти пяти.
      for (final def in ContentPack.current.abilities) {
        final forms = def.tags.where(Tag.forms.contains).length;
        if (def.params.has('weaponMultiplier')) {
          expect(forms, 1, reason: def.name);
        }
        expect(forms, lessThanOrEqualTo(1), reason: def.name);
      }
    });

    test('описание называет ту ось, от которой способность растёт', () {
      // «×3.2 урона оружия» у способности с тегом «Чары» — ложь игроку ровно
      // того сорта, ради которой существует валидатор шаблонов: увидеть её
      // можно было только сверив описание с тегами вручную. Живой прогон её
      // и показал — на экране выбора, во второй же строке.
      for (final def in ContentPack.current.abilities) {
        if (!def.params.has('weaponMultiplier') &&
            !def.params.has('dpsFraction')) {
          continue;
        }
        final text = def.text;
        // Проклятия описывают дебаф, а не свой множитель: им называть нечего.
        if (!text.contains('урона оружия') && !text.contains('силы чар')) {
          expect(def.kind, AbilityKind.curse, reason: def.name);
          continue;
        }

        if (def.isSpell) {
          expect(text, contains('силы чар'), reason: def.name);
          expect(text, isNot(contains('урона оружия')), reason: def.name);
        } else {
          expect(text, contains('урона оружия'), reason: def.name);
          expect(text, isNot(contains('силы чар')), reason: def.name);
        }
      }
    });

    test('сила чар доходит до боя из собранного билда', () {
      // Тот же класс ошибки, что был с маной в `StatBlock.scaled`: стат,
      // потерянный при сборке, выглядит как способность, которая не работает.
      const withPower = ['spark_bolt'];
      final base = Tuning.heroBase;
      expect(base.spellPower, greaterThan(0.0),
          reason: 'без базы новичок не может кастовать вовсе');

      final runner = fight(withPower, hero: base);
      expect(dealt(runner, ticks: 60), greaterThan(0.0));
    });
  });

  group('теги', () {
    test('множитель по тегу усиливает только свой тег', () {
      const fireSpell = ['ember_burst'];
      const coldSpell = ['frost_spike'];

      double withTag(List<String> ids, Tag tag) => dealt(fight(
            ids,
            hero: stats(spellPower: 200.0, tagDamage: {tag: 1.0}),
          ));
      double plain(List<String> ids) =>
          dealt(fight(ids, hero: stats(spellPower: 200.0)));

      expect(withTag(fireSpell, Tag.fire), greaterThan(plain(fireSpell)),
          reason: '«+% к урону Огнём» обязано усиливать огненную способность');
      expect(withTag(coldSpell, Tag.fire), closeTo(plain(coldSpell), 1.0),
          reason: 'и не обязано усиливать холодную');
    });

    test('дот несёт теги того, кто его повесил', () {
      // Пока тик дота наносил урон без тегов, длительный урон не усиливался
      // ничем, кроме общего «+% к урону»: сборка вокруг дотов была невозможна.
      const burn = ['pyre'];

      final plain = dealt(fight(burn, hero: stats(spellPower: 200.0)));
      final boosted = dealt(fight(
        burn,
        hero: stats(spellPower: 200.0, tagDamage: {Tag.fire: 1.0}),
      ));

      expect(boosted, greaterThan(plain * 1.2),
          reason: 'горение — это Огонь, и огненные аффиксы его усиливают');
    });

    test('«+% к урону» не учитывается дважды', () {
      // `_dotDps` считал долевые прибавки, и `_applyDamage` считал их ещё раз:
      // дот от сборки с +150 % бил в 6.25 раза сильнее базового вместо 2.5.
      const burn = ['pyre'];

      final plain = dealt(fight(burn, hero: stats(spellPower: 200.0)));
      final doubled = dealt(fight(
        burn,
        hero: stats(spellPower: 200.0, increasedDamage: 1.0),
      ));

      expect(doubled / plain, closeTo(2.0, 0.15),
          reason: '+100 % это вдвое, а не вчетверо');
    });

    test('автоатака не безтеговая', () {
      // Иначе у сборки вокруг оружия не было бы ни одного аффикса, который
      // усиливает именно её, — а именно ею наносится львиная доля урона.
      final plain = dealt(fight(const [], hero: stats(attackDamage: 100.0)));
      final boosted = dealt(fight(
        const [],
        hero: stats(attackDamage: 100.0, tagDamage: {Tag.attack: 1.0}),
      ));

      expect(boosted, greaterThan(plain * 1.5));
    });
  });

  group('пропитка', () {
    test('меняет стихию автоатаки, и это режется сопротивлением', () {
      // Мост между двумя осями: игрок, нашедший три вещи с «+% к урону
      // Огнём», должен уметь применить их к автоатаке. Проверяется
      // сопротивлением цели, а не числом: тип урона либо сменился, либо нет.
      final plain = dealt(fight(
        const [],
        hero: stats(attackDamage: 100.0),
        enemy: warded(DamageType.fire),
      ));
      final infused = dealt(fight(
        const ['ember_infusion'],
        hero: stats(attackDamage: 100.0),
        enemy: warded(DamageType.fire),
      ));

      expect(infused, lessThan(plain * 0.5),
          reason: 'огненный клинок обязан упереться в огненный оберег');
    });

    test('пропитанная автоатака получает теги стихии', () {
      final infused = dealt(fight(
        const ['ember_infusion'],
        hero: stats(attackDamage: 100.0),
      ));
      final boosted = dealt(fight(
        const ['ember_infusion'],
        hero: stats(attackDamage: 100.0, tagDamage: {Tag.fire: 1.0}),
      ));

      expect(boosted, greaterThan(infused * 1.5),
          reason: 'ради этого пропитка и существует');
    });

    test('пропитка не отменяет того, что удар остаётся ударом', () {
      // «Атака» и «Удар» никуда не деваются: пропитанный клинок не перестаёт
      // быть оружием, и вложения в оружейную сборку не пропадают.
      final infused = dealt(fight(
        const ['ember_infusion'],
        hero: stats(attackDamage: 100.0),
      ));
      final boosted = dealt(fight(
        const ['ember_infusion'],
        hero: stats(attackDamage: 100.0, tagDamage: {Tag.strike: 1.0}),
      ));

      expect(boosted, greaterThan(infused * 1.5));
    });
  });

  group('тотемы', () {
    test('тотем бьёт сам, пока герой занят', () {
      // Единственный источник урона, который работает без участия героя.
      // Проверяется на герое без оружия: весь урон в волне — тотемный.
      final runner = fight(
        const ['cinder_totem'],
        hero: stats(spellPower: 200.0),
      );
      expect(dealt(runner, ticks: 80), greaterThan(0.0));
    });

    test('повторный каст обновляет тотем, а не ставит второй', () {
      // Иначе способность с перезарядкой короче своей длительности копила бы
      // тотемы и становилась единственным источником урона в игре.
      final short = fight(
        const ['cinder_totem'],
        hero: stats(spellPower: 200.0),
      );
      final first = dealt(short, ticks: 130);

      // Столько же времени, но каст был один: тотем стоял всё это время.
      // Если бы касты копили тотемы, второй отрезок бил бы кратно сильнее.
      final second = dealt(short, ticks: 130) - first;
      expect(second, lessThan(first * 1.6),
          reason: 'тотемы не должны накапливаться');
    });
  });

  test('повтор чар работает только на Чарах', () {
    // Зеркало «Эха клинка» для второй оси: без него у сборки на чарах не было
    // множителя частоты вовсе.
    final spell = ContentPack.current.ability('overcharge')!;
    expect(spell.kind, AbilityKind.repeatSpell);

    double sum(List<String> ids) {
      var total = 0.0;
      for (var seed = 1; seed <= 24; seed++) {
        final runner = WaveRunner(
          bus: EventBus(),
          depth: 5,
          hero: HeroState(stats(spellPower: 200.0, attackDamage: 200.0)),
          enemies: [EnemyInstance.spawn(dummy, 5)],
          rng: Rng(seed),
          abilities: AbilityRuntime.fromIds(ids),
        );
        total += dealt(runner, ticks: 100);
      }
      return total;
    }

    expect(sum(const ['spark_bolt', 'overcharge']),
        greaterThan(sum(const ['spark_bolt'])),
        reason: 'чары повторяются');
    expect(sum(const ['flame_lash', 'overcharge']),
        closeTo(sum(const ['flame_lash']), 1.0),
        reason: 'атаки — нет');
  });

  group('контент', () {
    test('у каждой стихии есть чем бить и чем это усилить', () {
      // Замечание с телефона было буквально таким: «на вещах есть модификатор
      // урона к огню, а умений огня нет». Проверка держит обе половины сразу:
      // тег без способностей — мёртвый аффикс, способности без тега —
      // сборка, которую нечем усилить.
      final abilityTags = {
        for (final def in ContentPack.current.abilities) ...def.tags,
      };
      final affixTags = {
        for (final def in ContentPack.current.statAffixes) ...def.family,
      };
      final treeTags = {
        for (final node in ContentPack.current.passiveTree.nodes)
          if (node.tag != null) node.tag!,
      };

      for (final element in Tag.elements) {
        expect(abilityTags, contains(element),
            reason: 'нет ни одной способности со стихией ${element.ru}');
        expect(affixTags, contains(element),
            reason: 'стихию ${element.ru} нечем усилить с вещей');
        expect(treeTags, contains(element),
            reason: 'в дереве нет ни одного узла на ${element.ru}');
      }
    });

    test('каждое семейство аффиксов на теги во что-то попадает', () {
      // Ролл по тегу, которого нет ни у одной способности и ни у автоатаки, —
      // это строка на вещи, которая ничего не делает.
      const autoAttack = [Tag.attack, Tag.strike, Tag.physical];
      final live = {
        for (final def in ContentPack.current.abilities) ...def.tags,
        ...autoAttack,
      };

      for (final def in ContentPack.current.statAffixes) {
        for (final tag in def.family) {
          expect(live, contains(tag), reason: '${def.id}: ${tag.ru}');
        }
      }
    });

    test('в каждую стихию можно собрать сборку, а не одно умение', () {
      // Одна огненная способность — это не билд, а строка в списке. Чтобы
      // стихия была выбором, в ней должно быть чем занять несколько слотов и
      // чем отличаться от соседней.
      for (final element in [Tag.fire, Tag.cold, Tag.lightning, Tag.voidTag]) {
        final kit = [
          for (final def in ContentPack.current.abilities)
            if (def.tags.contains(element)) def,
        ];
        expect(kit.length, greaterThanOrEqualTo(4), reason: element.ru);

        // Разные ВИДЫ, а не разные множители: способность, отличающаяся от
        // соседней только числом, билда не строит.
        expect({for (final def in kit) def.kind}.length,
            greaterThanOrEqualTo(3),
            reason: '${element.ru}: одни и те же механики с разными числами');
      }
    });

    test('обе оси открыты с первого рана', () {
      // Иначе выбор появляется не тогда, когда игрок его делает, а после
      // того, как он уже собрал единственную возможную сборку.
      final starters = [
        for (final def in ContentPack.current.abilities)
          if (def.isStarter) def,
      ];
      final forms = {
        for (final def in starters) ...def.tags.where(Tag.forms.contains),
      };
      expect(forms, containsAll(Tag.forms),
          reason: 'в стартовом наборе должны быть и Атаки, и Чары');

      final elements = {
        for (final def in starters) ...def.tags.where(Tag.elements.contains),
      };
      expect(elements.length, greaterThanOrEqualTo(3),
          reason: 'три стихии с первого рана — это уже выбор');
    });
  });
}
