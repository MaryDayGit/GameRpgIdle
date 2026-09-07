import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'strings.dart';

/// Метка на элементе экрана: место, куда обучение умеет показать пальцем.
///
/// Обёртка вокруг виджета, и только. Экран не знает, идёт обучение или нет —
/// он расставляет метки один раз и живёт дальше; выбирает из них
/// [TutorialLayer]. Иначе каждое место, на которое надо указать, обросло бы
/// проверкой «а сейчас обучение?», и половина этих проверок разошлась бы с
/// самим сценарием.
class TutorialAnchor extends StatelessWidget {
  const TutorialAnchor({super.key, required this.id, required this.child});

  /// Идентификатор места. Уникален на всю игру, а не на экран: два виджета с
  /// одним [GlobalKey] в дереве — это падение, а экраны в стопке маршрутов
  /// живут одновременно.
  final String id;

  final Widget child;

  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey keyOf(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tutorial:$id'));

  /// Где сейчас это место относительно [ancestor].
  ///
  /// `null`, если метки на экране нет — например, раздел ещё не открыт или
  /// уехал за пределы списка. Подсказка тогда показывается без окна, а не
  /// падает: сценарий не должен ломаться от того, что кнопку переставили.
  static Rect? rectOf(String id, RenderObject? ancestor) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (ancestor is! RenderBox || !ancestor.attached) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: ancestor);
    return offset & box.size;
  }

  static BuildContext? contextOf(String id) => _keys[id]?.currentContext;

  /// Метка, которую только что нажали.
  ///
  /// Нужна шагам, у которых нет следа в состоянии игры: «откройте Сборку» не
  /// меняет в профиле ничего, и понять, что игрок это сделал, можно только по
  /// самому нажатию. Остальные шаги закрываются состоянием — так надёжнее, и
  /// эта дорожка для них не используется.
  static final ValueNotifier<String?> tapped = ValueNotifier<String?>(null);

  @override
  Widget build(BuildContext context) {
    // `deferToChild`: слушатель ничего не перехватывает и ничего не меняет в
    // попадании — он лишь узнаёт о нажатии, которое и так дойдёт до кнопки.
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => tapped.value = id,
      child: KeyedSubtree(key: keyOf(id), child: child),
    );
  }
}

/// Одна подсказка обучения: что показать, что сказать и что с ней делать.
///
/// Данные, а не виджет: сценарий живёт в `onboarding.dart` и ничего не знает
/// про рисование, а слой ничего не знает про игру.
class CoachMark {
  const CoachMark({
    required this.id,
    required this.title,
    required this.text,
    this.anchor,
    this.hint,
    this.onNext,
    this.onSkip,
    this.onLost,
    this.step = 0,
    this.total = 0,
  });

  /// Идентификатор шага. По нему слой понимает, что подсказка сменилась.
  final String id;

  final String title;
  final String text;

  /// Куда указывать. `null` — подсказка без окна, посреди экрана.
  final String? anchor;

  /// Подпись под текстом для шага-задания: что игрок должен сделать.
  /// `null` — шаг объясняющий, у него вместо подписи кнопка «Дальше».
  final String? hint;

  /// Нажатие «Дальше». `null` — шаг закрывается действием игрока, а не
  /// кнопкой: обучение, в котором всё проходится кнопкой «Дальше», ничему
  /// не учит.
  final VoidCallback? onNext;

  /// Пропустить обучение целиком.
  final VoidCallback? onSkip;

  /// Закрыть шаг, когда указывать оказалось не на что.
  ///
  /// Страховка, а не рабочий путь. Задание не даёт кнопки «Дальше» нарочно —
  /// но если места, на которое оно показывает, на экране вдруг нет, без
  /// кнопки игрок останется запертым под затемнением.
  final VoidCallback? onLost;

  /// Номер и длина сценария — «шаг 3 из 14». Игрок должен видеть, что это
  /// кончится, и когда.
  final int step;
  final int total;
}

