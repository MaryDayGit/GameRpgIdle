import 'package:flutter/material.dart';
import 'package:rift/core/save/save_head.dart';

import '../data/account.dart';
import '../state/game_controller.dart';
import 'strings.dart';
import 'theme.dart';

/// Строка «Сохранение в облаке» в настройках.
///
/// ## Почему это лежит рядом со звуком, а не за отдельным экраном
///
/// Аккаунт в этой игре не даёт ничего, кроме сохранности прогресса: ни
/// друзей, ни профиля, ни покупок. Экран входа с логотипом сообщал бы
/// обратное — что тут есть какая-то отдельная сущность «аккаунт», ради
/// которой стоит отвлечься от игры.
///
/// ## Почему подпись говорит про потерю, а не про вход
///
/// «Войдите через Google» — это просьба, на которую нет причины соглашаться.
/// «Прогресс живёт только на этом телефоне, переустановка сотрёт его» — это
/// факт, из которого игрок делает вывод сам. Он и правда таков: анонимный
/// аккаунт хранится в данных приложения и стирается вместе с ними
/// (`account_firebase.dart`).
class AccountTile extends StatefulWidget {
  const AccountTile({super.key, required this.controller});

  final GameController controller;

  @override
  State<AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<AccountTile> {
  bool _busy = false;

  Future<void> _link() async {
    setState(() => _busy = true);
    final outcome = await widget.controller.linkGoogle();
    if (!mounted) return;
    setState(() => _busy = false);

    // Отменённый вход молчит. Игрок сам закрыл окно выбора аккаунта, и
    // сообщать ему об этом значит обвинять его в собственном решении.
    final message = switch (outcome) {
      LinkOutcome.ok => S.accountLinkedNow,
      LinkOutcome.alreadyInUse => S.accountAlreadyInUse,
      LinkOutcome.cancelled => null,
      LinkOutcome.failed => S.accountLinkFailed,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    // Вход в уже существующий аккаунт мог принести второй сейв. Спрашиваем
    // сразу, не откладывая до следующего запуска: игрок только что нажал
    // кнопку и понимает, о чём речь, — а через сутки не поймёт.
    if (mounted && widget.controller.hasPendingSync) {
      await showSyncConflictDialog(context, widget.controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.controller.account.current;

    final (subtitle, action) = switch (account.kind) {
      AccountKind.google => (S.accountLinkedAbout, S.accountSignOut),
      AccountKind.anonymous => (S.accountAnonymousAbout, S.accountLink),
      // Аккаунта нет вовсе: нет сети, нет Play Services, нет ключей Firebase.
      // Кнопка остаётся — попытка входа тут же и есть попытка связи.
      AccountKind.none => (S.accountOfflineAbout, S.accountLink),
    };

    // Значок говорит состояние раньше подписи: облако с галочкой — прогресс
    // в сохранности, перечёркнутое — живёт только на этом телефоне.
    final linked = account.kind == AccountKind.google;
    return ListTile(
      leading: Icon(
        linked ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        color: linked ? RiftColors.good : RiftColors.warn,
      ),
      title: Text(S.accountTitle),
      subtitle: Text(
        account.kind == AccountKind.google && account.email != null
            ? '${account.email}\n$subtitle'
            : subtitle,
      ),
      isThreeLine: account.kind == AccountKind.google,
      trailing: _busy
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: account.kind == AccountKind.google
                  ? () async {
                      await widget.controller.signOutAccount();
                      if (mounted) setState(() {});
                    }
                  : _link,
              child: Text(action),
            ),
    );
  }
}

/// Строка «Удалить аккаунт и данные» в настройках.
///
/// Требование Google Play: игрок, который может завести аккаунт, должен
/// суметь удалить его из самой игры (`docs/13-RELEASE.md` §3.3). Стоит
/// последней в настройках и отдельно от «Сохранения в облаке»: выход из
/// аккаунта прогресс не трогает, удаление стирает всё, и перепутать их
/// соседством нельзя.
class DeleteAccountTile extends StatefulWidget {
  const DeleteAccountTile({super.key, required this.controller});

  final GameController controller;

  @override
  State<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends State<DeleteAccountTile> {
  bool _busy = false;

  Future<void> _delete() async {
    final google =
        widget.controller.account.current.kind == AccountKind.google;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.deleteAccountConfirmTitle),
        content: Text(S.deleteAccountConfirmBody(google: google)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            key: const Key('delete-account-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: RiftColors.bad,
              foregroundColor: RiftColors.emberDeep,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.deleteAccountConfirm),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    final outcome = await widget.controller.deleteAccountAndData();
    if (!mounted) return;
    setState(() => _busy = false);

    // Отменённый повторный вход молчит — как и отменённая привязка.
    final message = switch (outcome) {
      DeleteOutcome.ok => S.deleteAccountDone,
      DeleteOutcome.cancelled => null,
      DeleteOutcome.failed => S.deleteAccountFailed,
    };
    final messenger = ScaffoldMessenger.of(context);
    // После удаления настройки закрываются: за ними уже новая игра.
    if (outcome == DeleteOutcome.ok) await Navigator.of(context).maybePop();
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.delete_forever_outlined, color: RiftColors.bad),
      title: Text(
        S.deleteAccountTitle,
        style: const TextStyle(color: RiftColors.bad),
      ),
      subtitle: Text(S.deleteAccountAbout),
      trailing: _busy
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: _busy ? null : _delete,
    );
  }
}

/// Диалог расхождения: два сохранения, выбирает игрок.
///
/// ## Почему спрашиваем, а не решаем сами
///
/// Расхождение возникает, когда обе стороны продвинулись с последней
/// синхронизации (`rift/core/save/save_sync.dart`). Слить их нельзя: сейв —
/// это не текст, и «объединить два Хранилища» не значит ничего. Значит одно
/// из двух будет перезаписано, и решать, какое, может только тот, кто помнит,
/// во что играл.
///
/// ## Почему сводка, а не дата
///
/// Даты у idle-игры почти всегда близкие: в неё заходят каждый день. «3
/// сентября» против «4 сентября» — это не выбор. «Рекорд 47, 12 спусков»
/// против «рекорд 12, 2 спуска» — выбор.
///
/// Диалог не закрывается мимо кнопок (`barrierDismissible: false`) — это
/// единственное место в игре, где так. Причина: закрытый мимо диалог означал
/// бы «оставить локальный» молча, то есть тихо перезаписать облачный сейв
/// через минуту автосейва.
Future<void> showSyncConflictDialog(
  BuildContext context,
  GameController controller,
) async {
  final pending = controller.pendingSync;
  if (pending == null || !pending.needsPlayer) return;

  final local = pending.decision.local;
  final remote = pending.decision.remote;

  final takeCloud = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(S.syncConflictTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.syncConflictAbout),
          const SizedBox(height: 16),
          _SaveCard(title: S.syncThisPhone, head: local),
          const SizedBox(height: 8),
          _SaveCard(title: S.syncCloud, head: remote),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(S.syncThisPhone),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(S.syncCloud),
        ),
      ],
    ),
  );

  await controller.resolveSync(takeCloud: takeCloud ?? false);
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.title, required this.head});

  final String title;
  final SaveHead? head;

  @override
  Widget build(BuildContext context) {
    final progress = head?.progress ?? const SaveProgress();
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RiftColors.raised,
        borderRadius: BorderRadius.circular(RiftSize.radiusSmall + 2),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: RiftText.heading),
          const SizedBox(height: 4),
          Text(
            S.syncSummary(
              progress.maxDepth,
              progress.runs,
              progress.outpostLevel,
            ),
            style: RiftText.body,
          ),
          if (head != null)
            Text(
              S.syncSeen(_when(head!.lastSeenUtc)),
              style: RiftText.caption,
            ),
        ],
      ),
    );
  }

  /// Местное время, а не UTC: игрок сравнивает с тем, когда он играл, и
  /// «вчера в 23:40» он узнаёт, а «вчера в 20:40 UTC» — нет.
  static String _when(DateTime utc) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:'
        '${two(local.minute)}';
  }
}
