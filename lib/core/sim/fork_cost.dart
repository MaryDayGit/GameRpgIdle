import '../content/ability_def.dart';
import '../content/floor_modifier_def.dart';
import '../model/stat_block.dart';

/// Во что обойдётся путь ИМЕННО ЭТОЙ сборке.
///
/// Развилка предлагает размен, но одна и та же плата стоит разным сборкам
/// разного. «−30 сопротивления огню» — тяжёлый минус тому, кто набрал 60
/// сопротивления, и ровно ноль тому, у кого его нет вовсе. «Перезарядки
/// +25 %» ничего не значат для сборки на автоатаке.
///
/// Без этого третий путь («оба сразу») — слепая монетка. Замер показал, что
/// «всегда смело» проигрывает по глубине, а «смело, пока цел» не помогает:
/// здоровье прошлого этажа плохой советчик, потому что между этажами наёмник
/// отдыхает. Настоящий вопрос не «сколько у него HP», а «бьёт ли эта плата по
/// тому, на чём стоит сборка», — и ответить на него может только игрок,
/// который видит и то, и другое.
///
/// Это и есть награда за присутствие: не лишний множитель, а знание.
class ForkCost {
  const ForkCost._(this.text, this.harmless);

  /// Короткая строка для экрана. `null` — сказать нечего.
  final String? text;

  /// Плата этой сборке почти ничего не стоит.
  final bool harmless;

  static const _nothing = ForkCost._(null, false);

  /// Разбирает плату модификатора против сборки.
  ///
  /// [stats] — собранный блок наёмника, [loadout] — его умения. Оба нужны:
  /// сопротивления живут в статах, а «есть ли у него вообще активки» — в
  /// лоадауте, и по одному другому не восстановить.
  static ForkCost of(
    FloorModifierDef modifier,
    StatBlock stats,
    List<AbilityDef> loadout,
  ) {
    final free = <String>[];
    var hasCost = false;

    void check(bool matters, String freeText) {
      if (matters) {
        hasCost = true;
      } else {
        free.add(freeText);
      }
    }

    // Сопротивления: терять нечего тому, у кого их нет. Порог не нулевой —
    // пять пунктов сопротивления это шум, а не защита.
    for (final (effect, current, name) in [
      (FloorEffect.resistFire, stats.resistFire, 'огню'),
      (FloorEffect.resistCold, stats.resistCold, 'холоду'),
      (FloorEffect.resistVoid, stats.resistVoid, 'пустоте'),
    ]) {
      if (modifier.value(effect) >= 0.0) continue;
      check(current > 5.0, 'сопротивления $name у вас и так нет');
    }

    if (modifier.disablesRegen) {
      check(stats.hpRegen > 0.5, 'восстановления HP у вас и так нет');
    }

    if (modifier.disablesAuras) {
      final has = loadout.any((d) =>
          d.isAura || d.kind == AbilityKind.summonTotem);
      check(has, 'аур и тотемов у вас нет');
    }

    if (modifier.value(FloorEffect.cooldownReduction) < 0.0) {
      check(loadout.any((d) => d.isActive), 'активных умений у вас нет');
    }

    // Плата, которую нечем отменить: она бьёт по любой сборке.
    //
    // Без этой проверки разбор ВРАЛ. Он смотрел только на то, что умел
    // отменять, и молчал про удвоенный урон мобов и лишние волны — а потом
    // писал «эта плата вам почти ничего не стоит». Замер поймал: сорок семь
    // процентов развилок объявлялись бесплатными, и присутствующий игрок,
    // веривший экрану, проигрывал отсутствующему.
    const unavoidable = {
      FloorEffect.mobHp,
      FloorEffect.mobDps,
      FloorEffect.waveMultiplier,
      FloorEffect.packMultiplier,
    };
    for (final effect in unavoidable) {
      final v = modifier.value(effect);
      // Множители: плата — всё, что БОЛЬШЕ единицы. Доли: всё, что больше нуля.
      final threshold = effect == FloorEffect.waveMultiplier ||
              effect == FloorEffect.packMultiplier
          ? 1.0
          : 0.0;
      if (v > threshold) hasCost = true;
    }

    // Путь без платы разбирать нечего: его собственная строка минуса уже
    // говорит «платы нет», и второе такое же предложение под ней — это не
    // объяснение, а шум.
    if (modifier.penalties.isEmpty) return _nothing;

    if (free.isEmpty) return _nothing;

    // «Почти ничего не стоит» — только если ВСЯ плата мимо. Один бесплатный
    // минус из двух — это по-прежнему плата, и подсвечивать её зелёным
    // значило бы уговаривать игрока.
    return ForkCost._(
      '${free.first[0].toUpperCase()}${free.first.substring(1)}'
      '${free.length > 1 ? ', ${free.skip(1).join(', ')}' : ''}.',
      !hasCost,
    );
  }
}