/// Слой обучения поверх экрана: затемнение с окном, стрелка и карточка.
///
/// Окно в затемнении не просто нарисовано — оно **не перехватывает касания**.
/// Затемнение выложено четырьмя прямоугольниками вокруг окна, а не одним
/// полотном с дыркой: полотно поверх кнопки собирало бы нажатия на себя, и
/// обучение, зовущее нажать, само бы этому мешало.
class TutorialLayer extends StatefulWidget {
  const TutorialLayer({super.key, required this.child, this.mark});

  final Widget child;
  final CoachMark? mark;

  @override
  State<TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends State<TutorialLayer>
    with SingleTickerProviderStateMixin {
  final GlobalKey _hostKey = GlobalKey();

  /// Где сейчас подсвеченное место. `null` — метки на экране нет.
  Rect? _rect;

  /// К какой метке относится [_rect]: подсказка сменилась — рамка устарела.
  String? _rectFor;

  /// К какой метке уже подкрутили список. Один раз на шаг: подкручивать
  /// каждый кадр значило бы отнимать у игрока прокрутку.
  String? _scrolledFor;

  /// Появление карточки. Однократное, не циклическое: бесконечная анимация
  /// в дереве — это `pumpAndSettle`, который никогда не вернётся, то есть
  /// экраны, которые больше нечем проверить.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    if (widget.mark != null) _in.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant TutorialLayer old) {
    super.didUpdateWidget(old);
    final id = widget.mark?.id;
    if (id != old.mark?.id) {
      _rect = null;
      _rectFor = null;
      _scrolledFor = null;
      if (id != null) {
        _in
          ..reset()
          ..forward();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  /// Находит метку и, если надо, подкручивает к ней список.
  void _sync() {
    if (!mounted) return;
    final mark = widget.mark;
    final anchor = mark?.anchor;
    if (mark == null || anchor == null) {
      if (_rect != null) setState(() => _rect = null);
      return;
    }

    // Метка может быть за пределами видимой части списка — тогда её надо
    // сначала показать. Прокрутка запускает новый кадр, и рамка встанет на
    // место в следующем проходе.
    if (_scrolledFor != anchor) {
      _scrolledFor = anchor;
      final ctx = TutorialAnchor.contextOf(anchor);
      if (ctx != null && Scrollable.maybeOf(ctx) != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.35,
        ).whenComplete(() {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
          }
        });
        return;
      }
    }

    final host = _hostKey.currentContext?.findRenderObject();
    final rect = TutorialAnchor.rectOf(anchor, host);
    if (rect == _rect && anchor == _rectFor) return;
    setState(() {
      _rect = rect;
      _rectFor = anchor;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.mark;
    if (mark == null) return widget.child;

    return Stack(
      key: _hostKey,
      children: [
        // Прокрутка двигает подсвеченное место, и рамка обязана ехать вместе
        // с ним. Иначе окно висит там, где кнопка была секунду назад.
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
            return false;
          },
          child: widget.child,
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => _Spotlight(
              mark: mark,
              hole: _hole(Size(box.maxWidth, box.maxHeight)),
              appear: _in,
            ),
          ),
        ),
      ],
    );
  }

  /// Окно в затемнении: подсвеченное место плюс поля вокруг, обрезанное по
  /// экрану. `null` — указывать не на что.
  Rect? _hole(Size size) {
    final rect = _rect;
    if (rect == null) return null;
    final grown = rect.inflate(6);
    final clipped = Rect.fromLTRB(
      math.max(0, grown.left),
      math.max(0, grown.top),
      math.min(size.width, grown.right),
      math.min(size.height, grown.bottom),
    );
    if (clipped.width <= 0 || clipped.height <= 0) return null;
    return clipped;
  }
}

