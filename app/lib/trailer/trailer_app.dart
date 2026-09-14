import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rift/core/model/lang.dart';

import '../data/content.dart';
import '../data/feedback.dart';
import '../data/save_store.dart';
import '../data/settings_store.dart';
import '../state/game_controller.dart';
import '../ui/outpost_screen.dart';
import 'demo_profile.dart';
import 'trailer_director.dart';
import 'trailer_script.dart';
import '../ui/theme.dart';

/// Приложение трейлера: живая игра под камерой.
///
/// Отдельно от точки входа, потому что точка входа умеет то, чего нет в
/// тесте: полноэкранный режим, ориентацию и каталог документов телефона.
/// Здесь остаётся только то, что можно прогнать целиком на машине без
/// телефона, — и оно прогоняется (`test/trailer_test.dart`).

class TrailerApp extends StatefulWidget {
  const TrailerApp({
    super.key,
    required this.content,
    required this.store,
    this.lang = Lang.ru,
    this.sound = false,
    this.onPass,
  });

  final ContentBundle content;
  final SaveStore store;

  /// Язык ролика. Подписи сценария двуязычные, игра переводится целиком, —
  /// английский дубль снимается сменой одного значения, а не правкой кадров.
  final Lang lang;

  /// Звук игры в записи.
  ///
  /// По умолчанию выключен: в монтаж всё равно ляжет своя музыка, а звук с
  /// динамика телефона попадает в дубль грязным. Включается, когда нужны
  /// настоящие удары, — их потом кладут отдельной дорожкой.
  final bool sound;

  /// Круг пройден. Нужно тесту, чтобы знать, что показ дошёл до конца, а не
  /// встал посередине.
  final VoidCallback? onPass;

  @override
  State<TrailerApp> createState() => _TrailerAppState();
}

class _TrailerAppState extends State<TrailerApp> {
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

  /// Номер дубля. Меняется на каждом круге и перезаводит всё дерево: игра
  /// после круга уже прожита — наёмник погиб, добыча разобрана, — и второй
  /// круг по ней показал бы не то же самое.
  int _take = 0;

  late GameController _controller;
  late TrailerStage _stage;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _boot() {
    final clock = TrailerClock(DateTime.utc(2026, 9, 7, 20));
    _controller = GameController(
      content: widget.content,
      store: widget.store,
      profile: DemoProfile.build(),
      clock: () => clock.now,
      feedback: GameFeedback(sound: widget.sound, haptics: false),
      // Обучение пройдено: вступительное окно первого запуска и подсказки
      // поверх кнопок — это ровно то, чего в трейлере быть не должно.
      initialSettings: AppSettings(
        lang: widget.lang,
        sound: widget.sound,
        haptics: false,
        tutorialDone: true,
      ),
    );
    _stage = TrailerStage(controller: _controller, navigator: _nav, clock: clock);
  }

  /// Круг пройден: свернуть открытые экраны, завести игру заново.
  void _loop() {
    widget.onPass?.call();
    final old = _controller;
    _nav.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _take++;
      _boot();
    });
    // Прежний контроллер снимается после кадра: до конца перестройки на него
    // ещё смотрят экраны, которые вот-вот исчезнут.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riftmark — трейлер',
      debugShowCheckedModeBanner: false,
      locale: Locale(widget.lang.code),
      supportedLocales: [for (final lang in Lang.values) Locale(lang.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: riftTheme(),
      navigatorKey: _nav,
      // `builder` оборачивает НАВИГАТОР, а не экран. Сборка, открытая поверх
      // Заставы, — отдельный маршрут; обернув только Заставу, камера
      // перестала бы её касаться ровно там, где начинается самое интересное.
      builder: (context, child) => TrailerHost(
        key: ValueKey(_take),
        stage: _stage,
        script: buildTrailerScript(),
        onLoop: _loop,
        child: child!,
      ),
      home: OutpostScreen(key: ValueKey(_take), controller: _controller),
    );
  }
}
