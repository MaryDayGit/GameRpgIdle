import 'package:flutter/material.dart';

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
    return MaterialApp(
      title: 'Расселина',
      debugShowCheckedModeBanner: false,
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
              tooltip: 'Дев-проба ядра',
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
