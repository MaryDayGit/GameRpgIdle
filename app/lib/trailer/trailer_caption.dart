import 'package:flutter/material.dart';

/// Подпись поверх кадра.
///
/// Данные, а не виджет: сценарий описывает, что сказать, и ничего не знает
/// про шрифты и появление.
@immutable
class TrailerLine {
  const TrailerLine(this.title, {this.text, this.top = false, this.card = false});

  final String title;

  /// Вторая строка помельче. `null` — только заголовок.
  final String? text;

  /// Поднять подпись наверх кадра. Нужно, когда камера смотрит вниз экрана и
  /// подпись легла бы ровно на то, что показывают.
  final bool top;

  /// Финальная карточка: текст по центру на затемнённом кадре.
  ///
  /// Ролику нужен конец, а не затухание на общем плане. Последний кадр,
  /// оставленный подписью в углу, читается как «запись оборвалась»; название
  /// по центру — как «это было кино».
  final bool card;

  @override
  bool operator ==(Object other) =>
      other is TrailerLine &&
      other.title == title &&
      other.text == text &&
      other.top == top &&
      other.card == card;

  @override
  int get hashCode => Object.hash(title, text, top, card);
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
  static const safeTop = 0.13;
  static const safeBottom = 0.15;

  /// Ключ подложки. Нужен проверке: высота этой полосы и есть то, насколько
  /// подпись закрывает игру, и мерить её глазами — значит мерить её на записи.
  static const plate = ValueKey('trailer.caption.plate');

  /// Ключ финальной карточки. Она закрывает кадр целиком — и должна.
  static const cardPlate = ValueKey('trailer.caption.card');

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
            final top = line?.top ?? false;

            final card = line?.card ?? false;

            return Padding(
              padding: EdgeInsets.only(
                top: !card && top ? height * safeTop : 0,
                bottom: !card && !top ? height * safeBottom : 0,
              ),
              child: Align(
                alignment: card
                    ? Alignment.center
                    : top
                        ? Alignment.topLeft
                        : Alignment.bottomLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 520),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: Offset(0, top ? -0.14 : 0.14),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: line == null
                      ? const SizedBox.shrink()
                      : line.card
                          ? _Card(line, key: ValueKey(line))
                          : _Plate(line, key: ValueKey(line)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Подпись со своей подложкой.
///
/// Подложка ОБНИМАЕТ ТЕКСТ, а не закрывает треть кадра. Раньше это был
/// градиент от края до 42 % высоты — постоянная тёмная полоса на две строки
/// текста, из-за которой почти половина кадра показывала не игру, а фон под
/// подписью. Теперь высота подложки равна высоте текста плюс поля, и оба её
/// края растушёваны: она читается как полоска титра, а не как штора.
class _Plate extends StatelessWidget {
  const _Plate(this.line, {super.key});

  final TrailerLine line;

  @override
  Widget build(BuildContext context) {
    final text = line.text;

    return Container(
      key: TrailerCaptionLayer.plate,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.80),
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
          ],
          stops: const [0, 0.26, 0.74, 1],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            line.title,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 23,
              height: 1.16,
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
            const SizedBox(height: 6),
            Text(
              text,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: Colors.white.withValues(alpha: 0.78),
                shadows: const [Shadow(blurRadius: 12, color: Colors.black87)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Финальная карточка: название по центру затемнённого кадра.
///
/// Игра под ней продолжает работать и продолжает двигаться — карточка
/// прозрачна процентов на десять. Кадр, ушедший в глухой чёрный, обрывает
/// ролик; кадр, сквозь который ещё видно Заставу, его закрывает.
class _Card extends StatelessWidget {
  const _Card(this.line, {super.key});

  final TrailerLine line;

  @override
  Widget build(BuildContext context) {
    final text = line.text;

    return Container(
      key: TrailerCaptionLayer.cardPlate,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            line.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
          if (text != null) ...[
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
