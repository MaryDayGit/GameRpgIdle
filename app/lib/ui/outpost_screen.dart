import 'package:flutter/material.dart';
import 'package:rift/core/sim/daily_rift.dart';
import 'package:rift/core/balance/curves.dart' as balance;
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/content/quest_def.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';

import '../state/game_controller.dart';
import 'echo_tree_screen.dart';
import 'forge_screen.dart';
import 'help_screen.dart';
import 'loot_sort_screen.dart';
import 'fork_card.dart';
import 'format.dart';
import 'battle_screen.dart';
import 'journal_screen.dart';
import 'mercenary_screen.dart';
import 'mercenary_sheet.dart';
import 'passive_tree_screen.dart';
import 'quests_screen.dart';
import 'run_ending_text.dart';
import 'stash_screen.dart';
import 'tutorial.dart';

/// Застава — то место, куда игрок возвращается.
///
/// Весь цикл на одном экране: нанять, отправить, дождаться, забрать, вложить.
/// Разносить эти пять шагов по вкладкам рано — тогда игрок перестаёт видеть
/// связь между «улучшил Оружейную» и «наёмник принёс больше».
class OutpostScreen extends StatefulWidget {
  const OutpostScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<OutpostScreen> createState() => _OutpostScreenState();
}

class _OutpostScreenState extends State<OutpostScreen> {
  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.start();
    if (c.profile.roster.candidates.isEmpty) c.refreshTavern();