/// Затемнение, окно, стрелка и карточка.
class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.mark,
    required this.hole,
    required this.appear,
  });

  final CoachMark mark;
  final Rect? hole;
  final Animation<double> appear;

  static const _dim = Color(0xCC000000);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final spot = hole;

    return Stack(
      children: [
        if (spot == null)
          // Указывать не на что — глушится весь экран. Шаг без указателя
          // всегда объясняющий, и закрывает его кнопка на карточке.
          _blocker(left: 0, top: 0, width: size.width, height: size.height)
        else ...[
          // Четыре куска затемнения вокруг окна. Окно остаётся живым: по
          // подсвеченной кнопке можно нажать, и ровно этого от игрока и ждут.
          _blocker(left: 0, top: 0, width: size.width, height: spot.top),
          _blocker(
            left: 0,
            top: spot.bottom,
            width: size.width,
            height: size.height - spot.bottom,
          ),
          _blocker(
            left: 0,
            top: spot.top,
            width: spot.left,
            height: spot.height,
          ),
          _blocker(
            left: spot.right,
            top: spot.top,
            width: size.width - spot.right,
            height: spot.height,
          ),
          Positioned.fromRect(
            rect: spot,
            child: IgnorePointer(
              child: FadeTransition(
                opacity: appear,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE0A87A),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFC7643F).withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        _card(context, size, spot),
      ],
    );
  }

  Widget _blocker({
    required double left,
    required double top,
    required double width,
    required double height,
  }) =>
      Positioned(
        left: left,
        top: top,
        width: math.max(0.0, width),
        height: math.max(0.0, height),
        // Глушит нажатия мимо окна: пока идёт шаг, работает только то, на что
        // указано. Это и есть разница между обучением и подписью на экране.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const ColoredBox(color: _dim),
        ),
      );

  /// Карточка с текстом. Ставится по ту сторону окна, где больше места, и
  /// никогда не наезжает ни на само окно, ни на край экрана.
  ///
  /// Высота ограничена доступной полосой, а текст внутри прокручивается.
  /// Без ограничения карточка просто продолжалась за нижний край: на узком
  /// экране с крупным системным шрифтом кнопка «Дальше» оказывалась за
  /// пределами экрана, и шаг становилось нечем закрыть — проверено на
  /// телефоне 360×640 при ×1.3.
  Widget _card(BuildContext context, Size size, Rect? spot) {
    const margin = 16.0;
    const gap = 14.0;

    // Полосы, вырезанные системой: шторка сверху, навигация снизу.
    final insets = MediaQuery.paddingOf(context);

    final below =
        spot == null ? 0.0 : size.height - spot.bottom - gap - insets.bottom;
    final above = spot == null ? 0.0 : spot.top - gap - insets.top;
    final under = spot == null || below >= above;

    // Минимум оставляем на случай, когда окно занимает почти весь экран:
    // карточка станет прокручиваемой, но не исчезнет.
    final room = spot == null
        ? size.height - insets.vertical - margin * 2
        : math.max(140.0, under ? below : above);

    final body = FadeTransition(
      opacity: appear,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, under ? 0.06 : -0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: appear, curve: Curves.easeOut)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room),
          child: _CardBody(
            mark: mark,
            arrowUp: under,
            arrowAt: spot?.center.dx,
            lost: spot == null,
          ),
        ),
      ),
    );

    if (spot == null) {
      return Positioned(
        left: margin,
        right: margin,
        top: insets.top,
        bottom: insets.bottom,
        child: Center(child: body),
      );
    }

    return Positioned(
      left: margin,
      right: margin,
      top: under ? spot.bottom + gap : null,
      bottom: under ? null : math.max(0.0, size.height - spot.top + gap),
      child: body,
    );
  }
}

