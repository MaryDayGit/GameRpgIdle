import 'package:flutter/material.dart';
import 'package:rift/core/content/passive_tree_def.dart';
import 'package:rift/core/model/passive_tree.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'passive_icons.dart';

/// Дерево пассивок — граф, а не список.
///
/// Список убил бы главное: расстояние. Ценность узла здесь не только в его
/// прибавке, но и в том, сколько очков стоит до него дойти, а это видно
/// только на карте. Поэтому холст с панорамированием и масштабом, узлы на
/// своих координатах из контента и линии между ними.
class PassiveTreeScreen extends StatefulWidget {
  const PassiveTreeScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<PassiveTreeScreen> createState() => _PassiveTreeScreenState();
}

class _PassiveTreeScreenState extends State<PassiveTreeScreen> {
  GameController get c => widget.controller;

  final _viewer = TransformationController();

  /// Узел, на который игрок нажал: карточка снизу показывает, что он даёт,
  /// и только оттуда его берут. Нажатие сразу по узлу тратило бы очко от
  /// случайного касания при панорамировании.
  String? _selected;

  @override
  void initState() {
    super.initState();
    // Дерево начинается от корня, поэтому и смотреть на него надо от центра.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnRoot());
  }

  void _centerOnRoot() {
    final size = MediaQuery.sizeOf(context);
    _viewer.value = Matrix4.identity()
      ..translateByDouble(
        size.width / 2 - _canvasSize / 2,
        size.height / 2 - _canvasSize / 2,
        0,
        1,
      );
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  static const double _canvasSize = treeCanvasSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final tree = c.profile.passives;
        final left = c.profile.passivePointsLeft;
        final selected = _selected == null ? null : tree.node(_selected!);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Дерево пассивок'),
            actions: [
              if (tree.spent > 0)
                TextButton(
                  onPressed: () => _confirmReset(context),
                  child: const Text('Сбросить'),
                ),
            ],
          ),
          body: Column(
            children: [
              _Header(
                left: left,
                total: c.profile.passivePoints,
                spent: tree.spent,
                nextAt: c.profile.nextPassivePointDepth,
              ),
              Expanded(
                child: InteractiveViewer(
                  transformationController: _viewer,
                  constrained: false,
                  minScale: 0.35,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: SizedBox(
                    width: _canvasSize,
                    height: _canvasSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _tapAt(tree, details.localPosition),
                      child: CustomPaint(
                        painter: _TreePainter(
                          tree: tree,
                          selected: _selected,
                          canBuy: left > 0,
                          origin: _canvasSize / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected != null)
                _NodeCard(
                  node: selected,
                  taken: tree.has(selected.id),
                  canTake: tree.canAllocate(selected.id, c.profile.passivePoints),
                  canRefund: tree.canRefund(selected.id),
                  onTake: () => c.allocatePassive(selected.id),
                  onRefund: () => c.refundPassive(selected.id),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Ищет узел под пальцем. Радиус попадания больше нарисованного: на
  /// телефоне палец толще узла, и промах читается как «экран не реагирует».
  void _tapAt(PassiveTree tree, Offset point) {
    const hitRadius = 26.0;
    String? hit;
    var best = double.infinity;

    for (final node in tree.nodes) {
      final center = Offset(
        _canvasSize / 2 + node.x * _scale,
        _canvasSize / 2 + node.y * _scale,
      );
      final distance = (center - point).distance;
      if (distance < hitRadius && distance < best) {
        best = distance;
        hit = node.id;
      }
    }

    setState(() => _selected = hit);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить дерево?'),
        content: const Text(
          'Все очки вернутся, и дерево можно будет собрать заново. '
          'Ничего не теряется — кроме самой сборки.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (agreed == true) {
      c.resetPassives();
      setState(() => _selected = null);
    }
  }
}

/// Цвет луча. Один на весь экран: карта и карточка узла обязаны красить
/// один и тот же узел одинаково.
const _clusterColors = {
  'root': Color(0xFFD9C8A9),
  'flesh': Color(0xFFC7643F),
  'stone': Color(0xFF8A7F77),
  'fang': Color(0xFFE0A87A),
  'spark': Color(0xFF7FB069),
  'wind': Color(0xFF5E7E92),
  'leech': Color(0xFF8E3A46),
  'mind': Color(0xFF5B8DD9),
  'hunt': Color(0xFFB7A05C),
  // Стихийные лучи: цвет узнаётся раньше подписи, и стихия — первое, что
  // игрок ищет глазами, когда собирает билд под свои умения.
  'ember': Color(0xFFD9622B),
  'frost': Color(0xFF6FB6D6),
  'storm': Color(0xFFC9A227),
  'abyss': Color(0xFF8B5FB0),
  'arcane': Color(0xFF4FA88B),
};

/// Во сколько пикселей превращается условная единица координат из контента.
const double _scale = treeScreenScale;

/// Сторона холста в пикселях. Координаты узлов в контенте условные, и холст
/// делается заведомо больше дерева: обрезанный край выглядел бы как
/// отсутствующая ветка. Дерево занимает 1436 пикселей из 1800.
///
/// Публичная, потому что по ней же тест считает, куда нажимать: тест со своей
/// копией числа проверяет не тот экран, который видит игрок.
const double treeCanvasSize = 1800;

class _Header extends StatelessWidget {
  const _Header({
    required this.left,
    required this.total,
    required this.spent,
    required this.nextAt,
  });

  final int left;
  final int total;
  final int spent;
  final int? nextAt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Flexible(
              child: Text(
                left > 0
                    ? '${plural(left, "очко", "очка", "очков")} свободно'
                    : 'Очков нет',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: left > 0 ? const Color(0xFFE0A87A) : Colors.white54,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Text(
                nextAt == null
                    ? 'вложено $spent из $total'
                    : 'вложено $spent из $total · следующее с этажа $nextAt',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
          ],
        ),
      );
}

/// Карточка выбранного узла. Взять можно только отсюда: нажатие прямо по
/// узлу тратило бы очко от случайного касания при панорамировании.
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.taken,
    required this.canTake,
    required this.canRefund,
    required this.onTake,
    required this.onRefund,
  });

  final PassiveNodeDef node;
  final bool taken;
  final bool canTake;
  final bool canRefund;
  final VoidCallback onTake;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            // Иконка та же, что на карте: карточка должна опознаваться как
            // тот узел, по которому игрок только что попал пальцем.
            SizedBox(
              width: 34,
              height: 34,
              child: CustomPaint(
                painter: _IconPainter(
                  icon: node.icon,
                  color: _clusterColors[node.cluster] ?? Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `Wrap`, а не `Row`: имя узла плюс два ярлыка при
                  // крупном системном шрифте не влезают в оставшуюся ширину,
                  // а обрезать имя узла нельзя — по нему его и опознают.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(node.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      // Класс узла назван словом. Три класса — это разные
                      // обещания: дорога, награда и размен; не сказать,
                      // который перед тобой, значит показать три одинаковых
                      // кружка разного размера.
                      if (_classLabel(node.kind) != null)
                        Text(_classLabel(node.kind)!,
                            style: TextStyle(
                                fontSize: 11,
                                color: node.kind == PassiveKind.keystone
                                    ? const Color(0xFFC7643F)
                                    : const Color(0xFF7FB069))),
                      if (node.rule != null)
                        const Text('правило',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF9AA7D0))),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(node.text,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (taken)
              OutlinedButton(
                onPressed: canRefund ? onRefund : null,
                child: const Text('Снять'),
              )
            else
              FilledButton(
                onPressed: canTake ? onTake : null,
                child: const Text('Взять'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Рисование дерева. Связи под узлами, узлы поверх; взятое — заливкой,
/// доступное — контуром, остальное — приглушённым.
/// Иконка узла для карточки — тем же рисунком, что и на карте.
class _IconPainter extends CustomPainter {
  const _IconPainter({required this.icon, required this.color});

  final String icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.shortestSide / 2,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    paintPassiveIcon(canvas, icon, center, size.shortestSide * 0.3, color);
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}

/// Класс узла словом. У дороги имени нет: её и так видно по размеру, а
/// подпись у каждого второго узла превратилась бы в шум.
String? _classLabel(PassiveKind kind) => switch (kind) {
      PassiveKind.keystone => 'ключевой',
      PassiveKind.notable => 'крупный',
      _ => null,
    };

class _TreePainter extends CustomPainter {
  _TreePainter({
    required this.tree,
    required this.selected,
    required this.canBuy,
    required this.origin,
  });

  final PassiveTree tree;
  final String? selected;
  final bool canBuy;
  final double origin;


  Offset _at(PassiveNodeDef node) =>
      Offset(origin + node.x * _scale, origin + node.y * _scale);

  /// Дуга между соседними лучами: выгибается ОТ центра.
  ///
  /// Контрольная точка отодвинута наружу по радиусу середины отрезка. Так
  /// перемычка обходит промежуток между лучами по кругу — как ей и положено
  /// по смыслу: это переход по соседнему кольцу, а не прямая через дерево.
  Path _arc(Offset from, Offset to) {
    final centre = Offset(origin, origin);
    final middle = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);

    final radial = middle - centre;
    final length = radial.distance;
    if (length < 1) {
      return Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy);
    }

    // Выгиб пропорционален длине хорды: короткая перемычка почти прямая,
    // длинная заметно выгнута.
    final chord = (to - from).distance;
    final control = middle + radial / length * (chord * 0.28);

    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final node in tree.nodes) node.id: node};

    for (final link in tree.def.links) {
      final from = byId[link.from];
      final to = byId[link.to];
      if (from == null || to == null) continue;

      final both = tree.has(from.id) &&
          (tree.has(to.id) || to.isRoot || from.isRoot);

      // Взятая дорога светится цветом своего луча, а не белым: по цвету
      // видно, куда игрок уже вложился, не читая ни одной подписи.
      final colour = _clusterColors[from.cluster] ?? Colors.white70;

      // Перемычка между лучами рисуется ДУГОЙ, огибающей центр. Прямая
      // прошла бы через чужой сектор и читалась бы как случайное
      // пересечение — на это и пожаловался живой прогон.
      final path = link.bridge
          ? _arc(_at(from), _at(to))
          : (Path()
            ..moveTo(_at(from).dx, _at(from).dy)
            ..lineTo(_at(to).dx, _at(to).dy));

      if (both) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.0
            ..strokeCap = StrokeCap.round
            ..color = colour.withValues(alpha: 0.18),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = both ? 2.4 : 1.2
          ..strokeCap = StrokeCap.round
          // Перемычка бледнее дороги: она — возможность перейти, а не сам
          // путь, и не должна спорить с лучами за внимание.
          ..color = both
              ? colour.withValues(alpha: link.bridge ? 0.5 : 0.75)
              : Colors.white.withValues(alpha: link.bridge ? 0.06 : 0.09),
      );
    }

    for (final node in tree.nodes) {
      final taken = tree.has(node.id);
      final available = !taken && tree.canAllocate(node.id, 1 << 30);
      final color = _clusterColors[node.cluster] ?? Colors.white70;
      final center = _at(node);
      // Размер говорит о классе узла раньше подписи: дорога мелкая, крупный
      // заметно больше, ключевой — самый большой.
      final radius = switch (node.kind) {
        PassiveKind.root => 17.0,
        PassiveKind.keystone => 16.0,
        PassiveKind.notable => 13.0,
        PassiveKind.stat => 9.0,
      };

      if (node.id == selected) {
        canvas.drawCircle(
          center,
          radius + 7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.75),
        );
      }

      // Взятый узел светится: дерево должно читаться боковым зрением, а не
      // разбираться по одному кружку.
      if (taken && node.kind != PassiveKind.stat) {
        canvas.drawCircle(
          center,
          radius + 6,
          Paint()..color = color.withValues(alpha: 0.14),
        );
      }

      // Тёмная подложка под иконкой: без неё рисунок сливается со связями,
      // которые проходят под узлом.
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFF16110F),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = taken
              ? color.withValues(alpha: 0.35)
              : color.withValues(alpha: available && canBuy ? 0.14 : 0.06),
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = taken ? 2.2 : (available ? 1.6 : 1.0)
          ..color = color.withValues(
              alpha: taken ? 1.0 : (available ? 0.75 : 0.22)),
      );

      // Ключевой узел обведён дважды: размен должно быть видно издалека.
      if (node.kind == PassiveKind.keystone) {
        canvas.drawCircle(
          center,
          radius - 3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = color.withValues(alpha: taken ? 0.8 : 0.3),
        );
      }

      // Корень помечен кольцом: у него нет ни стата, ни правила, но пустой
      // тёмный круг в центре дерева читается как дырка в картинке.
      if (node.isRoot) {
        canvas.drawCircle(
          center,
          radius * 0.45,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.8),
        );
      }

      if (!node.isRoot) {
        paintPassiveIcon(
          canvas,
          node.icon,
          center,
          radius * 0.62,
          color.withValues(alpha: taken ? 1.0 : (available ? 0.7 : 0.28)),
        );
      }

      // Крупные узлы подписаны прямо на карте: до них идут специально, и
      // искать их по нажатиям — это искать вслепую. Мелкие не подписаны
      // намеренно: сто восемьдесят подписей — это уже не карта.
      if (node.kind != PassiveKind.stat) {
        final label = TextPainter(
          text: TextSpan(
            text: node.name,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: taken ? 0.9 : 0.45),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final at = labelTopLeft(center, radius, label.size);

        // Подложка под подписью: без неё текст ложится поверх связей и
        // читается через них.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                at.dx - 4, at.dy - 1, label.width + 8, label.height + 2),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0xFF120E0C).withValues(alpha: 0.72),
        );
        label.paint(canvas, at);
      }
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.selected != selected ||
      old.canBuy != canBuy ||
      old.tree.spent != tree.spent;
}

/// Где лежит подпись крупного узла.
///
/// Отдельной чистой функцией, а не выражением внутри рисования: наложение
/// подписей нельзя увидеть, глядя на один узел, — проверять его надо на всём
/// наборе сразу, и тест зовёт эту функцию напрямую.
///
/// Расталкивания здесь нет намеренно. Оно было написано и оказалось лишним:
/// после того как дерево выросло в полтора раза (масштаб 0.62 -> 0.95),
/// подписи разошлись сами, и механизм не срабатывал ни разу. Механизм,
/// который никогда не выполняется, невозможно ни проверить, ни починить —
/// он просто ждёт своего часа с неизвестной ошибкой внутри. Если контента
/// станет больше и тест на наложение упадёт, расталкивание вернётся вместе
/// со случаем, на котором его видно.
Offset labelTopLeft(Offset center, double nodeRadius, Size label) =>
    center + Offset(-label.width / 2, nodeRadius + 5);