    // Вступление показывается после первого кадра: до него нет ни контекста
    // для диалога, ни уверенности, что экран вообще построился.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIntro());
  }

  /// Настройки: звук и вибрация. Два переключателя — всё, что здесь есть,
  /// и большего игре пока не нужно.
  Future<void> _openSettings(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => AnimatedBuilder(
          animation: c,
          builder: (context, _) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: c.settings.sound,
                  onChanged: c.setSound,
                  title: const Text('Звук'),
                  subtitle: const Text('Удары, гибель, находки'),
                ),
                SwitchListTile(
                  value: c.settings.haptics,
                  onChanged: c.setHaptics,
                  title: const Text('Вибрация'),
                  subtitle: const Text('Отдача на действиях и на гибели'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );

  Future<void> _maybeShowIntro() async {
    if (!mounted || c.settings.tutorialDone) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Расселина'),
        // Прокрутка обязательна: четыре абзаца при крупном системном шрифте
        // не помещаются в диалог на невысоком экране, и без неё нижний
        // просто обрезается — вместе с кнопкой.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in Tutorial.intro) ...[
                Text(line, style: const TextStyle(fontSize: 13, height: 1.35)),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );

    if (mounted) c.finishTutorial();
  }

  @override
  void dispose() {
    c.stop();
    super.dispose();
  }

  Future<void> _openJournal(Contract contract) async {
    var lostShards = 0;
    var overflow = 0;
    var closed = const <QuestDef>[];

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JournalScreen(
          contract: contract,
          onCollect: () {
            c.collect(contract);
            lostShards = contract.result?.haul.shardsLost ?? 0;
            overflow = c.profile.lastStashOverflow;
            closed = c.profile.lastClosedQuests;
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    // Разбор добычи — сразу после журнала, пока игрок ещё здесь и помнит,
    // ради чего был спуск. Отложить его на «когда-нибудь» значило бы копить
    // непонятную кучу, в которую игрок не полезет.
    if (c.profile.hasPendingLoot && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LootSortScreen(controller: c),
        ),
      );
    }

    // Награда, о которой не сказали, — награда, которой не было. Умение
    // появляется в списке сборки молча, и заметить его можно только зайдя
    // туда; значит сказать надо здесь, сразу после получения добычи.
    if (closed.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => _QuestsClosedDialog(quests: closed),
      );
    }

    // Верстак полон — часть осколков не доехала. Молча терять ресурс нельзя:
    // игрок не поймёт, почему их меньше, чем обещал журнал, и решит, что
    // считает игра, а не он.
    if (lostShards > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Верстак полон: $lostShards осколков потеряно. '
            'Улучшите Верстак осколков.',
          ),
        ),
      );
    }

    // Сундук полон — часть вещей ушла в переплавку. Игрок отправлял наёмника
    // со своим снаряжением и ждёт его обратно; молча продать это нельзя.
    if (overflow > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'В сундуке не хватило места: '
            '${plural(overflow, "вещь", "вещи", "вещей")} переплавлено '
            'в золото. Поднимите Хранилище.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final profile = c.profile;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Застава'),
            actions: [
              IconButton(
                tooltip: 'Справка',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => openHelp(context),
              ),
              IconButton(
                tooltip: 'Звук и вибрация',
                icon: Icon(
                  c.settings.sound
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                ),
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // Подсказка о следующем шаге. Считается от состояния игры, а не
              // хранится указателем на шаг сценария: игрок, ушедший в Кузницу
              // посреди обучения, вернётся и увидит ту же строку.
              _NextStep(step: Tutorial.stepFor(profile)),

              _Resources(profile: profile),
              const SizedBox(height: 8),
              // Подписанные словом кнопки, а не иконки в шапке. Сундук раньше
              // был только числом в шапке, а Кузница — иконкой с подсказкой:
              // и то и другое игрок не нашёл. Эту ошибку игра уже совершала
              // со «Снаряжением».
              // Пять переходов: сундук, Кузница, задания и два дерева.
              //
              // Раньше три из них жили в заголовке экрана, и на узком
              // телефоне заголовок переполнялся на две сотни точек: русские
              // подписи длиннее английских, а места в панели ровно столько,
              // сколько остаётся от названия. Здесь они помещаются всегда —
              // `Wrap` переносит на вторую строку вместо того, чтобы уехать
              // за край.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Destination(
                    icon: Icons.inventory_2_outlined,
                    label: 'Сундук · ${profile.stash.length}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StashScreen(controller: c),
                      ),
                    ),
                  ),
                  _Destination(
                    icon: Icons.auto_fix_high,
                    label: 'Кузница',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ForgeScreen(controller: c),
                      ),
                    ),
                  ),
                  _Destination(
                    icon: Icons.flag_outlined,
                    label: 'Задания',
                    // Точка зовёт туда, где появился выбор: новая цель,
                    // непотраченное Эхо, неистраченные очки.
                    marked: c.profile.quests.doneCount == 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => QuestsScreen(controller: c),
                      ),
                    ),
                  ),
                  _Destination(
                    icon: Icons.hub_outlined,
                    label: 'Древо Эха',
                    marked: c.canBuyEchoNode,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EchoTreeScreen(controller: c),
                      ),
                    ),
                  ),
                  _Destination(
                    icon: Icons.account_tree_outlined,
                    label: 'Пассивки',
                    marked: c.profile.passivePointsLeft > 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PassiveTreeScreen(controller: c),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DescentCard(controller: c, onCollect: _openJournal),
              const SizedBox(height: 16),
              _RosterSection(controller: c),
              const SizedBox(height: 16),
              _TavernSection(controller: c),
              const SizedBox(height: 16),
              _BuildingsSection(controller: c),
            ],
          ),
        );
      },
    );
  }
}

/// Объяснение раздела — один и тот же лист для всех: игрок учится один раз,
/// где искать «почему».
Future<void> showAbout(BuildContext context, String title, String text) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(
                text,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );

