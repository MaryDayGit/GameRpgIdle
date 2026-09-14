import 'package:flutter/material.dart';
import 'package:rift/core/model/mercenary.dart';

import '../state/game_controller.dart';
import 'coach_mark.dart';
import 'onboarding.dart';
import 'strings.dart';

/// Обучение поверх одного экрана.
///
/// Экран оборачивает себя этим виджетом и расставляет [TutorialAnchor] — всё.
/// Ни один экран не знает, какой сейчас шаг, чему он учит и когда кончится:
/// это знает [Onboarding], и знает в одном месте.
///
/// Шаг-задание закрывается не кнопкой, а тем, что игрок его выполнил. Виджет
/// помнит, какое задание показывает, и как только оно перестаёт быть к месту
/// — наёмник отправлен, вещь надета, путь выбран — записывает шаг пройденным.
/// Кнопки «Дальше» у задания нет нарочно: обучение, которое проходится
/// нажатием «Дальше», учит только нажимать «Дальше».
class TutorialHost extends StatefulWidget {
  const TutorialHost({
    super.key,
    required this.controller,
    required this.screen,
    required this.child,
    this.mercenary,
  });

  final GameController controller;
  final TutorialScreen screen;
  final Widget child;

  /// Наёмник открытого экрана Сборки: шаги про слоты спрашивают про него, а
  /// не про первого попавшегося в резерве.
  final Mercenary? mercenary;

  @override
  State<TutorialHost> createState() => _TutorialHostState();
}

class _TutorialHostState extends State<TutorialHost> {
  /// Показываемое сейчас задание. `null` — задания нет либо шаг объясняющий.
  String? _task;

  /// Метка задания, которое закрывается нажатием, а не состоянием игры.
  String? _tapTarget;

  @override
  void initState() {
    super.initState();
    TutorialAnchor.tapped.addListener(_onAnchorTap);
  }

  @override
  void dispose() {
    TutorialAnchor.tapped.removeListener(_onAnchorTap);
    super.dispose();
  }

  /// Нажали по подсвеченному месту — задание закрыто.
  void _onAnchorTap() {
    final target = _tapTarget;
    if (target == null || TutorialAnchor.tapped.value != target) return;
    final id = _task;
    if (id == null) return;

    _task = null;
    _tapTarget = null;
    _later(() {
      widget.controller.markTutorialSeen([id]);
      // Сбрасываем, иначе следующее нажатие по той же метке не заметит:
      // `ValueNotifier` молчит, когда значение не изменилось.
      TutorialAnchor.tapped.value = null;
    });
  }

  void _later(VoidCallback action) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    // Обучение пройдено или пропущено — виджета как будто нет. То же и до
    // вступления: пока игрок не дочитал, чем эта игра является, указывать
    // ему на кнопки бессмысленно.
    if (c.settings.tutorialDone || Onboarding.needsIntro(c.tutorialSeen)) {
      _task = null;
      _tapTarget = null;
      return widget.child;
    }

    final facts = TutorialFacts(
      profile: c.profile,
      now: c.now,
      mercenary: widget.mercenary,
    );

    // Задание, которое показывали, больше не к месту — значит, игрок его
    // сделал. Записывается после кадра: менять состояние игры посреди
    // построения дерева нельзя.
    final task = _task;
    if (task != null &&
        _tapTarget == null &&
        !Onboarding.isReady(task, facts)) {
      _task = null;
      _later(() => c.markTutorialSeen([task]));
    }

    final pick = Onboarding.pick(
      facts: facts,
      seen: c.tutorialSeen,
      screen: widget.screen,
    );

    // Шаги, которые опоздали: игрок сделал всё сам и ушёл вперёд. Гасим
    // молча, иначе они всплывут через десяток спусков.
    if (pick.retire.isNotEmpty) {
      _later(() => c.markTutorialSeen(pick.retire));
    }

    final beat = pick.beat;
    if (beat == null) {
      _task = null;
      _tapTarget = null;
      return widget.child;
    }

    _task = beat.isTask ? beat.id : null;
    _tapTarget = beat.isTask && beat.byTap ? beat.anchor : null;

    // Поверх экрана открыто что-то ещё — окно с наградой за задание, лист
    // выбора вещи, вопрос системы. Подсказку в это время не рисуем: на
    // телефоне «Заданий выполнено: 4» встало ровно поверх карточки «Сундук
    // открыт», и обе просили внимания одновременно.
    //
    // Считать шаг закрытым при этом нельзя — учёт выше идёт своим чередом, и
    // задание, выполненное из-под чужого окна, всё равно засчитается.
    if (ModalRoute.of(context)?.isCurrent == false) return widget.child;

    return TutorialLayer(
      mark: CoachMark(
        id: beat.id,
        title: beat.title,
        text: beat.text,
        anchor: beat.anchor,
        hint: beat.hint,
        step: Onboarding.numberOf(beat.id),
        total: Onboarding.total,
        // У задания кнопки нет: его закрывает действие.
        onNext: beat.isTask
            ? null
            : () {
                c.markTutorialSeen([beat.id]);
                // Последний шаг — он же конец обучения: дальше игра молчит,
                // а разделы, которые открывались по ходу, открыты все.
                if (beat.id == 'finale') c.finishTutorial();
              },
        onSkip: () => c.finishTutorial(skipped: true),
        // Указывать оказалось не на что — шаг закрывается кнопкой, а игрок
        // не остаётся запертым под затемнением.
        onLost: () => c.markTutorialSeen([beat.id]),
      ),
      child: widget.child,
    );
  }
}

/// Строка настроек: пройти обучение заново.
///
/// Есть ровно потому, что обучение пропускается одной кнопкой. Пропустить
/// по ошибке легко, а вернуть без этой строки нельзя ничем, кроме сноса игры.
class TutorialRestartTile extends StatelessWidget {
  const TutorialRestartTile({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final running = !controller.settings.tutorialDone;

    return ListTile(
      title: Text(S.settingsTutorial),
      subtitle: Text(running ? S.settingsTutorialRunning : S.settingsTutorialAbout),
      trailing: running
          ? null
          : TextButton(
              onPressed: controller.restartTutorial,
              child: Text(S.settingsTutorialRestart),
            ),
    );
  }
}
