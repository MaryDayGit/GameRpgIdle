import 'package:flutter/material.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/enemy.dart';
import 'package:rift/core/model/mercenary.dart';

import '../state/game_controller.dart';
import 'format.dart';
import 'lair_battle_screen.dart';
import 'outpost_screen.dart' show showAbout;
import 'strings.dart';
import 'theme.dart';

/// Логова стражей — цель позднего этапа (раунд 36).
///
/// Отдельный экран, а не раздел Заставы: логова открываются, когда всё
/// остальное на Заставе уже построено, и спрашивают о другом. Застава —
/// «кого и когда отправить», логово — «чем идти против этого стража».
class LairScreen extends StatelessWidget {
  const LairScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profile = controller.profile;
        return Scaffold(
          appBar: AppBar(
            title: Text(S.lairsTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => showAbout(context, S.lairsTitle, S.lairsAbout),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                S.lairTrophies(
                  profile.lairTrophies,
                  profile.lairPassivePoints,
                  profile.lairPassivePoints + profile.lairPassivePointsLeft,
                ),
                style: RiftText.small,
              ),
              const SizedBox(height: 12),
              for (final guardian in Bestiary.guardians) ...[
                _GuardianCard(controller: controller, guardian: guardian),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GuardianCard extends StatelessWidget {
  const _GuardianCard({required this.controller, required this.guardian});

  final GameController controller;
  final EnemyArchetype guardian;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    final circle = profile.nextLairCircle(guardian.id);
    final taken = profile.lairCircles[guardian.id] ?? 0;
    final reserve = profile.roster.reserve;

    // Вещи — те, что страж роняет: ради них к взятому кругу и возвращаются,
    // и игрок должен знать, за чем идёт, до того как заплатить.
    final drops = [
      for (final def in ContentPack.current.relics)
        if (def.source != null && def.source == guardian.embodies) def.name,
    ];

    // Причина проверяется на первом из резерва: у всех одна и та же, кроме
    // «занят», а занятых в резерве не бывает.
    final blocked = reserve.isEmpty
        ? S.lairNoMercs
        : profile.lairBlockedReason(reserve.first, guardian.id, circle);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: RiftColors.surface,
        borderRadius: BorderRadius.circular(RiftSize.radius),
        border: Border.all(color: RiftColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(guardian.name, style: RiftText.heading),
          if (guardian.role.isNotEmpty)
            Text(guardian.role, style: RiftText.caption),
          const SizedBox(height: 8),
          Text(
            S.lairCircle(circle, balance.Curves.lairDepth(circle)),
            style: RiftText.body,
          ),
          Text(
            S.lairOffering(money(balance.Curves.lairOffering(circle))),
            style: const TextStyle(fontSize: 13.5, color: RiftColors.gold),
          ),
          if (taken > 0)
            Text(S.lairTaken(taken),
                style: const TextStyle(fontSize: 13, color: RiftColors.good)),
          // Умения — до вызова: «чем идти» решается по ним, и узнавать о
          // Немоте из гибели наёмника значит платить за знание жизнью.
          if (guardian.skills.isNotEmpty)
            Text(
              S.lairSkills(guardian.skills.map((s) => s.name).join(', ')),
              style: const TextStyle(fontSize: 13, color: RiftColors.warn),
            ),
          if (weaknessHint(guardian) case final hint?)
            Text(hint,
                style: const TextStyle(fontSize: 13, color: RiftColors.info)),
          if (drops.isNotEmpty)
            Text(S.lairDrops(drops.join(', ')), style: RiftText.caption),
          const SizedBox(height: 10),
          if (blocked != null)
            Text(blocked,
                style: const TextStyle(fontSize: 13, color: RiftColors.inkFaint))
          else
            FilledButton(
              key: Key('lair-challenge-${guardian.id}'),
              onPressed: () => _pickAndFight(context),
              child: Text(S.lairChallenge),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndFight(BuildContext context) async {
    final merc = await showModalBottomSheet<Mercenary>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(S.lairPickMerc, style: RiftText.heading),
            const SizedBox(height: 4),
            Text(S.lairLossWarning,
                style: const TextStyle(fontSize: 13, color: RiftColors.bad)),
            const SizedBox(height: 8),
            for (final m in controller.profile.roster.reserve)
              ListTile(
                key: Key('lair-merc-${m.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(m.name),
                subtitle: Text(m.rank.forGender(m.gender)),
                onTap: () => Navigator.of(sheet).pop(m),
              ),
          ],
        ),
      ),
    );
    if (merc == null || !context.mounted) return;

    // Исход уже записан — экран боя его показывает, а не решает.
    final challenge = controller.challengeGuardian(merc, guardian.id);
    if (challenge == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LairBattleScreen(controller: controller, challenge: challenge),
      ),
    );
  }
}