class _Resources extends StatelessWidget {
  const _Resources({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Stat(label: 'Золото', value: money(profile.gold)),
        _Stat(label: 'Эхо', value: '${profile.echo}'),
        _Stat(label: 'Рекорд', value: '${profile.maxDepthEver}'),
        // Осколки — такой же ресурс, как золото и Эхо: они копятся с каждого
        // спуска и упираются в потолок Верстака. Ресурс, которого нет в шапке,
        // игрок не считает своим.
        _Stat(
          label: 'Осколки',
          value: '${profile.shards.length}/${profile.outpost.shardCapacity}',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Состояние бездны: кто там и сколько осталось.
class _DescentCard extends StatelessWidget {
  const _DescentCard({required this.controller, required this.onCollect});

  final GameController controller;
  final void Function(Contract) onCollect;

  void _watch(BuildContext context, Contract contract) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BattleScreen(controller: controller, contract: contract),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Слотов может быть больше одного, и тогда карточек тоже больше одной.
    // Забрать добычу — первым: это то, ради чего игрок вернулся.
    final ready = controller.collectableContracts;
    final active = controller.activeContracts;

    if (ready.isNotEmpty || active.isNotEmpty) {
      // Развилка — первой, впереди даже добычи: наёмник СТОИТ и ждёт, и
      // каждая секунда раздумий тратит бюджет ожидания. Добыча подождёт,
      // она уже никуда не денется.
      final cards = <Widget>[
        for (final contract in active)
          if (contract.atFork) _fork(context, contract),
        for (final contract in ready) _ready(context, contract),
        for (final contract in active)
          if (!contract.atFork) _active(context, contract),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            cards[i],
          ],
        ],
      );
    }

    // Верёвка спущена до доли рекорда, и спуск начинается там. Молча
    // начавшийся с двенадцатого этажа спуск читается как сбой счёта.
    final start = controller.profile.startDepth;

    return _Panel(
      title: 'Бездна пуста',
      about:
          'Наёмник уходит вниз один и идёт, пока не погибнет. Пока он там, '
          'вы не получаете ничего: всё, что он найдёт, вернётся только с ним. '
          'Снаряжение и умения выставляются ДО отправки и заперты до '
          'конца контракта.'
          '\n\n'
          'Спуск начинается не с первого этажа: до трети вашего рекорда '
          'спущена верёвка. Пройденное однажды не надо проходить заново — '
          'там нечего искать и некому сопротивляться.',
      child: Text(
        start > 1
            ? 'Отправьте наёмника вниз. Верёвка спущена до этажа $start.'
            : 'Отправьте наёмника вниз.',
        style: const TextStyle(fontSize: 13, color: Colors.white70),
      ),
    );
  }

  /// Наёмник стоит на развилке и ждёт решения.
  ///
  /// Единственное место в игре, где игрок нужен ВО ВРЕМЯ спуска. До этого
  /// между отправкой и гибелью не происходило ничего, и живой прогон назвал
  /// это «захожу, собираю билд, отправляю и выхожу».
  Widget _fork(BuildContext context, Contract contract) {
    if (contract.pendingFork == null) return const SizedBox.shrink();

    return _Panel(
      title: '${contract.mercenary.name} на развилке',
      about: 'Каждый третий этаж расселина расходится надвое. Выбранный путь '
          'держится до следующей развилки — это не один этаж, а отрезок '
          'спуска. Пока вас нет, наёмник выбирает сам по приказу, но ждёт '
          'не вечно — и третий путь без вас ему недоступен.',
      child: ForkCard(controller: controller, contract: contract),
    );
  }

  Widget _active(BuildContext context, Contract contract) {
    final now = controller.now;
    final depth = contract.currentFloorAt(now);
    final record = controller.profile.maxDepthEver;

    return _Panel(
      title: '${contract.mercenary.name} в бездне',
      about:
          'Снаряжение и умения заперты до конца контракта: наёмник '
          'уже внизу, и переодеть его нельзя. '
          'Отзыв заканчивает спуск '
          'там, где наёмник сейчас. Добыча и Эхо остаются при нём — штрафа '
          'за отзыв нет.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Этаж $depth',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Сколько наёмник УЖЕ внизу, а не сколько ему осталось.
              //
              // Ран посчитан целиком в момент отправки, поэтому «осталось
              // 11 мин» — это не оценка, а дата смерти: игрок знал исход
              // до спуска. Прошедшее время говорит ровно то же про ход
              // спуска и ничего не выдаёт про его конец.
              Text(
                'в бездне ${duration(contract.elapsedAt(now))}',
                style: const TextStyle(fontSize: 13, color: Colors.white60),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Полоса показывает глубину относительно рекорда, а не долю
          // пройденного рана: доля рана — тот же обратный отсчёт, только
          // нарисованный. А рекорд — цель, которую видно.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: record <= 0 ? 0.0 : (depth / record).clamp(0.0, 1.0),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            record <= 0
                ? 'Первый спуск'
                : depth >= record
                    ? 'Новый рекорд глубины'
                    : 'Рекорд: этаж $record',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _watch(context, contract),
            child: const Text('Смотреть бой'),
          ),
          const SizedBox(height: 8),
          // Отзыв стоит рядом с «Смотреть бой», а не прячется внутри боя:
          // застревание в неудачном ране бесит, и выход должен быть на виду
          // (GDD §8).
          TextButton(
            onPressed: () => _confirmRecall(context, contract),
            child: const Text('Отозвать наёмника'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRecall(BuildContext context, Contract contract) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отозвать наёмника?'),
        // Без номера этажа: спуск идёт, пока диалог открыт.
        content: const Text(
          'Спуск закончится там, где наёмник сейчас. Добыча и Эхо остаются '
          'при нём — штрафа за отзыв нет.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Пусть идёт дальше'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (agreed == true) controller.recall(contract);
  }

  Widget _ready(BuildContext context, Contract contract) {
    final result = contract.result!;
    return _Panel(
      title: '${contract.mercenary.name} '
          '${endingRu(result.ending, contract.mercenary.gender)}',
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Этаж ${result.maxDepth}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Добыча ждёт: '
            '${plural(result.haul.itemCount, "предмет", "предмета", "предметов")}, '
            '${money(result.haul.totalGold)} золота, ${result.echo} Эха',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => onCollect(contract),
            child: const Text('Открыть журнал'),
          ),
        ],
      ),
    );
  }
}

class _RosterSection extends StatelessWidget {
  const _RosterSection({required this.controller});

  final GameController controller;

  void _openLoadout(BuildContext context, Mercenary merc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MercenaryScreen(controller: controller, mercenary: merc),
      ),
    );
  }

