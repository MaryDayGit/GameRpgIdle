import '../balance/curves.dart';
import '../balance/tuning.dart';
import '../model/enemy.dart';
import '../model/hero.dart';
import 'combat.dart';
import 'combat_feed.dart';
import 'events.dart';
import 'hero_rig.dart';
import 'rng.dart';

/// Чем кончился бой в логове.
class LairFightResult {
  const LairFightResult({
    required this.won,
    required this.seconds,
    required this.hpLeft,
    this.killedBy,
  });

  /// Страж повержен, наёмник жив.
  final bool won;

  /// Игровые секунды боя.
  final double seconds;

  /// Доля здоровья наёмника к концу боя. У поражения — ноль.
  final double hpLeft;

  /// Кто добил наёмника. `null`, если он выжил.
  final String? killedBy;
}

/// Бой со стражем в его логове: один на один, на глубине круга.
///
/// Никакого спуска перед ним нет. Страж — цель, к которой пришли нарочно,
/// зная, кто там стоит (`docs/09-BESTIARY.md`), и решается здесь один вопрос:
/// **чем идти**. Всё, что перед боем, — сборка, которую игрок собрал наверху.
///
/// Бой детерминирован по сиду, как и спуск, поэтому результат известен в
/// момент вызова, а экран может повторить его тик в тик.
class LairFight {
  LairFight._();

  static LairFightResult run({
    required HeroProfile profile,
    required EnemyArchetype guardian,
    required int depth,
    required int seed,
    CombatFeed? feed,
    double? might,
  }) {
    final runner = start(
      profile: profile,
      guardian: guardian,
      depth: depth,
      seed: seed,
      feed: feed,
      might: might,
    );

    // Таймаут волны — тот же предохранитель, что и в спуске: страж, которого
    // не убить за час, для игрока неотличим от стены.
    final ticks = (Tuning.waveTimeoutSeconds / Tuning.tickSeconds).ceil() + 1;
    for (var i = 0; i < ticks && !runner.finished; i++) {
      runner.tick();
    }

    final outcome = runner.outcome;
    final won = outcome.heroAlive && !outcome.timedOut;
    return LairFightResult(
      won: won,
      seconds: outcome.seconds,
      hpLeft: won ? runner.hero.hpFraction : 0.0,
      killedBy: outcome.killer?.name,
    );
  }

  /// Бой, готовый к пошаговому проигрыванию. Наружу — ради экрана, который
  /// обязан показать ТОТ бой, чей исход уже записан.
  /// [might] — множитель здоровья и урона стража поверх выверенного аудитом.
  /// По умолчанию из контента; явное число нужно только замеру, который его
  /// подбирает (`sim_cli --lair-probe`).
  static WaveRunner start({
    required HeroProfile profile,
    required EnemyArchetype guardian,
    required int depth,
    required int seed,
    CombatFeed? feed,
    double? might,
  }) {
    final power = might ?? Curves.lairGuardianMight;
    final bus = EventBus();
    final rig = HeroRig.of(profile, bus);

    return WaveRunner(
      bus: bus,
      depth: depth,
      hero: rig.hero,
      // Здоровье — по кривой вещей от глубины аудита (`Curves.lairHpScale`):
      // иначе глубокий страж умирает раньше, чем успевает ударить.
      //
      // «Рог охоты» делает крепче всех, кого встретит наёмник: страж —
      // не исключение, иначе реликт бесплатен ровно там, где его плата
      // ощущается сильнее всего.
      enemies: [
        EnemyInstance.spawn(guardian, depth,
            hpMultiplier: Curves.lairHpScale(depth) *
                power *
                (1.0 + rig.rules.mobHpBonus),
            dpsMultiplier: power),
      ],
      rng: Rng.stream(seed, depth, 0, RngPurpose.lair),
      abilities: rig.abilities,
      triggers: rig.triggers,
      rules: rig.rules,
      passives: rig.passives,
      feed: feed,
    );
  }
}
