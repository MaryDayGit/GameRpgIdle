import '../balance/tuning.dart';
import '../content/content_pack.dart';
import '../content/floor_modifier_def.dart';
import 'rng.dart';

/// Политика выбора пути, когда игрока нет в приложении (GDD §2.6).
///
/// Игрок выбирает сам, если он здесь; иначе выбирает наёмник по заданной
/// политике. Третья, самая жирная опция доступна только при присутствии —
/// это награда за присутствие, а не наказание за отсутствие.
enum ForkPolicy {
  /// Добыча важнее безопасности.
  loot('Искать добычу'),

  /// Безопасность важнее добычи.
  safety('Идти глубже'),

  /// Эхо важнее всего.
  echo('Охотиться на чудовищ'),

  /// Как повезёт.
  random('Как повезёт');

  const ForkPolicy(this.ru);

  final String ru;
}

/// Развилка: два пути, третий «за присутствие» и выбранный.
class Fork {
  const Fork({
    required this.options,
    required this.chosen,
    required this.bold,
  });

  /// Два обычных пути. Между ними и только между ними выбирает приказ.
  final List<FloorModifierDef> options;

  /// Третий путь: оба обычных сразу — обе платы и обе награды.
  ///
  /// Доступен ТОЛЬКО присутствующему игроку. Отдельным полем, а не третьим
  /// элементом [options], намеренно: будь он в списке, приказ рано или поздно
  /// выбрал бы его — не сегодня, так после правки оценок. Правило «наёмник
  /// один такого не выберет» должно держаться на устройстве кода, а не на
  /// договорённости.
  final FloorModifierDef bold;

  final FloorModifierDef chosen;

  /// Индекс, которым выбирается смелый путь.
  static const boldIndex = 2;

  /// Все пути по порядку — для экрана и для проверки решения игрока.
  List<FloorModifierDef> get allOptions => [...options, bold];
}

/// Выбор пути на развилке.
///
/// Оценки ниже — это ПОЛИТИКА отсутствующего игрока, а не числа баланса.
/// Они ранжируют два варианта между собой и больше нигде не используются:
/// ни одна кривая на них не стоит.
class ForkChooser {
  ForkChooser._();

  /// Насколько путь щедр на добычу.
  static double lootScore(FloorModifierDef m) =>
      m.value(FloorEffect.lootQuantity) + m.value(FloorEffect.chestRarityBonus);

  /// Насколько путь опасен. Складываются только те эффекты, которые реально
  /// повышают шанс смерти: больше мобов, крепче мобы, сильнее бьют, срезаны
  /// сопротивления, отключён реген.
  static double dangerScore(FloorModifierDef m) {
    var danger = 0.0;
    danger += m.value(FloorEffect.mobDps);
    danger += m.value(FloorEffect.mobHp);
    danger += (m.value(FloorEffect.waveMultiplier) - 1.0).clamp(0.0, 10.0);
    danger += (m.value(FloorEffect.packMultiplier) - 1.0).clamp(0.0, 10.0);
    danger -= m.value(FloorEffect.resistFire) / 100.0;
    danger -= m.value(FloorEffect.resistCold) / 100.0;
    danger -= m.value(FloorEffect.resistVoid) / 100.0;
    danger -= m.value(FloorEffect.cooldownReduction);
    if (m.disablesRegen) danger += 0.2;
    if (m.disablesAuras) danger += 0.2;
    return danger;
  }

  static double echoScore(FloorModifierDef m) =>
      m.value(FloorEffect.bossEchoMultiplier);

  /// Катит развилку для этажа. Детерминирована по сиду рана и глубине:
  /// один и тот же ран обязан предлагать одни и те же пути.
  /// [chosen] — решение игрока: индекс пути в [Fork.options]. Когда он
  /// задан, политика не спрашивается вовсе. Спуск при этом остаётся
  /// детерминированным: он функция от снимка, сида и СПИСКА РЕШЕНИЙ, и по
  /// этим трём вещам воспроизводится тик в тик.
  static Fork roll(int seed, int depth, ForkPolicy policy, {int? chosen}) {
    final all = ContentPack.current.floorModifiers;
    if (all.isEmpty) {
      throw StateError('Нет модификаторов этажей');
    }

    final rng = Rng.stream(seed, depth, 0, RngPurpose.fork);
    final first = all[rng.nextInt(all.length)];

    var second = first;
    if (all.length > 1) {
      // Второй путь обязан отличаться от первого: развилка из двух одинаковых
      // вариантов — это не выбор, а лишний экран.
      while (identical(second, first)) {
        second = all[rng.nextInt(all.length)];
      }
    }

    final options = [first, second];
    final bold = boldPath(first, second);

    if (chosen != null && chosen >= 0 && chosen <= Fork.boldIndex) {
      return Fork(
        options: options,
        bold: bold,
        chosen: chosen == Fork.boldIndex ? bold : options[chosen],
      );
    }
    return Fork(
      options: options,
      bold: bold,
      chosen: _choose(options, policy, rng),
    );
  }

