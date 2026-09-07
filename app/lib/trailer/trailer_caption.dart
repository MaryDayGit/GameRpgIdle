import 'package:flutter/material.dart';

/// Подпись поверх кадра.
///
/// Данные, а не виджет: сценарий описывает, что сказать, и ничего не знает
/// про шрифты и появление.
@immutable
class TrailerLine {
  const TrailerLine(this.title, {this.text, this.top = false});

  final String title;

  /// Вторая строка помельче. `null` — только заголовок.
  final String? text;

  /// Поднять подпись наверх кадра. Нужно, когда камера смотрит вниз экрана и
  /// подпись легла бы ровно на то, что показывают.
  final bool top;

  @override
  bool operator ==(Object other) =>
      other is TrailerLine &&
      other.title == title &&
      other.text == text &&
      other.top == top;

  @override
  int get hashCode => Object.hash(title, text, top);
}

/// Слой подписей.
///
/// Поля сверху и снизу — не отступы по вкусу, а безопасные зоны вертикального
/// видео: в ленте поверх кадра лежат аватар, описание и кнопки. Текст,
/// доходящий до низа кадра, в TikTok окажется под ними, и это выяснится уже
/// после съёмки.
class TrailerCaptionLayer extends StatelessWidget {
  const TrailerCaptionLayer({super.key, required this.line});

  final TrailerLine? line;

  /// Сколько высоты кадра занимает интерфейс ленты. Снизу больше: там
  /// подпись, звук и три кнопки.
  static const safeTop = 0.14;
  static const safeBottom = 0.16;

  /// Докуда достаёт затемнение под текстом.
  ///
  /// Только нижняя треть. Раньше оно шло до середины кадра, и вместе с
  /// крупным заголовком подпись съедала пол-экрана — а показывать надо игру,
  /// а не подписи к ней.
  static const scrim = 0.42;

  @override
  Widget build(BuildContext context) {
    final line = this.line;

    // `Material` здесь не для вида. Слой подписей лежит поверх навигатора, вне
    // `Scaffold`, и своего стиля текста у него нет: Flutter рисует такой текст
    // служебным моноширинным шрифтом с жёлтым подчёркиванием — ровно то, что
    // и попало в первый дубль.
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Затемнение под текстом. Интерфейс игры тёмный, но не всюду:
              // без подложки заголовок ложится на светлую карточку и пропадает.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: line?.top ?? false
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      // Конец градиента считается в долях от середины кадра:
                      // -1 это край, 0 — середина. Держим его в трети.
                      end: Alignment(
                        0,
                        (line?.top ?? false ? -1 : 1) * (1 - 2 * scrim),
                      ),
                      colors: [
                        Colors.black.withValues(alpha: line == null ? 0 : 0.94),
                        Colors.black.withValues(alpha: line == null ? 0 : 0.8),
                        Colors.transparent,
                      ],
                      // Почти непрозрачное дно и быстрый спад. Ровный градиент
                      // не спасал: под подписью просвечивал список наёмников,
                      // и два текста читались одновременно.
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  top: height * safeTop,
                  bottom: height * safeBottom,
                ),
                child: Align(
                  alignment: line?.top ?? false
                      ? Alignment.topLeft
                      : Alignment.bottomLeft,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 460),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: line == null
                        ? const SizedBox.shrink()
                        : _Text(line, key: ValueKey(line)),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text(this.line, {super.key});

  final TrailerLine line;

  @override
  Widget build(BuildContext context) {
    final text = line.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.title,
          maxLines: 2,
          style: const TextStyle(
            fontSize: 25,
            height: 1.18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.1,
            shadows: [
              Shadow(blurRadius: 16, color: Colors.black87),
              Shadow(blurRadius: 3, color: Colors.black),
            ],
          ),
        ),
        if (text != null) ...[
          const SizedBox(height: 7),
          Text(
            text,
            maxLines: 2,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.32,
              color: Colors.white.withValues(alpha: 0.8),
              shadows: const [Shadow(blurRadius: 12, color: Colors.black87)],
            ),
          ),
        ],
      ],
    );
  }
}
