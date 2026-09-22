import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rift/core/model/lang.dart';

import 'state/game_controller.dart';
import 'ui/outpost_screen.dart';
import 'ui/theme.dart';

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
      title: 'Riftmark',
      debugShowCheckedModeBanner: false,

      // Язык берётся из настроек игры, а не из системной локали телефона.
      // Игрок выбрал его сам в настройках, и системный русский не должен
      // переключать обратно того, кто нарочно поставил английский. Локаль
      // телефона спрашивают один раз — при первом запуске, когда настроек
      // ещё нет и выбора тоже (`SettingsStore.load`).
      //
      // `Localizations` здесь отвечает только за виджеты Flutter — кнопки
      // диалогов, меню выделения текста. Тексты самой игры идут через
      // `Lang.current` (`ui/strings.dart`), потому что собираются в том числе
      // вне дерева виджетов.
      locale: Locale(controller.settings.lang.code),
      supportedLocales: [for (final lang in Lang.values) Locale(lang.code)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: riftTheme(),
      home: OutpostScreen(controller: controller),
    );
  }
}
