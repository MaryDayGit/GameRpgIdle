import 'package:flutter/material.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/ability_def.dart';
import 'package:rift/core/content/text_template.dart';
import 'package:rift/core/model/stat_block.dart';
import 'package:rift/core/model/tags.dart';

import 'format.dart';

/// Подробная карточка способности.
///
/// Существует ради одного вопроса, на который в игре негде было получить
/// ответ: **от чего это умение растёт и сколько оно бьёт ИМЕННО У МЕНЯ.**
///
/// Строка «Актив · 3 с · 10 маны · ×2.9 урона» отвечает на него только для
/// того, кто уже знает устройство игры. Игрок видит «×2.9 урона» и не может
/// узнать — урона чего, от какого стата, и почему найденный «+18 % к урону
/// Огнём» на эту способность не действует.
///
/// Поэтому здесь не описание, а РАЗБОР: каждая строка расчёта названа своим
/// именем и подставлена настоящим числом из сборки. Число, которое игрок
/// может проверить глазами, объясняет систему лучше любого абзаца.
class AbilityDetailSheet extends StatelessWidget {
  const AbilityDetailSheet({
    super.key,
    required this.def,
    required this.stats,
  });

  final AbilityDef def;

  /// Характеристики собранного наёмника. Разбор считается по ним, а не по
  /// эталонным: «сколько это бьёт вообще» — вопрос, которого игрок не задаёт.
  final StatBlock stats;