  void _openCard(BuildContext context, Mercenary merc) {
    final canDeploy = controller.profile.canDeploy;
    showMercenarySheet(
      context,
      merc: merc,
      abilitySlots: controller.profile.abilitySlotsFor(merc),
      profileFor: () => controller.profile.heroProfileFor(merc),
      depth: controller.profile.maxDepthEver < 10
          ? 10
          : controller.profile.maxDepthEver,
      onBuild: () => _openLoadout(context, merc),
      onDeploy: canDeploy ? () => controller.deploy(merc) : null,
      note: canDeploy
          ? null
          : 'Все слоты спуска заняты: '
              '${controller.profile.roster.deployed.length} из '
              '${controller.profile.deploySlots}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reserve = controller.profile.roster.reserve;
    final canDeploy = controller.profile.canDeploy;

    return _Panel(
      title: 'Наёмники (${reserve.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reserve.isEmpty)
            const Text(
              'Никого нет — наймите в Таверне.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            )
          else
            for (final merc in reserve)
              _MercRow(
                merc: merc,
                abilitySlots: controller.profile.abilitySlotsFor(merc),
                action: canDeploy ? 'Отправить' : 'Слоты заняты',
                onTap: canDeploy ? () => controller.deploy(merc) : null,
                onOpen: () => _openCard(context, merc),
                onBuild: () => _openLoadout(context, merc),
              ),

          // Клеймо стоит рядом с «Отправить», потому что это решение перед
          // КАЖДЫМ спуском (GDD §2.5), а не настройка, которую выставили
          // однажды и забыли.
          if (controller.profile.brandRankUnlocked > 0) ...[
            const SizedBox(height: 12),
            _BrandPicker(controller: controller),
          ],

          // Разлом дня — здесь же, рядом с «Отправить»: это не отдельный
          // режим, а вторая кнопка того же решения. Отдельным экраном он
          // превратился бы в место, куда надо не забыть зайти.
          if (reserve.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RiftRow(controller: controller, merc: reserve.first),
          ],
        ],
      ),
    );
  }
}