  /// Третий путь: ЛУЧШАЯ награда развилки, и взять её может только игрок.
  ///
  /// Награды обоих путей плюс прибавка за смелость. **Платы нет вовсе** — она
  /// уже уплачена тем, что игрок открыл игру и нажал. В этом весь смысл: тот,
  /// кто здесь, получает больше, чем наёмник, решавший сам.
  ///
  /// ## Почему без платы
  ///
  /// Сначала третий путь брал обе платы, потом — более мягкую из двух. Обе
  /// версии замерились ХУЖЕ обычного выбора: за двенадцать кампаний по
  /// двадцать контрактов «всегда смело» давало 103 и 130 этажей против 143 у
  /// «здесь, без смелого».
  ///
  /// Причина второй неудачи поучительна. «Более мягкая плата» определялась
  /// оценкой опасности, которой пользуется приказ, а та не знает про сборку:
  /// «реген не работает» весит в ней 0.2 — столько же, сколько «мобы бьют на
  /// 20 % сильнее». Для снаряжённого наёмника, который на регене и держится,
  /// это несопоставимые вещи. Третий путь систематически выбирал то, что
  /// оценке кажется мелочью, а живой сборке стоит спуска.
  ///
  /// Чинить оценку значило бы учить её всем сборкам сразу. Проще и честнее
  /// признать: плата третьего пути — не минус внутри игры, а присутствие.
  static FloorModifierDef boldPath(
      FloorModifierDef first, FloorModifierDef second) {
    final combined = FloorModifierDef.combine(
      first,
      second,
      effectsA: first.rewards,
      effectsB: second.rewards,
    );

    final effects = Map<FloorEffect, double>.from(combined.effects);
    if (Tuning.boldForkLootBonus > 0) {
      effects[FloorEffect.lootQuantity] =
          (effects[FloorEffect.lootQuantity] ?? 0.0) + Tuning.boldForkLootBonus;
    }
    if (Tuning.boldForkRarityBonus > 0) {
      effects[FloorEffect.chestRarityBonus] =
          (effects[FloorEffect.chestRarityBonus] ?? 0.0) +
              Tuning.boldForkRarityBonus;
    }
    if (Tuning.boldForkEchoBonus > 0) {
      effects[FloorEffect.echoBonus] =
          (effects[FloorEffect.echoBonus] ?? 0.0) + Tuning.boldForkEchoBonus;
    }

    return FloorModifierDef(
      id: '${first.id}${FloorModifierDef.boldMark}${second.id}',
      name: combined.name,
      minus: 'Платы нет',
      plus: '${first.plus}. ${second.plus}${_boldReward()}',
      effects: effects,
    );
  }

  /// Приписка про прибавку сверх наград обоих путей. Собирается из ручек, а
  /// не пишется строкой: число в тексте, разошедшееся с числом в симуляции, —
  /// это ровно тот случай, когда экран врёт игроку.
  static String _boldReward() {
    final parts = <String>[
      if (Tuning.boldForkEchoBonus > 0)
        '+${(Tuning.boldForkEchoBonus * 100).round()} % Эха с каждого этажа',
      if (Tuning.boldForkLootBonus > 0)
        '+${(Tuning.boldForkLootBonus * 100).round()} % добычи',
      if (Tuning.boldForkRarityBonus > 0)
        '+${Tuning.boldForkRarityBonus} к рангу редкости сундука',
    ];
    return parts.isEmpty ? '' : '. И сверх того: ${parts.join(' и ')}';
  }

  static FloorModifierDef _choose(
      List<FloorModifierDef> options, ForkPolicy policy, Rng rng) {
    switch (policy) {
      case ForkPolicy.random:
        return options[rng.nextInt(options.length)];
      case ForkPolicy.loot:
        return _best(options, lootScore);
      case ForkPolicy.echo:
        // Если Эха не даёт ни один путь, политика вырождается в «лут»:
        // выбирать по нулям одинаково — значит выбирать первый попавшийся.
        final byEcho = _best(options, echoScore);
        return echoScore(byEcho) > 0.0 ? byEcho : _best(options, lootScore);
      case ForkPolicy.safety:
        return _best(options, (m) => -dangerScore(m));
    }
  }

  static FloorModifierDef _best(
      List<FloorModifierDef> options, double Function(FloorModifierDef) score) {
    var best = options.first;
    var bestScore = score(best);
    for (final option in options.skip(1)) {
      final value = score(option);
      if (value > bestScore) {
        bestScore = value;
        best = option;
      }
    }
    return best;
  }

  /// Есть ли развилка на входе на этот этаж.
  static bool isForkFloor(int depth) =>
      Tuning.forkEveryFloors > 0 && depth % Tuning.forkEveryFloors == 0;
}