  static Future<void> show(
    BuildContext context, {
    required AbilityDef def,
    required StatBlock stats,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => AbilityDetailSheet(def: def, stats: stats),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(def.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 4),
              Text(_kindLine(def),
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 10),
              Text(
                TextTemplate.render(def.text, _params(def)),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 20),

              ..._scaling(context),
              ..._damageType(context),
              ..._cost(context),
              ..._tags(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- От чего растёт --------------------------------------------------------

  /// Разбор урона по шагам.
  ///
  /// Порядок строк повторяет порядок формулы: стат сборки, множитель
  /// способности, основа удара, увеличения, итог. Так видно не только
  /// «сколько», но и «где именно моя вещь вошла в это число».
  List<Widget> _scaling(BuildContext context) {
    final rows = <Widget>[];

    final multiplier = def.params.dbl('weaponMultiplier');
    final increased = _increasedFraction();

    if (multiplier > 0.0) {
      final source = def.isSpell ? stats.spellPower : stats.attackDamage;
      final base = source * multiplier;
      final hit = base * (1.0 + increased);

      rows.addAll([
        _row(
          def.isSpell ? 'Сила чар' : 'Урон оружия',
          money(source),
          def.isSpell
              ? 'Ваша характеристика. Урон оружия этому умению не помогает '
                  'вовсе.'
              : 'Ваша характеристика. Сила чар этому умению не помогает '
                  'вовсе.',
        ),
        _row('Множитель умения', '×${_num(multiplier)}',
            'Число самого умения, оно не меняется.'),
        _row('Основа удара', money(base), null, strong: true),
        _row('Ваши увеличения', '+${(increased * 100).round()} %',
            _increasedBreakdown()),
        _row('Урон за удар', money(hit), null, strong: true),
      ]);

      final targets = def.params.integer('targets', 1);
      if (targets > 1) {
        rows.add(_row('Целей за раз', targets >= 99 ? 'вся волна' : '$targets',
            'Урон считается каждой цели отдельно.'));
      }

      if (def.kind == AbilityKind.execute) {
        final bonus = def.params.dbl('bonusBelow');
        final threshold = def.params.dbl('threshold');
        rows.add(_row(
          'По раненой цели',
          money(hit * (1.0 + bonus)),
          'Ниже ${(threshold * 100).round()} % здоровья цели. Умение '
              'сама выбирает самого раненого врага.',
        ));
      }
      if (def.kind == AbilityKind.chainDamage) {
        final falloff = def.params.dbl('falloff');
        rows.add(_row('Затухание цепи', '−${(falloff * 100).round()} %',
            'Каждая следующая цель получает на столько меньше предыдущей.'));
      }
      if (def.params.dbl('bonusVsSlowed') > 0.0) {
        final bonus = def.params.dbl('bonusVsSlowed');
        rows.add(_row('По замедленным', money(hit * (1.0 + bonus)),
            'Замедление даёт «Ледяной покров» и узел «Стылая хватка».'));
      }
    }

    // Доты считаются не от удара, а от вашего урона в секунду.
    if (def.params.has('dpsFraction')) {
      final fraction = def.params.dbl('dpsFraction');
      final duration = def.params.dbl('duration');
      final perSecond = def.isSpell
          ? stats.spellPower * Tuning.spellReferenceRate
          : stats.attackDamage * stats.effectiveAttackSpeed;
      final dps = perSecond * fraction * (1.0 + increased);

      if (multiplier <= 0.0) {
        rows.addAll([
          _row(
            def.isSpell ? 'Сила чар' : 'Урон оружия',
            money(def.isSpell ? stats.spellPower : stats.attackDamage),
            def.isSpell
                ? 'Ваша характеристика. Урон оружия этому умению '
                    'не помогает.'
                : 'Ваша характеристика. Сила чар этому умению не помогает.',
          ),
          _row('Ваши увеличения', '+${(increased * 100).round()} %',
              _increasedBreakdown()),
        ]);
      }
      rows.addAll([
        _row('Длительный урон', '${money(dps)} в секунду',
            'Доля вашего урона в секунду: ${(fraction * 100).round()} %.'),
        _row('Держится', '${_num(duration)} с', null),
        _row('Всего за наложение', money(dps * duration), null, strong: true),
      ]);
    }

    if (def.kind == AbilityKind.summonTotem) {
      final interval = def.params.dbl('interval');
      final duration = def.params.dbl('duration');
      rows.add(_row('Бьёт раз в', '${_num(interval)} с',
          'Тотем стоит ${_num(duration)} с и бьёт, пока вы заняты другим. '
              'Повторное применение обновляет тот же тотем, а не ставит '
              'второй.'));
    }

    if (def.kind == AbilityKind.heal) {
      final fraction = def.params.dbl('fractionOfMaxHp');
      rows.add(_row('Восстанавливает', money(stats.maxHp * fraction),
          '${(fraction * 100).round()} % вашего максимума HP. '
              'На полном здоровье не тратится.'));
    }

    if (def.kind == AbilityKind.infusion) {
      rows.add(_row(
        'Автоатака бьёт',
        def.damageType.ru,
        'Вместо физического урона. Теги автоатаки становятся '
            '«Атака · Удар · ${def.damageType.tag.ru}» — и всё, что усиливает '
            'эту стихию, начинает работать на автоатаке.',
      ));
      final more = def.params.dbl('moreDamage');
      if (more > 0.0) {
        rows.add(_row('И бьёт сильнее', '+${(more * 100).round()} %',
            'Множитель к урону автоатаки.'));
      }
    }

    if (def.kind == AbilityKind.auraStat) {
      rows.add(_row('Даёт постоянно', _statLine(),
          'Работает всё время, пока аура в слоте.'));
    }

    if (def.kind == AbilityKind.buff) {
      rows.add(_row('Даёт на ${_num(def.params.dbl('duration'))} с',
          _statLine(), null));
    }

    if (def.kind == AbilityKind.repeatAttack) {
      rows.add(_row('Шанс ударить дважды',
          '${(def.params.dbl('chance') * 100).round()} %',
          'Второй удар бесплатный и не трогает перезарядки.'));
    }
    if (def.kind == AbilityKind.repeatSpell) {
      rows.add(_row('Шанс сработать дважды',
          '${(def.params.dbl('chance') * 100).round()} %',
          'Работает только на умениях с тегом «Чары». Повтор бесплатный.'));
    }
    if (def.kind == AbilityKind.thorns) {
      rows.add(_row('Возвращает ударившему',
          '${(def.params.dbl('fractionReturned') * 100).round()} %',
          'Долю полученного урона. Считается от того, что до вас дошло: '
              'броня и сопротивления уменьшают и его.'));
    }
    if (def.kind == AbilityKind.lowLifeGuard) {
      rows.add(_row('Ниже ${(def.params.dbl('threshold') * 100).round()} % HP',
          '−${(def.params.dbl('lessDamageTaken') * 100).round()} % урона',
          'Множитель к получаемому урону, а не к броне.'));
    }
    if (def.kind == AbilityKind.conditionalLeech) {
      rows.add(_row('Ниже ${(def.params.dbl('threshold') * 100).round()} % HP',
          'вампиризм ×${_num(def.params.dbl('leechMultiplier'))}',
          'Множитель к вампиризму, который у вас уже есть. Без вампиризма '
              'умножать нечего.'));
    }
    if (def.kind == AbilityKind.statTradeoff) {
      rows.add(_row('Размен', _tradeoffLine(),
          'Считается один раз при сборке, а не в бою.'));
    }
    if (def.kind == AbilityKind.auraSlow) {
      rows.add(_row('Замедляет атакующих',
          '−${(def.params.dbl('slow') * 100).round()} %',
          'Скорость их атак. Замедленные цели — условие для «Морозного шипа» '
              'и узла «Охотник на медленных».'));
    }
    if (def.kind == AbilityKind.corpseExplosion) {
      rows.add(_row('Взрыв трупа',
          '${(def.params.dbl('fractionOfMaxHp') * 100).round()} % HP убитого',
          'Только по проклятым целям. От ваших характеристик урон взрыва '
              'не зависит — зато теги на него действуют.'));
    }
    if (def.kind == AbilityKind.curse) {
      rows.add(_row('Цель получает больше урона',
          '+${(def.params.dbl('damageTakenIncrease') * 100).round()} %',
          'От любого источника, ${_num(def.params.dbl('duration'))} с. '
              'Проклятие — условие для «Печати бездны» и узла '
              '«Печать увядания».'));
    }
    if (def.kind == AbilityKind.critApplyDot) {
      rows.add(_row('Срабатывает от крита', 'ваш шанс — '
          '${(stats.critChance * 100).toStringAsFixed(1)} %',
          'Без шанса крита умение не работает вовсе.'));
    }

    // Итог в секунду — только там, где он честно считается.
    final perSecond = _damagePerSecond(increased);
    if (perSecond != null) {
      rows.add(const SizedBox(height: 4));
      rows.add(_row('Итого в секунду', money(perSecond),
          'С учётом перезарядки и числа целей. Мана и живучесть цели тут '
              'не учтены.',
          strong: true));
    }

    if (rows.isEmpty) return const [];
    return [_header('От чего растёт'), ...rows, const SizedBox(height: 20)];
  }

  /// Урон в секунду, если его можно посчитать без вранья.
  double? _damagePerSecond(double increased) {
    final cooldown = _effectiveCooldown();
    final multiplier = def.params.dbl('weaponMultiplier');

    if (def.kind == AbilityKind.summonTotem) {
      final source = def.isSpell ? stats.spellPower : stats.attackDamage;
      final interval = def.params.dbl('interval');
      if (interval <= 0.0) return null;
      final targets = def.params.integer('targets', 1);
      return source * multiplier * targets * (1.0 + increased) / interval;
    }

    if (!def.isActive || cooldown <= 0.0 || multiplier <= 0.0) return null;

    final source = def.isSpell ? stats.spellPower : stats.attackDamage;
    final targets = def.params.integer('targets', 1).clamp(1, 4);
    return source * multiplier * targets * (1.0 + increased) / cooldown;
  }

  double _effectiveCooldown() =>
      def.cooldown * (1.0 - stats.cooldownReduction).clamp(0.1, 1.0);

  // --- Тип урона -------------------------------------------------------------

  List<Widget> _damageType(BuildContext context) {
    if (!_dealsDamage) return const [];

    return [
      _header('Тип урона'),
      _row(def.damageType.ru, '', _resistNote()),
      const SizedBox(height: 20),
    ];
  }

  String _resistNote() => switch (def.damageType) {
        DamageType.physical =>
          'Уменьшается бронёй цели. Броня врагов растёт с глубиной, поэтому '
              'физический урон труднее всего тащить вниз.',
        _ => 'Уменьшается сопротивлением «${def.damageType.ru}» у цели, и '
            'бронёй тоже. У чудовищ сопротивление своей стихии обычно '
            'высокое — бить их той же стихией невыгодно.',
      };

  bool get _dealsDamage =>
      def.params.has('weaponMultiplier') ||
      def.params.has('dpsFraction') ||
      def.kind == AbilityKind.corpseExplosion ||
      def.kind == AbilityKind.thorns ||
      def.kind == AbilityKind.infusion;

  // --- Цена ------------------------------------------------------------------

  List<Widget> _cost(BuildContext context) {
    final rows = <Widget>[];

    if (def.isActive) {
      rows.add(_row('Перезарядка', '${_num(_effectiveCooldown())} с',
          stats.cooldownReduction > 0.0
              ? 'Базовая ${_num(def.cooldown)} с, ваше сокращение '
                  '−${(stats.cooldownReduction * 100).round()} %.'
              : 'Сокращается свойством «−% ко времени перезарядки» и лучом '
                  '«Порыв».'));
      rows.add(_row('Стоит маны', money(def.manaCost),
          'Ваш запас ${money(stats.maxMana)}, восстановление '
              '${_num(stats.manaRegen)} в секунду. Не хватило — умение '
              'ждёт, наёмник продолжает бить оружием.'));
      final drain = _effectiveCooldown() > 0.0
          ? def.manaCost / _effectiveCooldown()
          : 0.0;
      rows.add(_row('Расход', '${_num(drain)} маны в секунду',
          'Столько это умение съедает из общего запаса, если срабатывает '
              'без перерыва.'));
    } else if (def.isAura) {
      rows.add(_row('Резервирует', '${(def.manaReserve * 100).round()} % маны',
          'Забирает и запас, и восстановление — насовсем, пока аура в слоте. '
              'Из ${money(stats.maxMana)} останется '
              '${money(stats.maxMana * (1.0 - def.manaReserve))}.'));
    } else {
      rows.add(_row('Стоит', 'одно место',
          'Пассивное умение работает всегда и маны не тратит. Его цена — '
              'место, которое не досталось активному.'));
    }

    return [_header('Цена'), ...rows, const SizedBox(height: 20)];
  }

  // --- Теги ------------------------------------------------------------------

  List<Widget> _tags(BuildContext context) {
    if (def.tags.isEmpty) return const [];

    return [
      _header('Теги'),
      const Text(
        'Тег — единственное, за что цепляются вещи, дерево пассивок и черта '
        'наёмника. Множитель по тегу, которого у умения нет, на него не '
        'действует.',
        style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.35),
      ),
      const SizedBox(height: 10),
      for (final tag in def.tags) _tagRow(tag),
    ];
  }

  Widget _tagRow(Tag tag) {
    final value = stats.tagDamage[tag] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Доли, а не фиксированные ширины: «Длительность» при крупном
          // системном шрифте шире ста четырёх точек, и колонка обрезала бы
          // ровно название тега — то, ради чего строку и читают.
          Expanded(
            flex: 4,
            child: Text(tag.ru,
                style: const TextStyle(fontSize: 13, height: 1.3)),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text(
              value > 0.0 ? '+${(value * 100).round()} %' : '—',
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: value > 0.0 ? FontWeight.w600 : FontWeight.w400,
                color: value > 0.0 ? Colors.white : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 7,
            child: Text(
              _tagMeaning(tag),
              style: const TextStyle(
                  fontSize: 11, color: Colors.white38, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  static String _tagMeaning(Tag tag) => switch (tag) {
        Tag.fire ||
        Tag.cold ||
        Tag.lightning ||
        Tag.voidTag ||
        Tag.physical =>
          'Стихия. Ищите «+% к урону ${tag.ru}» на вещах и луч этой стихии '
              'в дереве.',
        Tag.attack => 'Растёт от урона оружия. Его же несёт автоатака.',
        Tag.spell => 'Растёт от силы чар. Урон оружия не помогает.',
        Tag.projectile => 'Летит в цель. Аффиксы на снаряды усиливают.',
        Tag.area => 'Задевает нескольких. Аффиксы на область усиливают.',
        Tag.duration => 'Урон идёт со временем, а не сразу.',
        Tag.curse => 'Вешает проклятие. Его ждут «Печать бездны» и '
            '«Печать увядания».',
        Tag.aura => 'Работает постоянно за резерв маны.',
        Tag.totem => 'Бьёт сам, пока наёмник занят другим.',
        Tag.strike => 'Удар оружием. Его же несёт автоатака.',
        Tag.blood => 'Кровь: вампиризм, кровотечение, добивание.',
      };

  // --- Вспомогательное -------------------------------------------------------

  double _increasedFraction() {
    var v = stats.increasedDamage;
    for (final tag in def.tags) {
      v += stats.tagDamage[tag] ?? 0.0;
    }
    return v;
  }

  /// Из чего сложились увеличения. Без разбивки строка «+45 %» ничего не
  /// объясняет: игрок не может понять, какая его вещь сюда вошла.
  String _increasedBreakdown() {
    final parts = <String>[];
    if (stats.increasedDamage > 0.0) {
      parts.add('общее +${(stats.increasedDamage * 100).round()} %');
    }
    for (final tag in def.tags) {
      final v = stats.tagDamage[tag] ?? 0.0;
      if (v > 0.0) parts.add('${tag.ru} +${(v * 100).round()} %');
    }
    if (parts.isEmpty) {
      return 'Увеличений нет. Их дают свойства вещей, дерево пассивок и '
          'черта наёмника.';
    }
    return 'Складывается: ${parts.join(', ')}.';
  }

  String _statLine() {
    final name = def.params.str('stat');
    final value = def.params.dbl('value');
    final key = StatKeyText.byName(name);
    return key == null
        ? '$name $value'
        : '${key.percent ? '+${(value * 100).round()} %' : '+${_num(value)}'} '
            '${key.ru}';
  }

  String _tradeoffLine() {
    final armor = def.params.dbl('armorPct');
    final speed = def.params.dbl('attackSpeedPct');
    String part(double v, String what) =>
        '${v >= 0 ? '+' : '−'}${(v.abs() * 100).round()} % $what';
    return '${part(armor, 'брони')}, ${part(speed, 'скорости атаки')}';
  }

  static String _kindLine(AbilityDef def) => def.isActive
      ? 'Активное — срабатывает само, когда готово и хватает маны'
      : def.isAura
          ? 'Аура — работает всегда, держит часть маны занятой'
          : 'Пассивное — работает всегда и ничего не стоит';

  static Map<String, double> _params(AbilityDef def) => {
        for (final entry in def.params.raw.entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      };

  static String _num(double v) {
    final rounded = v.roundToDouble();
    return (v - rounded).abs() < 0.005
        ? rounded.toStringAsFixed(0)
        : v.toStringAsFixed(v.abs() < 1.0 ? 2 : 1);
  }

  static Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
      );

  static Widget _row(String label, String value, String? note,
          {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        color: strong ? Colors.white : Colors.white70,
                        fontWeight:
                            strong ? FontWeight.w600 : FontWeight.w400,
                      )),
                ),
                const SizedBox(width: 8),
                // Значение тоже гибкое: «3.3 маны в секунду» рядом с длинной
                // подписью не влезает, и без этого строка уезжала за край.
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white38, height: 1.3)),
            ],
          ],
        ),
      );
}

