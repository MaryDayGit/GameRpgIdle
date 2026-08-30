import 'dart:convert';

import 'package:rift/core/balance/curves.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/content_issue.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/item_text.dart';
import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/content/floor_modifier_def.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/gear.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/loot.dart';
import 'package:rift/core/sim/rng.dart';
import 'package:test/test.dart';

import '../tool/content_io.dart';

/// Глубокая копия сырых JSON: тесты ломают контент нарочно и не должны
/// портить его друг другу.
Map<String, Object?> _freshJson() {
  final src = readContentJson();
  return jsonDecode(jsonEncode(src)) as Map<String, Object?>;
}

List<ContentIssue> _issuesOf(Map<String, Object?> files) {
  try {
    ContentPack.parse(files);
  } on ContentException catch (e) {
    return e.issues;
  }
  return const [];
}

Map<String, dynamic> _entry(
    Map<String, Object?> files, String file, String list, String id) {
  final root = files[file] as Map<String, dynamic>;
  final items = root[list] as List;
  return items.firstWhere((e) => (e as Map)['id'] == id)
      as Map<String, dynamic>;
}

void main() {
  group('загрузка', () {
    test('настоящий контент проходит валидацию', () {
      final pack = loadContentFromDisk();

      expect(pack.enemies, hasLength(19));
      expect(pack.bosses, hasLength(4));
      // Число здесь — не догма, а страховка от «потерялся файл»: если
      // способностей вдруг стало вдвое меньше, это ошибка загрузки, а не
      // правка баланса.
      expect(pack.abilities.length, greaterThanOrEqualTo(25));
      expect(pack.statAffixes, hasLength(26));
      expect(pack.triggerAffixes, hasLength(12));
      expect(pack.relics, hasLength(25));
      expect(pack.floorModifiers, hasLength(8));
    });

    test('содержимое разобрано, а не просто прочитано', () {
      final pack = loadContentFromDisk();

      final rift = pack.ability('rift')!;
      expect(rift.tags, contains(Tag.voidTag));
      expect(rift.type, AbilityType.active);
      expect(rift.kind, AbilityKind.directDamage);
      expect(rift.params.integer('targets'), 99);

      // Семейство `tagDamage` разложено по осям: одно семейство из всех
      // тегов давало около процента шанса на нужный конкретный тег, и
      // собрать под него билд было нельзя.
      final elements = pack.statAffix('damage_element')!;
      expect(elements.family, Tag.elements);
      expect(elements.scales, isFalse);

      final forms = pack.statAffix('damage_form')!;
      expect(forms.family, Tag.forms);

      final crown = pack.relic('crown_of_obsession')!;
      expect(crown.kind, GearKind.helmet);
      expect(crown.exclusiveWith, ['charm_of_silence']);

      final swarm = pack.floorModifier('swarm')!;
      expect(swarm.value(FloorEffect.waveMultiplier), 2.0);
      expect(swarm.value(FloorEffect.mobHp), -0.40);
    });

    test('apply переносит контент в статики ядра', () {
      final pack = loadContentFromDisk();
      pack.apply();

      expect(Curves.tau, pack.curves.tau);
      expect(Tuning.heroBase.maxHp, pack.tuning.heroBase.maxHp);
      expect(Tuning.rarityWeights[Rarity.relic], 4.0);
      expect(Tuning.affixSlotsByRarity[Rarity.rare], 3);
      expect(Bestiary.enemies, hasLength(19));
      expect(Bestiary.bossFor(10)?.id, 'void_devourer');
      expect(Bestiary.bossFor(5)?.id, 'ash_lord');
      expect(Bestiary.bossFor(4), isNull);
    });
  });

  group('значения по умолчанию', () {
    // Значения по умолчанию в коде — это то, на чём считают тесты формул и
    // балансировщик без контента. Разъехавшись с JSON, они начинают проверять
    // не тот баланс, который увидит игрок.
    test('бестиарий в коде совпадает с JSON по всем числам', () {
      final pack = loadContentFromDisk();

      void same(EnemyArchetype code, EnemyArchetype json) {
        expect(code.hpMult, json.hpMult, reason: '${code.id}.hpMult');
        expect(code.dpsMult, json.dpsMult, reason: '${code.id}.dpsMult');
        expect(code.attackSpeed, json.attackSpeed,
            reason: '${code.id}.attackSpeed');
        expect(code.armorMult, json.armorMult, reason: '${code.id}.armorMult');
        expect(code.packMin, json.packMin, reason: '${code.id}.packMin');
        expect(code.packMax, json.packMax, reason: '${code.id}.packMax');
        expect(code.damageType, json.damageType,
            reason: '${code.id}.damageType');
        expect(code.resists, json.resists, reason: '${code.id}.resists');
        expect(code.everyFloors, json.everyFloors,
            reason: '${code.id}.everyFloors');
      }

      // Другие тесты в файле уже вызвали apply — возвращаем реестр к коду,
      // иначе сравнение JSON с самим собой всегда сходится.
      Bestiary.reset();
      final codeScavenger = Bestiary.byId('scavenger');
      final codeAshLord = Bestiary.byId('ash_lord');
      final codeDevourer = Bestiary.byId('void_devourer');

      same(codeScavenger, pack.enemies.firstWhere((e) => e.id == 'scavenger'));
      same(codeAshLord, pack.bosses.firstWhere((e) => e.id == 'ash_lord'));
      same(codeDevourer,
          pack.bosses.firstWhere((e) => e.id == 'void_devourer'));
    });
  });

  group('валидатор', () {
    test('ловит опечатку в имени поля', () {
      final files = _freshJson();
      final cleave = _entry(files, 'abilities', 'abilities', 'cleave');
      cleave['cooldwn'] = cleave.remove('cooldown');

      final issues = _issuesOf(files);
      expect(issues.map((i) => i.path), contains('abilities.abilities[0].cooldwn'));
      expect(issues.any((i) => i.message.contains('неизвестное поле')), isTrue);
      expect(issues.any((i) => i.path.endsWith('cooldown')), isTrue);
    });

    test('ловит опечатку в параметре внутри params', () {
      final files = _freshJson();
      final cleave = _entry(files, 'abilities', 'abilities', 'cleave');
      final params = cleave['params'] as Map<String, dynamic>;
      params['weaponMult'] = params.remove('weaponMultiplier');

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.path.endsWith('params.weaponMultiplier')),
          isTrue);
      expect(issues.any((i) => i.path.endsWith('params.weaponMult')), isTrue);
    });

    test('ловит неизвестный kind', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'cleave')['kind'] = 'megaBlast';

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('megaBlast')),
        isTrue,
        reason: 'kind без ветки в рантайме обязан валить загрузку',
      );
    });


    /// Проверки тегов.
    ///
    /// Тег — это не строка на карточке, а точка привязки аффиксов, узлов
    /// дерева и черт наёмника. Способность, у которой тег забыт, выглядит
    /// работающей и при этом не входит ни в один билд: заметить это можно
    /// только замером. Поэтому валидатор.
    test('ловит способность с уроном, но без формы', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'cleave')['tags'] =
          ['strike', 'physical'];

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('форма')),
        isTrue,
        reason: 'без формы способность не растёт ни от чего',
      );
    });

    test('ловит две формы у одной способности', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'cleave')['tags'] =
          ['attack', 'spell', 'strike', 'physical'];

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.message.contains('форма ровно одна')), isTrue);
    });

    test('ловит стихию, разошедшуюся с типом урона', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'ember_burst')['tags'] =
          ['spell', 'cold', 'area'];

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('Огонь')),
        isTrue,
        reason: 'огненной способности без тега Огонь нечего усиливать',
      );
    });

    test('ловит способность без тегов вовсе', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'fortitude')['tags'] =
          <String>[];

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.message.contains('не входит ни в один билд')),
          isTrue);
    });

    test('ловит узел дерева на tagDamage без тега', () {
      final files = _freshJson();
      final tree = files['passive_tree'] as Map<String, Object?>;
      final nodes = (tree['nodes'] as List).cast<Map<String, Object?>>();
      final node = nodes.firstWhere((n) => n['tag'] != null);
      node.remove('tag');

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('обязан называть тег')),
        isTrue,
        reason: 'узел без тега молча не даёт ничего',
      );
    });

    test('ловит способность, которую нечем открыть', () {
      // Способность, у которой нет ни стартового флага, ни задания, — мёртвый
      // груз в файле: список умений показывает открытое, а не всё, что есть,
      // и пересчитать это можно только вручную.
      final files = _freshJson();
      final quests = files['quests'] as Map<String, Object?>;
      (quests['quests'] as List).removeAt(0);

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.message.contains('не открывается ничем')),
          isTrue);
    });

    test('ловит две награды на одну способность', () {
      // Второе задание на то же умение ничего не даёт: способность уже
      // открыта, и игрок этого не поймёт — он увидит награду, которой нет.
      final files = _freshJson();
      final list = (files['quests'] as Map<String, Object?>)['quests'] as List;
      final first = Map<String, Object?>.from(list.first as Map);
      list.add({...first, 'id': 'duplicate', 'after': <String>[]});

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.message.contains('уже открывает')), isTrue);
    });

    test('ловит ссылку на несуществующее задание', () {
      final files = _freshJson();
      final list = (files['quests'] as Map<String, Object?>)['quests'] as List;
      (list[1] as Map)['after'] = ['нет_такого'];

      final issues = _issuesOf(files);
      expect(
          issues.any((i) => i.message.contains('несуществующее задание')),
          isTrue);
    });

    test('ловит задание про несуществующего босса', () {
      final files = _freshJson();
      final list = (files['quests'] as Map<String, Object?>)['quests'] as List;
      final boss = list.firstWhere(
          (q) => (q as Map)['condition'] == 'defeatBoss') as Map;
      (boss['params'] as Map)['boss'] = 'кто_то';

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.message.contains('нет такого босса')), isTrue);
    });

    test('ловит долевой стат, растущий от ilvl', () {
      final files = _freshJson();
      _entry(files, 'affixes_stat', 'affixes', 'increased_damage')['scales'] =
          true;

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('не может расти от ilvl')),
        isTrue,
        reason: 'иначе сила билда растёт в квадрате и формула стены не сходится',
      );
    });

    test('ловит триггер на запрещённом типе предмета', () {
      final files = _freshJson();
      (_entry(files, 'affixes_trigger', 'affixes', 'metronome')['kinds']
          as List)
        ..clear()
        ..add('armor');

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('потолок в шесть')),
        isTrue,
      );
    });

    test('ловит одностороннюю несовместимость реликтов', () {
      final files = _freshJson();
      _entry(files, 'relics', 'relics', 'charm_of_silence')
          .remove('exclusiveWith');

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('в обратную сторону')),
        isTrue,
      );
    });

    test('ловит несуществующую ссылку на реликт', () {
      final files = _freshJson();
      (_entry(files, 'relics', 'relics', 'crown_of_obsession')['exclusiveWith']
          as List)
        ..clear()
        ..add('nothing_here');

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('nothing_here')),
        isTrue,
      );
    });

    test('ловит неизвестный эффект модификатора этажа', () {
      final files = _freshJson();
      final heat = _entry(files, 'floor_modifiers', 'modifiers', 'heat');
      (heat['effects'] as Map<String, dynamic>)['mobSpeed'] = 0.2;

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('симуляция его не читает')),
        isTrue,
      );
    });

    test('ловит опечатку в balance.json, а не подставляет умолчание', () {
      final files = _freshJson();
      final balance = files['balance'] as Map<String, dynamic>;
      final curves = balance['curves'] as Map<String, dynamic>;
      curves['mobHpGrow'] = curves.remove('mobHpGrowth');

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.path == 'balance.curves.mobHpGrow'), isTrue);
      expect(issues.any((i) => i.path == 'balance.curves.mobHpGrowth'), isTrue);
    });

    test('ловит несовпадение версии схемы', () {
      final files = _freshJson();
      (files['relics'] as Map<String, dynamic>)['version'] = 2;

      final issues = _issuesOf(files);
      expect(issues.any((i) => i.path == 'relics.version'), isTrue);
    });

    test('сообщает обо всех проблемах разом, а не о первой', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'cleave')['kind'] = 'megaBlast';
      _entry(files, 'affixes_stat', 'affixes', 'increased_damage')['scales'] =
          true;
      (files['relics'] as Map<String, dynamic>)['version'] = 2;

      final issues = _issuesOf(files);
      expect(issues.length, greaterThanOrEqualTo(3));
    });

    test('пустой ввод не бросает исключение мимо ContentException', () {
      expect(
        () => ContentPack.parse(const {}),
        throwsA(isA<ContentException>()),
      );
    });
  });

  group('описания', () {
    test('плейсхолдер, не совпавший с параметром, валит загрузку', () {
      final files = _freshJson();
      _entry(files, 'abilities', 'abilities', 'cleave')['text'] =
          'Удар на {weaponMult:x} урона';

      final issues = _issuesOf(files);
      expect(
        issues.any((i) => i.message.contains('плейсхолдер {weaponMult}')),
        isTrue,
        reason: 'текст, разошедшийся с параметрами, — это ложь игроку',
      );
    });

    test('форматы подставляются по правилам автора текста', () {
      expect(
        TextTemplate.render('+{value:%} к урону', {'value': 0.085}),
        '+8.5 % к урону',
      );
      expect(
        TextTemplate.render('Каждый {n}-й удар на {multiplier:x}',
            {'n': 5, 'multiplier': 2.0}),
        'Каждый 5-й удар на ×2',
      );
      expect(
        TextTemplate.render('горение на {duration:s}', {'duration': 4.0}),
        'горение на 4 с',
      );
      // Тег подставляется в той форме, в какой читается строка про урон.
      // «+10 % к урону с тегом Огонь» — запись разработчика; игрок видит в
      // дереве пассивок «к урону Огнём» и на вещи обязан видеть то же самое.
      expect(
        TextTemplate.render('+{value:%} {tag}', {'value': 0.1}, tag: Tag.fire),
        '+10 % к урону Огнём',
      );
    });

    test('предмет читается словами целиком', () {
      loadContentFromDisk().apply();
      final rng = Rng(4);

      var described = 0;
      for (var i = 0; i < 60; i++) {
        final item = ItemFactory.roll(ilvl: 30, rng: rng);
        final lines = ItemText.lines(item);

        // Имплицит есть всегда, значит и строк всегда не меньше одной.
        expect(lines, isNotEmpty, reason: item.toString());
        for (final line in lines) {
          expect(line, isNot(contains('{')),
              reason: 'неподставленный плейсхолдер в «$line»');
        }
        if (item.triggerAffixId != null) described++;
      }
      expect(described, greaterThan(0), reason: 'триггеры обязаны описываться');
    });
  });
}
