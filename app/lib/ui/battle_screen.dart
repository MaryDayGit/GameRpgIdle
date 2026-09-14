import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/sim/combat_feed.dart';
import 'package:rift/core/sim/forecast.dart';

import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/grammar.dart';

import '../game/battle_scene.dart';
import '../game/silhouettes.dart';
import '../data/feedback.dart';
import '../state/descent_replay.dart';
import 'fork_card.dart';
import '../state/game_controller.dart';
import 'format.dart';
import 'strings.dart';
import 'theme.dart';

/// Что происходит в бездне прямо сейчас.
///
/// Не вторая симуляция, а повтор уже посчитанного рана — см. [DescentReplay].
/// Игрок смотрит, но не вмешивается: лоадаут заперт до конца контракта
/// (`docs/03-DECISIONS.md`, раунд 9).
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.controller,
    required this.contract,
  });

  final GameController controller;
  final Contract contract;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with SingleTickerProviderStateMixin implements BattleView {
  late final DescentReplay _replay;
  late final Ticker _ticker;
  late final BattleScene _scene;

  @override
  void initState() {
    super.initState();
    _replay = DescentReplay(contract: widget.contract);
    _scene = BattleScene(this);
    _ticker = createTicker(_onFrame)..start();
    _replay.seekToTime(widget.controller.now);
  }

  @override
  void dispose() {
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  /// Когда в последний раз перестраивался Flutter-слой экрана.
  Duration _lastRebuild = Duration.zero;

  /// Как часто перестраивается всё, кроме арены.
  ///
  /// Арену рисует Flame своим циклом и читает состояние напрямую — ей
  /// `setState` не нужен. А шапка, полоски и лента боя меняются медленнее
  /// кадра: перестраивать их шестьдесят раз в секунду значит тратить кадр на
  /// текст, который не изменился. Именно это и ощущалось как рывки.
  static const _rebuildEvery = Duration(milliseconds: 100);

  /// Этаж на прошлом кадре. По его смене звучит отметка шага вниз.
  int? _lastDepth;

  void _onFrame(Duration elapsed) {
    _replay.seekToTime(widget.controller.now);

    final depth = _replay.snapshot.depth;
    if (_lastDepth != null && depth > _lastDepth!) {
      widget.controller.feedback.play(Sfx.floor);
    }
    _lastDepth = depth;

    if (elapsed - _lastRebuild < _rebuildEvery) return;
    _lastRebuild = elapsed;
    setState(() {});
  }

  // --- BattleView ------------------------------------------------------------

  @override
  double get heroHpFraction => _replay.hero.hpFraction;

  @override
  double get heroManaFraction => _replay.hero.manaFraction;

  @override
  String get heroName => widget.contract.mercenary.name;

  @override
  List<double> get enemyHpFractions => [
        for (final enemy in _replay.enemies)
          enemy.maxHp > 0 ? (enemy.hp / enemy.maxHp).clamp(0.0, 1.0) : 0.0,
      ];

  /// Лента боя: последние события словами.
  ///
  /// Экран наблюдения без неё показывает четыре числа и фигурки — по нему
  /// нельзя понять, ПОЧЕМУ здоровье поехало вниз. Лента отвечает на это
  /// теми же событиями, по которым живёт анимация.
  final List<String> _log = [];

  @override
  List<CombatBeat> takeBeats() {
    final beats = _replay.takeBeats();
    for (final beat in beats) {
      _sound(beat);
      final line = _lineFor(beat);
      if (line != null) _log.insert(0, line);
    }
    if (_log.length > _logLength) _log.removeRange(_logLength, _log.length);
    return beats;
  }

  static const _logLength = 7;

  /// Озвучка идёт по тем же событиям, что и анимация: звук, посчитанный
  /// отдельно, разошёлся бы с картинкой — было бы слышно удар, которого не
  /// видно. Замах молчит: он звучал бы по нескольку раз в секунду, а бьёт
  /// в итоге попадание.
  void _sound(CombatBeat beat) {
    final feedback = widget.controller.feedback;
    switch (beat.kind) {
      case BeatKind.enemyHit:
        // Крит перебивает стихию: он про СИЛУ удара, и слышать его важнее.
        // Иначе самый заметный момент боя звучал бы как обычное попадание,
        // только другого цвета.
        feedback.play(beat.crit ? Sfx.crit : sfxForDamage(beat.type));
      case BeatKind.enemyDied:
        // Босс падает тяжело и победно: его смерть — главное событие волны,
        // и звучать тем же «пух», что падальщик, ей нельзя.
        if (bossWave) {
          feedback.play(Sfx.bossDown, bump: Bump.heavy);
        } else {
          feedback.play(Sfx.kill);
        }
      case BeatKind.heroHurt:
        feedback.play(Sfx.hurt, bump: Bump.light);
      case BeatKind.heroDied:
        feedback.play(Sfx.death, bump: Bump.heavy);
      case BeatKind.heroCast:
        feedback.play(Sfx.cast);
      case BeatKind.waveStarted:
        // Рык — только на боссовой волне: на каждой он был бы метрономом.
        if (bossWave) {
          feedback.play(Sfx.boss, bump: Bump.medium);
        }
      case BeatKind.bossWindup:
        feedback.play(Sfx.boss, bump: Bump.medium);
      case BeatKind.bossSkill:
        feedback.play(Sfx.crit, bump: Bump.heavy);
      case BeatKind.heroSwing:
        break;
    }
  }

  /// Замах и начало волны в ленту не идут: они видны в сцене и вытеснили бы
  /// всё остальное — автоатака случается по несколько раз в секунду.
  String? _lineFor(CombatBeat beat) {
    return switch (beat.kind) {
      // Цель видна в шапке экрана, поэтому в строке только удар: склонять
      // имена мобов («Крит по Владыка Пепла») читается как ошибка.
      BeatKind.enemyHit =>
        beat.crit ? S.critFor(money(beat.amount)) : null,
      // Имя берётся из самой записи, а не из текущего снимка: запись
      // забирается кадром позже, и волны к тому моменту может уже не быть.
      // Согласовано по роду: «Кровавая пиявка» — она, и «пал» про неё
      // читается как ошибка. Род приходит вместе с записью.
      BeatKind.enemyDied => S.battleKilled(beat.name,
          she: beat.gender == Gender.feminine),


      BeatKind.heroCast =>
        S.battleAbility(
            ContentPack.current.ability(beat.id)?.name ?? beat.id),
      // Нулевой урон в ленту не идёт: строка «Получено 0» читается как
      // поломка счёта, а означает лишь округление.
      BeatKind.heroHurt => beat.amount < 0.5
          ? null
          : S.battleTook(money(beat.amount)),
      BeatKind.heroDied => S.battleMercFell,
      BeatKind.bossWindup => S.battleBossWindup(beat.name),
      BeatKind.bossSkill => S.battleBossSkill(beat.name),
      BeatKind.waveStarted || BeatKind.heroSwing => null,
    };
  }

  @override
  List<String> get enemyIds =>
      [for (final enemy in _replay.enemies) enemy.archetype.id];

  /// Оружие берётся из снимка контракта, а не из текущего снаряжения: лоадаут
  /// заперт до гибели, и в бою обязано быть видно то, с чем наёмник ушёл.
  @override
  HeroWeapon get heroWeapon => heroWeaponOf(widget.contract.loadout);

  @override
  String get enemyName => _replay.snapshot.enemyName;

  @override
  bool get bossWave => _replay.snapshot.isBossWave;

  @override
  double get waveProgress => _replay.snapshot.waveProgress;

  /// Отзыв необратим и закрывает ран, поэтому спрашивается прямо. Но и
  /// пугать нечем: наёмник возвращается живым и с добычей.
  Future<void> _confirmRecall() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.recallTitle),
        // Без номера этажа намеренно: спуск идёт, пока диалог открыт, и
        // любое число здесь успевает устареть до нажатия «Отозвать».
        content: Text(S.recallAbout),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.recallLetThemGo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.recall),
          ),
        ],
      ),
    );

    if (agreed != true || !mounted) return;
    widget.controller.recall(widget.contract);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _replay.snapshot;
    final finished = snapshot.finished;

    // Наёмник дошёл до развилки и СТОИТ. Повтор честно замирает вместе с
    // ним — и без этой ветки экран выглядел бы зависшим: полоска перехода на
    // ста процентах, часы не идут, объяснения нет.
    //
    // Вопрос задаётся прямо здесь, а не «вернитесь на Заставу». Наблюдающий
    // за боем — это и есть тот игрок, ради которого развилка спрашивает
    // вживую, и третий путь открыт только ему.
    final atFork = widget.contract.atFork;

    return Scaffold(
      appBar: AppBar(title: Text(heroName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finished && !atFork
                            ? S.battleOver
                            : S.battleFloor(snapshot.depth,
                                boss: !atFork && snapshot.isBossWave),

                        style: RiftText.display.copyWith(
                          fontSize: 24,
                          color: !finished && !atFork && snapshot.isBossWave
                              ? RiftColors.ember
                              : RiftColors.ink,
                        ),
                      ),
                      Text(
                        atFork
                            ? S.battleAtFork
                            : finished
                            ? S.battleWaitsAtOutpost
                            // Переход между этажами занимает время рана.
                            // Пауза, которую нечем объяснить, читается как
                            // зависшая игра — именно это и увидел живой
                            // прогон: «стоит секунд пять и прыгает вперёд».
                            : snapshot.resting
                                ? S.battleResting
                                : '${S.battleWave(snapshot.waveIndex)}'
                                    '/${snapshot.waveCount}'
                                    ' · ${snapshot.enemyName}',
                        style: RiftText.small,
                      ),
                    ],
                  ),
                ),
                // Часы — плашкой: это единственное, что в шапке меняется
                // каждую секунду, и на голом фоне цифры прыгали.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: RiftColors.raised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: RiftColors.line),
                  ),
                  child: Text(
                    clock(snapshot.totalSeconds),
                    style: RiftText.number.copyWith(color: RiftColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          // Арена — полоса с постоянными пропорциями, а не «весь остаток
          // экрана». На высоком телефоне остаток превращался в пустое поле
          // выше бойцов в половину экрана: сцена растягивалась, фигуры — нет.
          Flexible(
            flex: 3,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: GameWidget<BattleScene>(game: _scene),
            ),
          ),
          // Низ прокручивается, а не растёт вниз: полоски, лента боя, прогноз
          // и кнопка отзыва при крупном системном шрифте не помещаются на
          // невысоком экране, и без прокрутки уезжала кнопка — то есть
          // единственное действие, которое здесь вообще есть.
          Flexible(
            flex: 4,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Bar(
                      label: S.battleMercHp,
                      value: heroHpFraction,
                      // Здоровье краснеет по мере убыли: полоска одного цвета
                      // сообщала только длину, а «пора ли отзывать» — это
                      // вопрос о цвете, который видно боковым зрением.
                      color: heroHpFraction > 0.5
                          ? RiftColors.health
                          : heroHpFraction > 0.25
                              ? RiftColors.warn
                              : RiftColors.bad,
                    ),
                    const SizedBox(height: 8),
                    _Bar(
                      label: snapshot.resting
                          ? S.battleRest
                          : S.battleWaveShort,
                      value: snapshot.resting
                          ? snapshot.restProgress
                          : snapshot.waveProgress,
                      color: snapshot.resting
                          ? RiftColors.info
                          : RiftColors.ember,
                    ),
                    const SizedBox(height: 16),
                    _BattleLog(lines: _log),
                    if (atFork) ...[
                      const SizedBox(height: 16),
                      ForkCard(
                        controller: widget.controller,
                        contract: widget.contract,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _confirmRecall,
                        child: Text(S.recallMercenary),
                      ),
                    ] else if (!finished) ...[
                      const SizedBox(height: 16),
                      _Forecast(
                        floors: widget.controller
                            .forecastFrom(widget.contract, snapshot.depth),
                        currentDepth: snapshot.depth,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _confirmRecall,
                        child: Text(S.recallMercenary),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      S.battleWatching,
                      style: const TextStyle(fontSize: 13.5, color: RiftColors.inkFaint),
                      textAlign: TextAlign.center,
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

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Доля, а не 96 точек: «HP наёмника» при крупном системном шрифте
        // шире, и подпись обрезалась бы ровно посередине слова.
        SizedBox(
          width: 104,
          child: Text(label, style: RiftText.small),
        ),
        Expanded(
          child: _GlowBar(value: value.clamp(0.0, 1.0), color: color),
        ),
        SizedBox(
          width: 52,
          child: Text(percent(value),
              textAlign: TextAlign.right,
              style: RiftText.number.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Лента боя. Свежее сверху, старое тает — иначе взгляд ищет, где именно
/// добавилась строка.
class _BattleLog extends StatelessWidget {
  const _BattleLog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox(height: 8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              lines[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: i == 0 ? 14.5 : 13.5,
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.normal,
                // Свежая строка — основным цветом, старые тают к третичному,
                // но не ниже него: лента обязана читаться целиком.
                color: Color.lerp(RiftColors.ink, RiftColors.inkFaint,
                    (i / lines.length).clamp(0.0, 1.0)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Прогноз этажей (GDD §6.2). Глубину обзора даёт Картограф.
///
/// Смысл не в том, чтобы переставить снаряжение — лоадаут заперт до конца
/// контракта. Смысл в одном вопросе: пора ли отзывать. Путь без регена
/// и босс Пустоты впереди — это повод забрать добычу сейчас.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.floors, required this.currentDepth});

  final List<FloorOutlook> floors;

  /// Этаж, на котором наёмник стоит сейчас. Первая строка — про него: она
  /// объясняет, почему прямо сейчас не работает реген.
  final int currentDepth;

  @override
  Widget build(BuildContext context) {
    if (floors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.battlePath(floors.length),
            style: const TextStyle(fontSize: 13.5, color: RiftColors.inkFaint)),
        const SizedBox(height: 6),
        for (final (i, floor) in floors.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${floor.depth}',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: floor.boss == null
                          ? RiftColors.inkFaint
                          : RiftColors.ember,
                      fontWeight: floor.boss == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: Text(
                    floor.depth == currentDepth
                        ? S.battleNow(_describe(floor, i))
                        : _describe(floor, i),
                    style: const TextStyle(fontSize: 13.5,
                        color: RiftColors.ink))),
              ],
            ),
          ),
      ],
    );
  }

  /// Строка одного этажа. [index] нужен, чтобы не повторять на трёх строках
  /// подряд одно и то же описание пути: модификатор держится до следующей
  /// развилки, и в разломе, где он ещё и составной, три одинаковых абзаца
  /// занимали пол-экрана. Повторившийся путь называется по имени.
  String _describe(FloorOutlook floor, int index) {
    final parts = <String>[];

    // Босс и тип его урона — первое, что нужно знать: именно он решает,
    // доживёт ли наёмник до следующей развилки.
    final boss = floor.boss;
    if (boss != null) parts.add('${boss.name} · ${boss.damageType.title}');

    final modifier = floor.modifier;
    if (modifier != null) {
      final same = index > 0 && floors[index - 1].modifier?.id == modifier.id;
      parts.add(floor.forkHere
          ? S.battleForkAhead(modifier.name, modifier.minus)
          : same
              ? modifier.name
              : '${modifier.name}: ${modifier.minus}');
    } else {
      parts.add(S.battleClearPath);
    }

    return parts.join(' · ');
  }
}


/// Полоска боя: толще прежней, со скруглённым краем и свечением заполнения.
///
/// Системная полоска в шесть точек читалась ниткой: на телефоне в руке она
/// сливалась с разделителем, и здоровье приходилось искать. Здесь толщина,
/// дорожка поверхности и отсвет цвета заполнения — длину видно боковым
/// зрением, а цвет сообщает, пора ли вмешиваться.
class _GlowBar extends StatelessWidget {
  const _GlowBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RiftColors.raised,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: RiftColors.line),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(color, Colors.white, 0.25)!,
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