/// Название стата по имени из контента.
///
/// Отдельно от `StatKey.ru`, потому что там формулировки для строки аффикса
/// («% к урону»), а здесь нужен именительный падеж после числа.
class StatKeyText {
  const StatKeyText(this.ru, {this.percent = false});

  final String ru;
  final bool percent;

  static StatKeyText? byName(String name) => switch (name) {
        'increasedDamage' => const StatKeyText('к урону', percent: true),
        'increasedAttackSpeed' =>
          const StatKeyText('к скорости атаки', percent: true),
        'armorPct' => const StatKeyText('к броне', percent: true),
        'maxHpPct' => const StatKeyText('к максимуму HP', percent: true),
        'leech' => const StatKeyText('вампиризма', percent: true),
        'critChance' =>
          const StatKeyText('к шансу критического удара', percent: true),
        'critMulti' =>
          const StatKeyText('к множителю крита', percent: true),
        'cooldownReduction' =>
          const StatKeyText('ко времени перезарядки', percent: true),
        'hpRegen' => const StatKeyText('восстановления HP в секунду'),
        'manaRegen' => const StatKeyText('восстановления маны в секунду'),
        'attackDamage' => const StatKeyText('к урону оружия'),
        'spellPower' => const StatKeyText('к силе чар'),
        'resistFire' ||
        'resistCold' ||
        'resistLightning' ||
        'resistVoid' =>
          const StatKeyText('ко всем сопротивлениям'),
        _ => null,
      };
}
