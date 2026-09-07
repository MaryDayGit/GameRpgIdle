import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rift/core/model/lang.dart';

import 'dev/core_probe_screen.dart';
import 'state/game_controller.dart';
import 'ui/outpost_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Контент и сейв грузятся ДО первого кадра: любая симуляция, стартовавшая
  // на значениях по умолчанию, посчитает не тот баланс — и это не будет видно.
  final controller = await GameController.boot();

  runApp(RiftApp(controller: controller));
}

class RiftApp extends StatelessWidget {
  const RiftApp({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Слушаем контроллер здесь, на самом верху: смена языка меняет `locale`
    // самого `MaterialApp`, а не только тексты внутри экранов. Перестрой мы
    // одну Заставу — системные виджеты остались бы на прежнем языке.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'Расселина',
      debugShowCheckedModeBanner: false,

      // Язык берётся из настроек игры, а не из системной локали телефона.
      // Игрок выбрал его сам в настройках, и системный русский не должен
      // переключать обратно того, кто нарочно поставил английский.
      //
      // `Localizations` здесь отвечает только за виджеты Flutter — кнопки
      // диалогов, меню выделения текста. Тексты самой игры идут через
      // `Lang.current` (`ui/strings.dart`), потому что собираются в том числе
      // вне дерева виджетов.
      locale: Locale(controller.settings.lang.code),
      supportedLocales: [for (final lang in Lang.values) Locale(lang.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC7643F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _Home(controller: controller),
    );
  }
}

/// Застава плюс вход в дев-пробу.
///
/// Проба остаётся доступной, пока идёт разработка: на ней проверяется ядро
/// целиком, и терять её раньше, чем появятся настоящие боевой экран и
/// инвентарь, незачем. К релизу `lib/dev/` удаляется.
class _Home extends StatelessWidget {
  const _Home({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        OutpostScreen(controller: controller),
        Positioned(
          right: 8,
          bottom: 8,
          child: Opacity(
            opacity: 0.4,
            child: IconButton(
              tooltip: const Phrase('Дев-проба ядра', 'Core probe').text,
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CoreProbeScreen(content: controller.content),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
