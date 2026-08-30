import 'json_node.dart';

/// Что модификатор этажа умеет менять.
///
/// Закрытый список намеренно: модификатор с произвольным ключом эффекта — это
/// эффект, который в симуляции никто не читает. Такой контент выглядит
/// работающим и не работает.
enum FloorEffect {
  /// Сопротивления героя, в пунктах.
  resistFire,
  resistCold,
  resistVoid,

  /// Доля к урону с тегом Огонь.
  tagDamageFire,

  /// Доля к урону автоатак.
  autoAttackDamage,

  /// Доля к перезарядкам: плюс — быстрее, минус — медленнее.
  cooldownReduction,

  /// Флаги-выключатели: 1.0 — включено.
  regenDisabled,

  /// Выключает ауры, действующие на ВРАГОВ (замедление), и тотемы.
  ///
  /// Ауры, дающие статы герою, живут в собранном билде и считаются один раз
  /// на ран — их этот флаг не трогает, и текст модификатора обязан это
  /// отражать. Иначе игрок читает «ауры не работают», а «Клич ярости»
  /// продолжает работать.
  aurasDisabled,

  /// Доли к добыче.
  lootQuantity,
  chestRarityBonus,

  /// Множитель Эха с боссов этажа.
  bossEchoMultiplier,

  /// Доля к Эху за КАЖДЫЙ этаж, не только за босса.
  ///
  /// Отдельно от [bossEchoMultiplier] потому, что боссы редки: множитель на
  /// них — это награда раз в несколько этажей, а третьему пути развилки нужна
  /// награда на каждом. Замер показал, что добыча и редкость глубину почти не
  /// двигают (сундук полон, `Curves.lootLoopGain` = 1.02), а Эхо двигает: оно
  /// идёт в древо и остаётся навсегда.
  echoBonus,

  /// Доли к статам мобов.
  mobHp,
  mobDps,

  /// Множители количества: волн на этаже и мобов в пачке.
  waveMultiplier,
  packMultiplier,
}

/// Модификатор этажа: один минус и один плюс (GDD §6).
/// Виден на три этажа вперёд, Картограф расширяет обзор до шести.
class FloorModifierDef {
  const FloorModifierDef({
    required this.id,
    required this.name,
    required this.minus,
    required this.plus,
    required this.effects,
  });

  final String id;
  final String name;

  /// Тексты для UI. Ядро их не интерпретирует, но пустыми они быть не должны:
  /// модификатор, который игрок не может прочитать, — невидимая механика.
  final String minus;
  final String plus;

  final Map<FloorEffect, double> effects;

  double value(FloorEffect effect) => effects[effect] ?? 0.0;

  /// Множители, а не доли: их нельзя складывать.
  ///
  /// «Волн вдвое больше» плюс «волн вдвое больше» — это вчетверо, а не
  /// «плюс два». Список закрытый по той же причине, что и сам [FloorEffect]:
  /// новый множитель, забытый здесь, сложился бы как доля и дал бы тихо
  /// неверное число.
  static const _multiplicative = {
    FloorEffect.waveMultiplier,
    FloorEffect.packMultiplier,
    FloorEffect.bossEchoMultiplier,
  };

  /// Флаги-выключатели: складывать их бессмысленно, «выключено дважды» — это
  /// по-прежнему выключено.
  static const _flags = {
    FloorEffect.regenDisabled,
    FloorEffect.aurasDisabled,
  };

  /// Плата это или награда — по знаку и по смыслу эффекта.
  ///
  /// Нужно развилке: третий путь берёт награды обоих путей, а плату — только
  /// одного, и без этого разделения «сложить два модификатора» нечем.
  static bool isPenalty(FloorEffect effect, double value) => switch (effect) {
        FloorEffect.regenDisabled || FloorEffect.aurasDisabled => value > 0.0,
        FloorEffect.mobHp || FloorEffect.mobDps => value > 0.0,
        FloorEffect.waveMultiplier ||
        FloorEffect.packMultiplier =>
          value > 1.0,
        FloorEffect.resistFire ||
        FloorEffect.resistCold ||
        FloorEffect.resistVoid =>
          value < 0.0,
        FloorEffect.cooldownReduction => value < 0.0,
        // Добыча, редкость, Эхо и урон бывают только со знаком плюс: минус в
        // этих ключах в контенте не встречается, а встретится — валидатор
        // ловит его отдельно.
        _ => false,
      };