/// Разлом дня: спуск по общему для всех сегодняшнему расписанию.
///
/// Отвечает на единственный вопрос, которого у игры не было: чем завтра
/// отличается от сегодня. Всё остальное в ней — накопление, а накопление
/// одинаково в любой день.
class _RiftRow extends StatelessWidget {
  const _RiftRow({required this.controller, required this.merc});

  final GameController controller;
  final Mercenary merc;

  @override
  Widget build(BuildContext context) {
    final rift = DailyRift.on(controller.now);
    final available = controller.profile.riftAvailable(controller.now) &&
        controller.profile.canDeploy;
    final best = controller.profile.riftBestDepth;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: available
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок и рекорд — разными строками, а не в один ряд: при
          // крупном системном шрифте «Разлом дня» и «рекорд: этаж 128» на
          // узком экране выдавливали друг друга за край.
          const Text('Разлом дня',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (best > 0)
            Text('Ваш рекорд в разломах: этаж $best',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 4),
          // Модификатор назван до отправки: разлом отличается от обычного
          // спуска ровно им, и узнавать это из журнала было бы поздно.
          Text(
            '${rift.modifier.name} — на каждом этаже, а не между развилками.',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          Text(
            rift.modifier.minus,
            style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
          ),
          Text(
            '${rift.modifier.plus}. Эхо за спуск удваивается',
            style:
                const TextStyle(fontSize: 12, color: Colors.lightGreenAccent),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                available ? () => controller.deploy(merc, rift: true) : null,
            // Без имени: винительный падеж («Отправить Талу Однорукую»)
            // склонением из именительного не получить, а «Отправить Тала
            // Однорукая» — ровно та ошибка, из-за которой в проекте появился
            // `Gender`.
            child: Text(available
                ? 'Отправить в разлом'
                : 'Сегодня разлом уже пройден'),
          ),
        ],
      ),
    );
  }
}

/// Приписка к объяснению Таверны, когда задаток уже начал расти.
const _hireScaleNote =
    ' Задаток растёт с вашим рекордом: чем глубже расселина, тем дороже те, '
    'кто в неё пойдёт. Оборванцы стоят своё всегда.';

class _TavernSection extends StatelessWidget {
  const _TavernSection({required this.controller});

  final GameController controller;

  void _openCard(BuildContext context, Mercenary merc) {
    final cost = controller.profile.hireCostOf(merc);
    final affordable = controller.canAfford(cost);

    showMercenarySheet(
      context,
      merc: merc,
      abilitySlots: controller.profile.abilitySlotsFor(merc),
      profileFor: () => controller.profile.heroProfileFor(merc),
      depth: controller.profile.maxDepthEver < 10
          ? 10
          : controller.profile.maxDepthEver,
      hireLabel: cost <= 0 ? 'Взять даром' : 'Нанять за ${money(cost)}',
      onHire: affordable ? () => controller.hire(merc) : null,
      note: affordable ? null : 'Не хватает золота: нужно ${money(cost)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Список читается у профиля, а не у ростера: доброволец живёт не в пуле
    // кандидатов, и экран, читающий ростер напрямую, его не покажет.
    final candidates = controller.profile.tavernCandidates;
    final volunteer = controller.profile.volunteer;

    final scaled =
        balance.Curves.hireCostScale(controller.profile.maxDepthEver) > 1.0;

    return _Panel(
      title: 'Таверна',
      about:
          'Ранг наёмника поднимает все его характеристики и размер рюкзака. '
          'Таверна сильнее никого не делает — она повышает шансы, что придёт '
          'кто-то хороший.'
          '${scaled ? _hireScaleNote : ""}',
      trailing: TextButton(
        onPressed: controller.refreshTavern,
        child: const Text('Обновить'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Бесплатный наёмник без объяснения читается как поломка цены —
          // но объяснение нужно короткое: это одна строка на весь экран.
          if (volunteer != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Платить нечем — ${volunteer.name} пойдёт даром.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7FB069)),
              ),
            ),
          for (final merc in candidates)
            _MercRow(
              merc: merc,
              action: merc.id == volunteer?.id
                  ? 'даром'
                  : money(controller.profile.hireCostOf(merc)),
              onTap: controller.canAfford(controller.profile.hireCostOf(merc))
                  ? () => controller.hire(merc)
                  : null,
              onOpen: () => _openCard(context, merc),
            ),
        ],
      ),
    );
  }
}

