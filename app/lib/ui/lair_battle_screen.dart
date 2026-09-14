import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/model/relic_effect.dart';
import 'package:rift/core/model/tags.dart';
import 'package:rift/core/sim/combat.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/lair.dart';

import '../data/feedback.dart';
import '../game/battle_scene.dart';
import '../game/silhouettes.dart';
import '../state/game_controller.dart';
import 'format.dart';
import 'strings.dart';
import 'theme.dart';

/// Слабость стража словами: стихии, к которым он уязвим, и Проводники,
/// которые их дают. `null` — слабостей нет.
///
/// Показывается и на карточке до вызова, и в окне поражения: «чем идти» — это
/// вопрос, ответ на который игрок обязан знать ДО того, как заплатит жизнью.
/// Числа сопротивлений не показываются — достаточно направления.
String? weaknessHint(EnemyArchetype guardian) {
  final weak = [
    for (final type in DamageType.values)
      if (guardian.resistFor(type) < 0.0) type,
  ]..sort((a, b) => guardian.resistFor(a).compareTo(guardian.resistFor(b)));
  if (weak.isEmpty) return null;

  final conduits = [
    for (final def in ContentPack.current.relics)
      if (def.effect == RelicEffect.elementalConduit &&
          weak.any((t) => t.name == def.params.str('element')))
        def.name,
  ];
  return S.lairWeakness(
    weak.map((t) => t.title).join(', '),
    conduits.join(', '),
  );
}

/// Бой со стражем на глазах у игрока.
///
/// Не вторая симуляция, а повтор уже посчитанного боя: тот же снимок героя,
/// тот же сид (`LairChallenge`). Исход записан в момент вызова, и экран
/// обязан показать ровно его — бой, который на экране выигран, а в профиле
/// проигран, это худшее, что может случиться с логовом.
class LairBattleScreen extends StatefulWidget {
  const LairBattleScreen({
    super.key,
    required this.controller,
    required this.challenge,
  });

  final GameController controller;
  final LairChallenge challenge;

  @override
  State<LairBattleScreen> createState() => _LairBattleScreenState();
}

