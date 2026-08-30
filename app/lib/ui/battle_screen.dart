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

  void _onFrame(Duration elapsed) {
    _replay.seekToTime(widget.controller.now);

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
        feedback.play(beat.crit ? Sfx.crit : Sfx.hit);
      case BeatKind.enemyDied:
        feedback.play(Sfx.kill);
      case BeatKind.heroHurt:
        feedback.play(Sfx.hurt, bump: Bump.light);
      case BeatKind.heroDied:
        feedback.play(Sfx.death, bump: Bump.heavy);
      case BeatKind.waveStarted:
      case BeatKind.heroSwing:
      case BeatKind.heroCast:
        break;
    }
  }

  /// Замах и начало волны в ленту не идут: они видны в сцене и вытеснили бы
  /// всё остальное — автоатака случается по несколько раз в секунду.
  String? _lineFor(CombatBeat beat) {
    return switch (beat.kind) {
      // Цель видна в шапке экрана, поэтому в строке только удар: склонять
      // имена мобов («Крит по Владыка Пепла») читается как ошибка.
      BeatKind.enemyHit => beat.crit ? 'Крит · ${money(beat.amount)}' : null,
      // Имя берётся из самой записи, а не из текущего снимка: запись
      // забирается кадром позже, и волны к тому моменту может уже не быть.
      // Согласовано по роду: «Кровавая пиявка» — она, и «пал» про неё
      // читается как ошибка. Род приходит вместе с записью.
      BeatKind.enemyDied => beat.gender == Gender.feminine
          ? '«${beat.name}» повержена'
          : '«${beat.name}» повержен',
      BeatKind.heroCast =>
        'Умение: ${ContentPack.current.ability(beat.id)?.name ?? beat.id}',
      // Нулевой урон в ленту не идёт: строка «Получено 0» читается как
      // поломка счёта, а означает лишь округление.
      BeatKind.heroHurt => beat.amount < 0.5
          ? null
          : 'Получено ${money(beat.amount)}',
      BeatKind.heroDied => 'Наёмник погиб',
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
        title: const Text('Отозвать наёмника?'),
        // Без номера этажа намеренно: спуск идёт, пока диалог открыт, и
        // любое число здесь успевает устареть до нажатия «Отозвать».
        content: const Text(
          'Спуск закончится там, где наёмник сейчас. Добыча и Эхо остаются '
          'при нём — штрафа за отзыв нет.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Пусть идёт дальше'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отозвать'),
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
                            ? 'Спуск окончен'
                            : 'Этаж ${snapshot.depth}'
                                '${!atFork && snapshot.isBossWave ? " · БОСС" : ""}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        atFork
                            ? 'Развилка · наёмник ждёт решения'
                            : finished
                            ? 'Наёмник ждёт вас на Заставе'
                            // Переход между этажами занимает время рана.
                            // Пауза, которую нечем объяснить, читается как
                            // зависшая игра — именно это и увидел живой
                            // прогон: «стоит секунд пять и прыгает вперёд».
                            : snapshot.resting
                                ? 'Переход · наёмник переводит дух'
                                : 'Волна ${snapshot.waveIndex}'
                                    '/${snapshot.waveCount}'
                                    ' · ${snapshot.enemyName}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Text(
                  clock(snapshot.totalSeconds),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white54,
                    fontFeatures: [FontFeature.tabularFigures()],
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
                      label: 'HP наёмника',
                      value: heroHpFraction,
                      color: const Color(0xFF7FB069),
                    ),
                    const SizedBox(height: 8),
                    _Bar(
                      label: snapshot.resting ? 'Переход' : 'Волна',
                      value: snapshot.resting
                          ? snapshot.restProgress
                          : snapshot.waveProgress,
                      color: snapshot.resting
                          ? const Color(0xFF5E7E92)
                          : const Color(0xFFC7643F),
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
                        child: const Text('Отозвать наёмника'),
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
                        child: const Text('Отозвать наёмника'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Вы наблюдаете. Сборка заперта до конца контракта.',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
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
          width: 96,
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(percent(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
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
                fontSize: 12,
                color: Colors.white.withValues(
                    alpha: (1.0 - i / lines.length).clamp(0.25, 0.85)),
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
        Text('Путь · ${plural(floors.length, "этаж", "этажа", "этажей")}',
            style: const TextStyle(fontSize: 12, color: Colors.white38)),
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
                      fontSize: 12,
                      color: floor.boss == null
                          ? Colors.white38
                          : const Color(0xFFC7643F),
                      fontWeight: floor.boss == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: Text(
                    floor.depth == currentDepth
                        ? 'сейчас · ${_describe(floor, i)}'
                        : _describe(floor, i),
                    style: const TextStyle(fontSize: 12,
                        color: Colors.white70))),
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
    if (boss != null) parts.add('${boss.name} · ${boss.damageType.ru}');

    final modifier = floor.modifier;
    if (modifier != null) {
      final same = index > 0 && floors[index - 1].modifier?.id == modifier.id;
      parts.add(floor.forkHere
          ? 'Развилка → ${modifier.name}: ${modifier.minus}'
          : same
              ? modifier.name
              : '${modifier.name}: ${modifier.minus}');
    } else {
      parts.add('Ровный путь');
    }

    return parts.join(' · ');
  }
}