class _MercRow extends StatelessWidget {
  const _MercRow({
    required this.merc,
    required this.action,
    this.abilitySlots = 0,
    this.onTap,
    this.onOpen,
    this.onBuild,
  });

  final Mercenary merc;
  final String action;
  final VoidCallback? onTap;

  /// Открыть карточку с характеристиками.
  final VoidCallback? onOpen;

  /// Открыть сборку билда. У кандидатов в Таверне её нет: сначала наём.
  final VoidCallback? onBuild;

  /// Сколько слотов способностей открыто игроку. Число живёт у профиля —
  /// его поднимает узел древа Эха, — и строка обязана читать его, а не
  /// считать по своему.
  final int abilitySlots;

  Widget _title() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          // Имя переносится, а не выдавливает значок за край: «Сольвейг
          // Долговязая» при крупном системном шрифте длиннее строки, и на
          // узком экране ряд вылезал за границу карточки.
          Flexible(
            child: Text(merc.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (onOpen != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.info_outline, size: 14, color: Colors.white38),
          ],
        ],
      ),
      Text(
        '${merc.rank.forGender(merc.gender)} · '
        '${merc.trait.forGender(merc.gender)} · '
        'рюкзак ${merc.backpackSlots}',
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      if (onBuild != null)
        Text(
          // Обе половины билда одной строкой. Раньше здесь стояло только
          // снаряжение, и про способности игрок не знал: «умений нет, как
          // менять билд — непонятно».
          'Снаряжение ${merc.gear.filledSlots}/${merc.gear.usableSlots} · '
          'умения ${merc.abilities.length}/$abilitySlots',
          style: TextStyle(
            fontSize: 12,
            // Пустые слоты подсвечены: это не украшение, а единственное
            // место, где игрок узнаёт, что снаряжать вообще надо.
            color: merc.gear.filledSlots < merc.gear.usableSlots ||
                    merc.abilities.length < abilitySlots
                ? const Color(0xFFE0A87A)
                : Colors.white38,
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // У наёмника в резерве два действия, и оба обязаны быть подписаны
    // словами. Раньше «Снаряжение» пряталось за иконкой с подсказкой —
    // на телефоне подсказку никто не увидит: её надо удерживать пальцем.
    if (onBuild != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(onTap: onOpen, child: _title()),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onBuild,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    // «Сборка», а не «Снаряжение»: за этой кнопкой и вещи,
                    // и способности, и приказ на развилку — весь билд.
                    label: const Text('Сборка'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(onPressed: onTap, child: Text(action)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(onTap: onOpen, child: _title()),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _BuildingsSection extends StatelessWidget {
  const _BuildingsSection({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final outpost = controller.profile.outpost;

    return _Panel(
      title: 'Постройки',
      about:
          'Застава покупается золотом. Она не делает наёмника сильнее — она '
          'облегчает жизнь вам: сколько '
          'вещей влезет, сколько даёт переплавка лишнего, кто приходит в '
          'Таверну.\n\nУровень открывает достигнутая ГЛУБИНА, а не '
          'кошелёк. Иначе Застава выкупалась бы вперёд прогресса, и дальше '
          'игра шла бы сама.\n\nНажмите на постройку, чтобы увидеть, '
          'что даст следующий уровень.',
      child: Column(
        children: [
          for (final building in Building.values)
            _BuildingRow(
              building: building,
              level: outpost.levelOf(building),
              cost: outpost.upgradeCost(building),
              gate: controller.profile.canUpgradeBuilding(building)
                  ? null
                  : outpost.nextGate(building),
              onUpgrade:
                  controller.profile.canUpgradeBuilding(building) &&
                      controller.canAfford(outpost.upgradeCost(building))
                  ? () => controller.upgrade(building)
                  : null,
              onOpen: () => _openBuilding(context, building),
            ),
        ],
      ),
    );
  }

  /// Карточка постройки: что она делает, что даст следующий уровень, и кнопка.
  ///
  /// Раньше описание постройки стояло строкой под её названием — восемь
  /// описаний подряд на главном экране. Здесь оно к месту: игрок открыл
  /// карточку именно потому, что решает, вкладывать ли.
  Future<void> _openBuilding(BuildContext context, Building building) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final outpost = controller.profile.outpost;
          final level = outpost.levelOf(building);
          final maxed = level >= Building.maxLevel;
          final open = controller.profile.canUpgradeBuilding(building);
          final cost = outpost.upgradeCost(building);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${building.ru} · $level из ${Building.maxLevel}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    building.description,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 14),

                  // Главное в карточке: что изменится. Цена без этого — это
                  // предложение купить кота в мешке.
                  Text(
                    'Сейчас: ${Outpost.effectAt(building, level)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (!maxed) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Станет: ${Outpost.effectAt(building, level + 1)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7FB069),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  if (maxed)
                    const Text(
                      'Предел.',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    )
                  else if (!open)
                    Text(
                      'Следующий уровень откроется, когда наёмник дойдёт до '
                      'этажа ${outpost.nextGate(building)}.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC7643F),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: controller.canAfford(cost)
                          ? () {
                              controller.upgrade(building);
                              Navigator.of(context).pop();
                            }
                          : null,
                      child: Text('Улучшить · ${money(cost)}'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BuildingRow extends StatelessWidget {
  const _BuildingRow({
    required this.building,
    required this.level,
    required this.cost,
    required this.onOpen,
    this.gate,
    this.onUpgrade,
  });

  /// Открыть карточку постройки: описание и «сейчас — станет».
  final VoidCallback onOpen;

  final Building building;
  final int level;
  final double cost;

  /// Глубина, с которой откроется следующий уровень. `null` — уже открыт.
  final int? gate;

  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final maxed = level >= Building.maxLevel;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        building.ru,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$level/${Building.maxLevel}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (gate != null)
                    Text(
                      'откроется с этажа $gate',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFC7643F),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onUpgrade,
              child: Text(
                maxed
                    ? 'Предел'
                    : gate != null
                    ? 'Этаж $gate'
                    : money(cost),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Раздел Заставы.
///
/// У заголовка есть место для ОБЪЯСНЕНИЯ, и оно открывается нажатием. Раньше
/// каждый раздел объяснял себя строкой под заголовком; поодиночке каждая была
/// оправдана, вместе они дали стену текста, в которой терялись числа. Правило
/// теперь одно: на экране состояние и действия, объяснение — в нажатии.
/// Один путь на развилке: что он отнимает и что даёт.
///
/// Минус показывается ПЕРВЫМ и не мельче плюса. Развилка — это размен, и
/// карточка, где плата набрана серым внизу, превращает выбор в «нажми то,
/// где цифра больше».
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.trailing,
    this.accent = false,
    this.about,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool accent;

  /// Текст, который объясняет раздел. Показывается по значку у заголовка.
  final String? about;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: accent
            ? Border.all(color: scheme.primary.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: Colors.white54,
                  ),
                ),
              ),
              if (about != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.white38,
                  ),
                  onPressed: () => showAbout(context, title, about!),
                ),
              if (about != null && trailing != null) const SizedBox(width: 8),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Клеймо Бездны — добровольная сложность (GDD §2.5).
///
/// Показывается, только когда открыт хотя бы первый ранг: пустой рычаг на
/// экране новичка — это вопрос без ответа. До первого открытия про Клеймо
/// говорит строка в журнале спуска, а не постоянный элемент Заставы.
class _BrandPicker extends StatelessWidget {
  const _BrandPicker({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    final unlocked = profile.brandRankUnlocked;
    final next = profile.nextBrandRequirement;
    final rank = profile.brandRank;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Клеймо Бездны',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.info_outline,
                size: 14,
                color: Colors.white24,
              ),
              onPressed: () => showAbout(context, 'Клеймо Бездны', _brandAbout),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Рангов бывает много: список прокручивается, а не сжимается.
            Expanded(
              child: SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i <= unlocked; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _BrandChip(
                          rank: i,
                          selected: i == rank,
                          onTap: () => controller.setBrandRank(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (next != null)
              Expanded(
                child: Text(
                  // Две разные причины, и игрок должен видеть, какая держит
                  // его: не хватает рекорда или не доказан текущий ранг.
                  next.atBrand == null
                      ? 'следующий ранг с этажа ${next.depth}'
                      : 'следующий ранг: этаж ${next.depth} на ранге '
                            '${next.atBrand}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          rank == 0
              ? 'Ранг 0: обычный спуск.'
              : 'Враги +${(balance.Curves.brandMobStatsPerRank * rank * 100).round()} %, '
                    'добыча +${(balance.Curves.brandLootPerRank * rank * 100).round()} %, '
                    'Эхо +${(balance.Curves.brandEchoPerRank * rank * 100).round()} %.',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        if (profile.provenBrandRanks > 0)
          Text(
            'Доказано рангов: ${profile.provenBrandRanks}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF7FB069)),
          ),
      ],
    );
  }
}

/// Объяснение Клейма. Лежит рядом с виджетом, но не на экране: игрок читает
/// его один раз, а числа смотрит каждый спуск.
const _brandAbout =
    'Клеймо — добровольная сложность, которую вы выставляете перед спуском. '
    'Каждый ранг делает врагов крепче, а добычу и Эхо больше.'
    '\n\n'
    'Первые ранги открывает рекорд глубины. Дальше — только делом: чтобы '
    'открыть следующий ранг, надо дойти до нужного этажа НА текущем.'
    '\n\n'
    'Каждый доказанный ранг даёт лишнее очко дерева пассивок сверх его '
    'потолка. Ради этого Клеймо и нужно: когда глубина упрётся в потолок, '
    'расти начнёт сложность — и вопрос сменится с «как глубоко ты зашёл» на '
    '«на каком Клейме ты там держишься».';

class _BrandChip extends StatelessWidget {
  const _BrandChip({
    required this.rank,
    required this.selected,
    required this.onTap,
  });

  final int rank;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 34,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFC7643F).withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? const Color(0xFFC7643F)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? const Color(0xFFE0A87A) : Colors.white54,
        ),
      ),
    ),
  );
}

/// Подсказка о следующем шаге. Не модальная и не блокирующая: игрок, который
/// знает, что делает, просто проходит мимо неё.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.step});

  final TutorialStep? step;

  @override
  Widget build(BuildContext context) {
    final current = step;
    if (current == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFC7643F).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFC7643F).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              current.text,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Задание выполнено» — сразу после получения добычи.
///
/// Отдельным окном, а не строкой в журнале: открытие нового умения — это
/// событие, ради которого задания и существуют. Строка внизу списка добычи
/// прошла бы мимо глаз ровно так же, как проходило открытие пачкой.
class _QuestsClosedDialog extends StatelessWidget {
  const _QuestsClosedDialog({required this.quests});

  final List<QuestDef> quests;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(quests.length == 1
          ? 'Задание выполнено'
          : 'Заданий выполнено: ${quests.length}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final quest in quests) ...[
            Text(quest.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              'Открыто умение: '
              '${ContentPack.current.ability(quest.rewardAbility)?.name ?? "?"}'
              '${quest.rewardEcho > 0 ? ' · +${quest.rewardEcho} Эха' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            quests.length == 1
                ? 'Поставить его в слот можно в сборке наёмника.'
                : 'Поставить их в слоты можно в сборке наёмника.',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Хорошо'),
        ),
      ],
    );
  }
}

/// Кнопка перехода на другой экран.
///
/// Своя, а не `OutlinedButton.icon`, ровно ради одного свойства: она ужимается
/// по содержимому и живёт в `Wrap`. Пять переходов с русскими подписями в один
/// ряд не влезают ни на одном телефоне, а перенос строки — единственный
/// способ не обрезать их в «…».
class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.marked = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Точка: там появился выбор, который игрок ещё не сделал.
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
          if (marked) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