/// Сама карточка: стрелка, заголовок, объяснение и одно действие.
class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.mark,
    required this.arrowUp,
    required this.arrowAt,
    required this.lost,
  });

  final CoachMark mark;

  /// Места, на которое указывал шаг, на экране не нашлось.
  final bool lost;

  /// Стрелка смотрит вверх — карточка стоит под подсвеченным местом.
  final bool arrowUp;

  /// Куда указывает стрелка по горизонтали. `null` — стрелки нет.
  final double? arrowAt;

  static const _accent = Color(0xFFC7643F);

  @override
  Widget build(BuildContext context) {
    final arrow = arrowAt == null
        ? null
        : _Arrow(up: arrowUp, at: arrowAt!, margin: 16);

    final card = Material(
      color: const Color(0xFF23191A),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.7)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текст прокручивается, кнопки — нет. Места под карточку столько,
            // сколько осталось от подсвеченного окна, и при крупном системном
            // шрифте длинное объяснение в него не влезает. Уехать за край
            // может текст; кнопка, которой шаг закрывается, — не может.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (mark.total > 0)
                      Text(
                        S.tutorialProgress(mark.step, mark.total),
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: Colors.white38,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      mark.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mark.text,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.white70,
                      ),
                    ),
                    // Задание, которому не на что указать, показывать заданием
                    // нельзя: игрок не найдёт того, чего на экране нет.
                    if (mark.hint case final hint? when !lost) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.touch_app_outlined,
                              size: 16, color: Color(0xFFE0A87A)),
                          const SizedBox(width: 6),
                          // Задание переносится, а не обрезается: «Нажмите
                          // „Отправить“» при крупном системном шрифте шире
                          // узкого экрана.
                          Expanded(
                            child: Text(
                              hint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE0A87A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // `Wrap`, а не `Row`: «Пропустить обучение» и «Дальше» рядом не
            // помещаются на узком экране с крупным системным шрифтом, а
            // обрезанная кнопка «Дальше» — это запертый игрок.
            //
            // `spaceBetween` разводит их по краям. Стоя вплотную, «Пропустить»
            // собирает промахи по «Дальше», а промах здесь стоит всего
            // обучения.
            // Ширина явная: без неё `Wrap` сжимается по содержимому, и
            // разводить по краям становится нечего.
            SizedBox(
              width: double.infinity,
              child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                if (mark.onSkip != null)
                  TextButton(
                    onPressed: mark.onSkip,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.white38,
                    ),
                    child: Text(
                      S.tutorialSkip,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if (mark.onNext case final next?)
                  FilledButton(
                    onPressed: next,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(S.tutorialNext),
                  )
                else if (lost && mark.onLost != null)
                  FilledButton(
                    onPressed: mark.onLost,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(S.gotIt),
                  ),
              ],
              ),
            ),
          ],
        ),
      ),
    );

    if (arrow == null) return card;

    // Карточка гибкая, стрелка — нет: высота ограничена сверху, и ужиматься
    // должно то, что умеет прокручиваться.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arrowUp) arrow,
        Flexible(child: card),
        if (!arrowUp) arrow,
      ],
    );
  }
}

/// Стрелка от карточки к подсвеченному месту.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.up, required this.at, required this.margin});

  final bool up;

  /// Куда указывать — в координатах экрана, а не карточки.
  final double at;

  /// Отступ карточки от края экрана: на него сдвинуты её координаты.
  final double margin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - margin * 2;
    // Остриё не уезжает за скруглённый угол карточки.
    final x = at.clamp(margin + 18, margin + width - 18) - margin;

    return SizedBox(
      height: 9,
      width: double.infinity,
      child: CustomPaint(painter: _ArrowPainter(up: up, x: x)),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up, required this.x});

  final bool up;
  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFC7643F);
    final path = Path();
    if (up) {
      path
        ..moveTo(x, 0)
        ..lineTo(x - 9, size.height)
        ..lineTo(x + 9, size.height);
    } else {
      path
        ..moveTo(x, size.height)
        ..lineTo(x - 9, 0)
        ..lineTo(x + 9, 0);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up || old.x != x;
}
