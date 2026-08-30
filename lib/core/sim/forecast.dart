import '../content/floor_modifier_def.dart';
import '../model/enemy.dart';
import 'fork.dart';

/// Что известно про один этаж заранее.
class FloorOutlook {
  const FloorOutlook({
    required this.depth,
    required this.modifier,
    required this.forkHere,
    required this.options,
    required this.boss,
  });

  final int depth;

  /// Модификатор, который будет действовать на этом этаже. Держится с
  /// последней развилки — путь, а не этаж (`docs/03-DECISIONS.md`, раунд 6).
  final FloorModifierDef? modifier;

  /// На этом этаже развилка: путь сменится.
  final bool forkHere;

  /// Оба варианта развилки. Пусто, если развилки здесь нет.
  final List<FloorModifierDef> options;

  /// Босс этажа, если он тут есть.
  final EnemyArchetype? boss;
}

/// Прогноз этажей (GDD §6.2, постройка «Картограф»).
///
/// Считается, а не симулируется: развилка детерминирована по сиду рана и
/// глубине, босс — по одной только глубине. Значит будущее известно, не трогая
/// боевую модель, и прогноз не может разойтись с тем, что случится.
///
/// **Зачем он нужен, если лоадаут заперт.** В GDD прогноз — повод переставить
/// сопротивления перед этажом; у нас снаряжение заперто с момента отправки
/// (раунд 9), и переставлять нечего. Прогноз отвечает на другой вопрос —
/// «пора ли отзывать»: наёмник жив, впереди путь без регена и босс Пустоты,
/// и решение забрать добычу сейчас становится осмысленным, а не случайным.
class Forecast {
  Forecast._();

  /// [rift] — модификатор разлома дня, если спуск идёт в разлом. Он действует
  /// на КАЖДОМ этаже и складывается с выбранным путём — ровно так же, как в
  /// самом спуске. Без него прогноз врал бы дважды: обещал бы «ровный путь»
  /// там, где ровных путей в разломе нет, и называл бы одну половину пары.
  ///
  /// [choices] — решения игрока на развилках по порядку, как их хранит
  /// контракт, а [startDepth] — этаж, с которого начался спуск: по этой паре
  /// восстанавливается номер развилки, ровно как в `DescentDriver`. Прогноз
  /// обязан читать решения по той же причине: путь держится с последней
  /// развилки, и если игрок выбрал третий путь, показывать выбор приказа
  /// значит описывать спуск, которого нет.
  static List<FloorOutlook> ahead({
    required int seed,
    required int fromDepth,
    required int floors,
    required ForkPolicy policy,
    FloorModifierDef? rift,
    List<int> choices = const [],
    int startDepth = 1,
  }) {
    if (floors <= 0) return const [];

    final out = <FloorOutlook>[];
    for (var i = 0; i < floors; i++) {
      final depth = fromDepth + i;
      if (depth < 1) continue;

      final forkHere = ForkChooser.isForkFloor(depth);
      final active = _activeFork(
        seed: seed,
        depth: depth,
        policy: policy,
        choices: choices,
        startDepth: startDepth,
      );

      out.add(FloorOutlook(
        depth: depth,
        modifier: _merge(active?.chosen, rift),
        forkHere: forkHere,
        options: forkHere
            ? [for (final o in active?.options ?? const []) _merge(o, rift)!]
            : const [],
        boss: Bestiary.bossFor(depth),
      ));
    }
    return out;
  }

  /// Путь этажа и разлом дня вместе. Повторяет `DescentDriver._rollFork`:
  /// разлом складывается с выбранным путём, а не заменяет его.
  static FloorModifierDef? _merge(
      FloorModifierDef? path, FloorModifierDef? rift) {
    if (rift == null) return path;
    if (path == null) return rift;
    return FloorModifierDef.combine(path, rift);
  }

  /// Развилка, действующая на этом этаже: последняя, что была на нём или до
  /// него. Первые этажи до первой развилки идут вообще без модификатора —
  /// и это правда, а не пробел в прогнозе.
  static Fork? _activeFork({
    required int seed,
    required int depth,
    required ForkPolicy policy,
    required List<int> choices,
    required int startDepth,
  }) {
    for (var d = depth; d >= 1; d--) {
      if (ForkChooser.isForkFloor(d)) {
        return ForkChooser.roll(seed, d, policy,
            chosen: _choiceAt(d, startDepth: startDepth, choices: choices));
      }
    }
    return null;
  }

  /// Решение игрока на развилке этажа [depth], если оно было.
  ///
  /// Решения лежат списком по порядку развилок, а не по этажам: так их хранит
  /// контракт и так их читает спуск (`DescentDriver._rollFork`). Номер
  /// развилки считается от этажа, с которого начался спуск, — «верёвка»
  /// Заставы опускает наёмника глубже первого этажа, и счёт от единицы дал бы
  /// сдвиг ровно на число пропущенных развилок.
  static int? _choiceAt(int depth,
      {required int startDepth, required List<int> choices}) {
    if (choices.isEmpty || depth < startDepth) return null;

    var ordinal = 0;
    for (var d = startDepth; d < depth; d++) {
      if (ForkChooser.isForkFloor(d)) ordinal++;
    }
    return ordinal < choices.length ? choices[ordinal] : null;
  }
}