class _LairBattleScreenState extends State<LairBattleScreen>
    with SingleTickerProviderStateMixin
    implements BattleView {
  final CombatFeed _feed = CombatFeed();
  late final WaveRunner _runner;
  late final Ticker _ticker;
  late final BattleScene _scene;

  Duration _last = Duration.zero;
  double _carry = 0.0;
  double _speed = 1.0;
  bool _outcomeShown = false;

  final List<String> _log = [];
  static const _logLength = 6;

  LairChallenge get _c => widget.challenge;

  @override
  void initState() {
    super.initState();
    _runner = LairFight.start(
      profile: _c.profile,
      guardian: _c.guardian,
      depth: _c.depth,
      seed: _c.seed,
      feed: _feed,
    );
    _scene = BattleScene(this);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onFrame(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _last = elapsed;
    if (_runner.finished) return;

    _carry += dt * _speed;
    while (_carry >= Tuning.tickSeconds && !_runner.finished) {
      _carry -= Tuning.tickSeconds;
      _runner.tick();
    }
    if (mounted) setState(() {});
    if (_runner.finished) _finish();
  }

  /// Досчитывает бой до конца без показа: игрок, который знает, чем кончится,
  /// не обязан смотреть минуту.
  void _skip() {
    var guard = 0;
    while (!_runner.finished && ++guard < 100000) {
      _runner.tick();
    }
    _feed.clear();
    setState(() {});
    _finish();
  }

  void _finish() {
    if (_outcomeShown) return;
    _outcomeShown = true;
    // Кадром позже: диалог, открытый изнутри тикера посреди сборки кадра,
    // Flutter не пропускает.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LairOutcomeDialog(challenge: _c),
      );
      if (mounted) Navigator.of(context).pop();
    });
  }

  // --- BattleView ------------------------------------------------------------

  @override
  double get heroHpFraction => _runner.hero.hpFraction.clamp(0.0, 1.0);

  @override
  double get heroManaFraction => _runner.hero.manaFraction.clamp(0.0, 1.0);

  @override
  String get heroName => _c.mercenary.name;

  @override
  HeroWeapon get heroWeapon => heroWeaponOf(_c.profile.gear);

  @override
  List<double> get enemyHpFractions => [
        for (final e in _runner.enemies)
          e.maxHp > 0 ? (e.hp / e.maxHp).clamp(0.0, 1.0) : 0.0,
      ];

  /// Фигура — босса, которого страж воплощает: это один и тот же он, и
  /// игрок, видевший Владыку Пепла в бездне, обязан узнать его в логове.
  @override
  List<String> get enemyIds => [
        for (final e in _runner.enemies) e.archetype.embodies ?? e.archetype.id,
      ];

  @override
  String get enemyName => _c.guardian.name;

  @override
  bool get bossWave => true;

  @override
  double get waveProgress => _runner.waveProgress;

  @override
  List<CombatBeat> takeBeats() {
    final beats = _feed.drain();
    final feedback = widget.controller.feedback;
    for (final beat in beats) {
      switch (beat.kind) {
        case BeatKind.enemyHit:
          feedback.play(beat.crit ? Sfx.crit : sfxForDamage(beat.type));
        case BeatKind.enemyDied:
          feedback.play(Sfx.bossDown, bump: Bump.heavy);
        case BeatKind.heroHurt:
          feedback.play(Sfx.hurt, bump: Bump.light);
        case BeatKind.heroDied:
          feedback.play(Sfx.death, bump: Bump.heavy);
        case BeatKind.heroCast:
          feedback.play(Sfx.cast);
        case BeatKind.bossWindup:
          feedback.play(Sfx.boss, bump: Bump.medium);
          _logLine(S.battleBossWindup(beat.name));
        case BeatKind.bossSkill:
          feedback.play(Sfx.crit, bump: Bump.heavy);
          _logLine(S.battleBossSkill(beat.name));
        case BeatKind.waveStarted:
          feedback.play(Sfx.boss, bump: Bump.medium);
        case BeatKind.heroSwing:
          break;
      }
      if (beat.kind == BeatKind.heroCast) {
        _logLine(S.battleAbility(
            ContentPack.current.ability(beat.id)?.name ?? beat.id));
      } else if (beat.kind == BeatKind.heroHurt && beat.amount >= 0.5) {
        _logLine(S.battleTook(money(beat.amount)));
      }
    }
    return beats;
  }

  void _logLine(String line) {
    _log.insert(0, line);
    if (_log.length > _logLength) _log.removeRange(_logLength, _log.length);
  }

  @override
  Widget build(BuildContext context) {
    final guardian = _runner.enemies.isEmpty ? null : _runner.enemies.first;
    final preparing = guardian?.windingUp;

    final heroStates = [
      if (_runner.heroStunned) S.lairStunned,
      if (_runner.heroSilenced) S.lairSilenced,
      if (_runner.heroExposed) S.lairExposed,
      if (_runner.heroBurning) S.lairBurning,
    ];
    final guardianStates = [
      if (guardian != null && guardian.shielded) S.lairShielded,
      if (guardian != null && guardian.enraged) S.lairEnraged,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_c.guardian.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.lairFightTitle(_c.circle),
                          style: RiftText.display.copyWith(
                              fontSize: 22, color: RiftColors.ember)),
                      Text(
                        preparing != null
                            ? S.lairPreparing(preparing.name)
                            : _c.guardian.role,
                        style: RiftText.small.copyWith(
                          color: preparing != null
                              ? RiftColors.warn
                              : RiftColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: RiftColors.raised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: RiftColors.line),
                  ),
                  child: Text(clock(_runner.seconds),
                      style:
                          RiftText.number.copyWith(color: RiftColors.inkMuted)),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 3,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: GameWidget<BattleScene>(game: _scene),
            ),
          ),
          Flexible(
            flex: 4,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Meter(
                      label: _c.mercenary.name,
                      value: heroHpFraction,
                      color: heroHpFraction > 0.5
                          ? RiftColors.health
                          : heroHpFraction > 0.25
                              ? RiftColors.warn
                              : RiftColors.bad,
                      states: heroStates,
                    ),
                    const SizedBox(height: 8),
                    _Meter(
                      label: S.lairGuardianHp,
                      value: enemyHpFractions.isEmpty
                          ? 0.0
                          : enemyHpFractions.first,
                      color: RiftColors.bad,
                      states: guardianStates,
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < _log.length; i++)
                      Text(
                        _log[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: i == 0 ? 14.5 : 13.5,
                          fontWeight:
                              i == 0 ? FontWeight.w600 : FontWeight.normal,
                          color: Color.lerp(RiftColors.ink, RiftColors.inkFaint,
                              (i / _log.length).clamp(0.0, 1.0)),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<double>(
                            segments: const [
                              ButtonSegment(value: 1.0, label: Text('×1')),
                              ButtonSegment(value: 2.0, label: Text('×2')),
                              ButtonSegment(value: 4.0, label: Text('×4')),
                            ],
                            selected: {_speed},
                            onSelectionChanged: (v) =>
                                setState(() => _speed = v.first),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          key: const Key('lair-skip'),
                          onPressed: _runner.finished ? null : _skip,
                          child: Text(S.lairSkip),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоска здоровья с состояниями бойца под ней.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.color,
    required this.states,
  });

  final String label;
  final double value;
  final Color color;
  final List<String> states;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: RiftText.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(percent(value),
                style: RiftText.number.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 12,
            color: color,
            backgroundColor: RiftColors.raised,
          ),
        ),
        if (states.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in states)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: RiftColors.warn.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: RiftColors.warn.withValues(alpha: 0.6)),
                    ),
                    child: Text(s,
                        style: const TextStyle(
                            fontSize: 12.5, color: RiftColors.warn)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Исход боя со стражем. Окном, а не строкой: взятый круг — событие, ради
/// которого логово и существует, а гибель наёмника — цена, о которой нельзя
/// промолчать.
class LairOutcomeDialog extends StatelessWidget {
  const LairOutcomeDialog({super.key, required this.challenge});

  final LairChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final fight = challenge.fight;
    final relic = challenge.relic;
    final relicName = relic?.relicId == null
        ? null
        : ContentPack.current.relic(relic!.relicId!)?.name;

    return AlertDialog(
      title: Text(
        fight.won
            ? (challenge.firstWin
                ? S.lairWon(challenge.guardian.name, challenge.circle)
                : S.lairWonAgain(challenge.guardian.name, challenge.circle))
            : S.lairLost(challenge.mercenary.name),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fight.won)
            Text(S.lairHpLeft((fight.hpLeft * 100).round()),
                style: RiftText.body),
          if (challenge.passivePoints > 0)
            Text(S.lairPassivePoints(challenge.passivePoints),
                style: const TextStyle(color: RiftColors.good)),
          if (relicName != null)
            Text(S.lairRelic(relicName),
                style: const TextStyle(color: RiftColors.gold)),
          // Поражение — цена и подсказка. Окно, в котором написано только
          // «не вернулся», не говорит ни сколько это стоило, ни что делать
          // иначе, и следующий вызов оказывается той же ошибкой.
          if (!fight.won) ...[
            Text(S.lairOfferingLost(money(challenge.offering)),
                style: const TextStyle(color: RiftColors.bad)),
            const SizedBox(height: 8),
            if (weaknessHint(challenge.guardian) case final hint?) ...[
              Text(hint, style: const TextStyle(color: RiftColors.warn)),
              const SizedBox(height: 4),
              Text(S.lairLossHint, style: RiftText.small),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('lair-outcome-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
