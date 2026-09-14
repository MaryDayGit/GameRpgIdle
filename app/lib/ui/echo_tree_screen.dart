import 'package:flutter/material.dart';
import 'package:rift/core/content/echo_tree_def.dart';

import '../state/game_controller.dart';
import 'strings.dart';
import 'theme.dart';

/// Древо Эха (GDD §8.3).
///
/// Единственная прогрессия, переживающая смерть наёмника, и единственное место,
/// где тратится Эхо. Поэтому экран показывает не «сколько вложено», а ЧТО
/// вложено: ветка открывается по порядку, и Эхо, ушедшее в урон, не досталось
/// выживанию.
class EchoTreeScreen extends StatefulWidget {
  const EchoTreeScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<EchoTreeScreen> createState() => _EchoTreeScreenState();
}

class _EchoTreeScreenState extends State<EchoTreeScreen> {
  GameController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final tree = c.profile.tree;

        return Scaffold(
          appBar: AppBar(title: Text(S.echoTreeTitle)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // `Wrap`, а не `Row`: числа растут (Эхо доходит до десятков
              // тысяч), подписи русские, а ширина экрана — нет. Перенос на
              // вторую строку честнее, чем обрезание.
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  // Эхо — своим цветом, тем же, что в полосе ресурсов на
                  // Заставе: это валюта, и узнаваться она обязана везде.
                  Text(S.echoAmount(c.profile.echo),
                      style: RiftText.title.copyWith(color: RiftColors.echo)),
                  Text(
                    tree.complete
                        ? S.echoTreeComplete
                        : S.echoNextNode(tree.nextNodeCost.round()),
                    style: const TextStyle(fontSize: 13.5, color: RiftColors.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                S.echoTreeAbout(tree.nodesBought, tree.totalNodes),
                style: const TextStyle(fontSize: 13.5, color: RiftColors.inkFaint),
              ),
              const SizedBox(height: 20),

              for (final branch in tree.branches) ...[
                _BranchHeader(branch: branch, tree: tree),
                for (final node in branch.nodes)
                  _NodeRow(
                    node: node,
                    bought: tree.has(node.id),
                    available: tree.isAvailable(node.id),
                    cost: tree.nextNodeCost.round(),
                    affordable: c.canBuyEchoNode,
                    onBuy: () => c.buyEchoNode(node.id),
                  ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BranchHeader extends StatelessWidget {
  const _BranchHeader({required this.branch, required this.tree});

  final EchoBranchDef branch;
  final dynamic tree;

  @override
  Widget build(BuildContext context) {
    final bought = branch.nodes.where((n) => tree.has(n.id)).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Flexible(
            child: Text(branch.name, style: RiftText.title),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(branch.about,
                style: const TextStyle(fontSize: 13.5, color: RiftColors.inkFaint)),
          ),
          Text('$bought/${branch.nodes.length}',
              style: const TextStyle(fontSize: 13.5, color: RiftColors.inkMuted)),
        ],
      ),
    );
  }
}

/// Строка узла. Три состояния, и все три должны читаться взглядом: куплен,
/// доступен, закрыт предыдущим.
class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.bought,
    required this.available,
    required this.cost,
    required this.affordable,
    required this.onBuy,
  });

  final EchoNodeDef node;
  final bool bought;
  final bool available;
  final int cost;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final canBuy = available && affordable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bought
                ? Icons.check_circle
                : available
                    ? Icons.radio_button_unchecked
                    : Icons.lock_outline,
            size: 18,
            color: bought
                ? RiftColors.good
                : available
                    ? RiftColors.inkMuted
                    : RiftColors.inkDisabled,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: bought || available ? RiftColors.ink : RiftColors.inkFaint,
                  ),
                ),
                Text(
                  node.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: bought || available
                        ? RiftColors.inkMuted
                        : RiftColors.inkDisabled,
                  ),
                ),
              ],
            ),
          ),
          if (!bought)
            // Ширина по содержимому, а не 92 точки: цена растёт до пяти цифр,
            // и при крупном системном шрифте фиксированная кнопка обрезала бы
            // ровно то число, ради которого её и смотрят.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: OutlinedButton(
                onPressed: canBuy ? onBuy : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: RiftColors.echo,
                  side: BorderSide(
                    color: canBuy
                        ? RiftColors.echo.withValues(alpha: 0.6)
                        : RiftColors.line,
                  ),
                ),
                child: Text('$cost'),
              ),
            ),
        ],
      ),
    );
  }
}