  /// Только награды модификатора.
  Map<FloorEffect, double> get rewards => {
        for (final e in effects.entries)
          if (!isPenalty(e.key, e.value)) e.key: e.value,
      };

  /// Только платы.
  Map<FloorEffect, double> get penalties => {
        for (final e in effects.entries)
          if (isPenalty(e.key, e.value)) e.key: e.value,
      };

  /// Оба пути сразу: обе платы и обе награды.
  ///
  /// Существует ради развилки — третий путь, который наёмник не выберет сам
  /// (см. `ForkChooser`). Новых чисел не вводит: composition уже написанного
  /// контента, и потому балансировать его отдельно не нужно — он ровно
  /// настолько силён и опасен, насколько сильны и опасны его половины.
  factory FloorModifierDef.combine(
    FloorModifierDef a,
    FloorModifierDef b, {
    Map<FloorEffect, double>? effectsA,
    Map<FloorEffect, double>? effectsB,
  }) {
    final left = effectsA ?? a.effects;
    final right = effectsB ?? b.effects;
    final effects = <FloorEffect, double>{};

    for (final effect in FloorEffect.values) {
      final x = left[effect] ?? 0.0;
      final y = right[effect] ?? 0.0;
      if (x == 0.0 && y == 0.0) continue;

      if (_flags.contains(effect)) {
        effects[effect] = x > y ? x : y;
      } else if (_multiplicative.contains(effect)) {
        // Отсутствующий множитель — это единица, а не ноль: иначе один путь
        // с «волн вдвое» и второй без него дали бы ноль волн.
        effects[effect] = (x == 0.0 ? 1.0 : x) * (y == 0.0 ? 1.0 : y);
      } else {
        effects[effect] = x + y;
      }
    }

    return FloorModifierDef(
      id: '${a.id}$composedMark${b.id}',
      name: '${a.name} и ${b.name}',
      minus: '${a.minus}. ${b.minus}',
      plus: '${a.plus}. ${b.plus}',
      effects: effects,
    );
  }

  /// Знак составного модификатора: путь развилки и разлом дня вместе.
  ///
  /// Составные модификаторы записываются в журнал тем же полем `modifierId`,
  /// что и обычные, и по этому знаку разбираются обратно
  /// (`ContentPack.floorModifier`). Иначе журнал разлома молчал бы: в паке
  /// такого id нет, поиск возвращал бы `null`, и строка просто не печаталась.
  static const composedMark = '+';

  /// Знак смелого пути: оба пути развилки, но только их награды.
  ///
  /// Отдельный знак нужен потому, что смелый путь — не та же композиция:
  /// у него нет платы. Разбери его как обычную пару — и журнал приписал бы
  /// игроку минусы, которых он не платил.
  static const boldMark = '&';

  bool get disablesRegen => value(FloorEffect.regenDisabled) > 0.0;
  bool get disablesAuras => value(FloorEffect.aurasDisabled) > 0.0;

  static const _keys = {'id', 'ru', 'minus', 'plus', 'effects'};

  static FloorModifierDef parse(JsonNode node) {
    node.checkKeys(_keys);

    final effectsNode = node.child('effects', required: true);
    final effects = effectsNode.asEnumDoubleMap(
      FloorEffect.values,
      unknownMessage: 'неизвестный эффект, симуляция его не читает',
    );
    if (effects.isEmpty) {
      node.issues.add(effectsNode.path, 'модификатор без эффектов');
    }

    return FloorModifierDef(
      id: node.str('id'),
      name: node.str('ru'),
      minus: node.str('minus'),
      plus: node.str('plus'),
      effects: Map.unmodifiable(effects),
    );
  }

  @override
  String toString() => 'FloorModifierDef($id)';
}
