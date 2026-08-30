import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/haul.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/shard.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/forecast.dart';
import 'package:rift/core/sim/rng.dart';

import '../data/content.dart';
import '../data/feedback.dart';
import '../data/notifications.dart';
import '../data/settings_store.dart';
import '../data/save_store.dart';

/// Состояние игры для экранов.
///
/// Всё, что экраны знают об игре, проходит через этот объект: у них нет своей
/// копии профиля и нет права его менять напрямую. Иначе «золото на экране» и
/// «золото в сейве» разъедутся, и заметит это игрок, а не тест.
///
/// Действий ровно столько, сколько шагов в цикле: нанять, отправить, забрать,
/// улучшить. Это и есть игра.
class GameController extends ChangeNotifier {
  GameController({
    required this.content,
    required this.store,
    required PlayerProfile profile,
    DateTime Function()? clock,
    DeathNotifier notifier = const NoDeathNotifier(),
    GameFeedback? feedback,
    SettingsStore? settings,
    AppSettings? initialSettings,
    int? seed,
  })  : _profile = profile,
        _tavernSeed =
            seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
        _clock = clock ?? DateTime.now,
        _notifier = notifier,
        _settingsStore = settings,
        settings = initialSettings ?? AppSettings(),
        feedback = feedback ?? GameFeedback();

  /// Загружает контент и сейв. Новый сейв заводится, только если старого нет.
  static Future<GameController> boot() async {
    final content = await ContentBundle.load();
    content.pack.apply();

    final store = await SaveStore.forApp();
    final saved = await store.load();
    final notifier = await LocalDeathNotifier.create();

    final settingsStore = SettingsStore(store.directory);
    final settings = settingsStore.load();

    final feedback = GameFeedback(
      sound: settings.sound,
      haptics: settings.haptics,
    );
    await feedback.init();

    return GameController(
      content: content,
      store: store,
      notifier: notifier,
      feedback: feedback,
      settings: settingsStore,
      initialSettings: settings,
      profile: saved?.profile ??
          PlayerProfile.newGame(
              seed: DateTime.now().millisecondsSinceEpoch & 0x7fffffff),
    );
  }

  final ContentBundle content;
  final SaveStore store;
  final DeathNotifier _notifier;

  /// Звук и вибрация. Экраны говорят, ЧТО случилось, а не как это озвучить.
  final GameFeedback feedback;

  final SettingsStore? _settingsStore;
  final AppSettings settings;

  /// Переключает звук или вибрацию и сразу записывает выбор: настройка,
  /// которая не пережила перезапуск, — это не настройка.
  void setSound(bool on) {
    settings.sound = on;
    feedback.sound = on;
    _settingsStore?.save(settings);
    notifyListeners();
  }

  void setHaptics(bool on) {
    settings.haptics = on;
    feedback.haptics = on;
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Обучение пройдено или пропущено — второй раз не показывается.
  void finishTutorial() {
    if (settings.tutorialDone) return;
    settings.tutorialDone = true;
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Разрешение спрашивается один раз и после первой гибели, а не на старте.
  bool _askedForNotifications = false;

  final PlayerProfile _profile;
  PlayerProfile get profile => _profile;

  /// Сид для таверны и спусков. Хранится, чтобы обновление списка кандидатов
  /// не выдавало один и тот же набор после перезапуска.
  ///
  /// Задаётся в тестах. Пока он брался только из системных часов, каждый
  /// прогон считал ДРУГОЙ ран: тест на переход между этажами падал раз в
  /// пять запусков, и падение сообщало не о поломке, а о том, что в этот раз
  /// выпал другой бой.
  int _tavernSeed;

  Timer? _timer;
  SaveScheduler? _scheduler;

  /// Контракты, которые закончились с прошлого тика. Экран показывает по ним
  /// «наёмник погиб» и очищает список.
  final List<Contract> justFinished = [];

  /// Часы. Подменяются в тестах: ждать двенадцать реальных минут, чтобы
  /// проверить кнопку «Забрать добычу», — не проверка, а ритуал.
  final DateTime Function() _clock;

  DateTime get now => _clock().toUtc();

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    _scheduler ??= SaveScheduler(
      store: store,
      snapshot: () => SaveData(lastSeenUtc: now, profile: _profile),
    )
      ..start();
    tick();
  }

  /// Останавливает часы и автосейв, не трогая состояние.
  ///
  /// Экран зовёт это, когда уходит: тикать в пустоту незачем, а живой таймер
  /// после снятия экрана — это утечка, которую тесты видят как «pending timer»,
  /// а игрок — как разряженную батарею.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _scheduler?.dispose();
    _scheduler = null;
  }

  @override
  void dispose() {
    stop();
    unawaited(feedback.dispose());
    super.dispose();
  }

  /// Шаг часов: переводит дошедшие до конца контракты в «ждёт получения».
  void tick() {
    final finished = _profile.refreshContracts(now);
    if (finished.isNotEmpty) {
      justFinished.addAll(finished);
      feedback.play(Sfx.death, bump: Bump.heavy);

      // Первая гибель — единственный момент, когда вопрос про уведомления
      // осмыслен: игрок уже понял, что наёмник уходит надолго и возвращается
      // не сам. На первом запуске тот же вопрос — просто помеха.
      if (!_askedForNotifications) {
        _askedForNotifications = true;
        unawaited(_notifier.ensurePermission());
      }
    }
    notifyListeners();
  }

  Future<void> saveNow() => _scheduler?.saveNow() ?? Future<void>.value();

  // --- Действия --------------------------------------------------------------

  void refreshTavern() {
    _profile.refreshTavern(Rng(_tavernSeed));
    _tavernSeed = _tavernSeed * 1664525 + 1013904223 & 0x7fffffff;
    _changed();
  }

  bool hire(Mercenary m) {
    final done = _profile.hire(m);
    if (done) {
      feedback.bump(Bump.light);
      _changed();
    }
    return done;
  }

  /// Отправляет наёмника вниз. Возвращает `null`, если слот спуска занят.
  /// [rift] — отправка в разлом дня: общий для всех сид и модификатор на
  /// каждом этаже. Раз в сутки.
  Contract? deploy(Mercenary m, {bool rift = false}) {
    if (!_profile.canDeploy) return null;
    if (rift && !_profile.riftAvailable(now)) return null;

    final contract = _profile.deploy(
      m,
      rift: rift,
      seed: _tavernSeed ^ m.id.hashCode ^ now.microsecondsSinceEpoch,
      // Часы контроллера, а не системные: иначе контракт живёт по одному
      // времени, а экран считает по другому, и наёмник «погибает» мгновенно.
      now: now,
      forkPolicy: m.forkPolicy,
    );

    feedback.play(Sfx.deploy, bump: Bump.medium);
    _scheduleContractNotice(contract);

    _changed();
    return contract;
  }

  /// Ставит уведомление на конец текущего ОТРЕЗКА спуска.
  ///
  /// Отрезок кончается либо гибелью, либо развилкой, и уведомление нужно в
  /// обоих случаях: гибель зовёт забрать добычу, развилка — принять решение,
  /// пока наёмник ждёт. Пересчитывается при каждом решении, потому что новый
  /// отрезок — это новое время.
  void _scheduleContractNotice(Contract contract) {
    final endsAt = contract.segmentEndsAtUtc;
    if (endsAt == null) return;

    unawaited(_notifier.scheduleContractEvent(
      id: notificationIdFor(contract),
      whenUtc: endsAt,
      mercName: contract.mercenary.name,
      depth: contract.result?.maxDepth ?? 0,
      atFork: contract.result?.awaitingFork ?? false,
    ));
  }

  /// Сколько наёмник ещё простоит на этой развилке, прежде чем решит сам.
  Duration forkWaitLeft(Contract contract, DateTime at) {
    final arrived = contract.forkArrivedAtUtc;
    if (arrived == null) return Duration.zero;
    final waiting =
        at.toUtc().difference(arrived).inMilliseconds / 1000.0;
    final left = Tuning.forkWaitSeconds - waiting;
    return left <= 0 ? Duration.zero : Duration(seconds: left.ceil());
  }

  /// Выбор пути на развилке. Возвращает `false`, если наёмник не ждёт.
  ///
  /// Ради этого метода переписывался спуск: до него игра не спрашивала игрока
  /// ни о чём между отправкой и гибелью — восемь минут без единого решения.
  bool chooseFork(Contract contract, int option) {
    if (!_profile.chooseFork(contract, option, now)) return false;

    feedback.play(Sfx.deploy, bump: Bump.light);
    _scheduleContractNotice(contract);
    _changed();
    return true;
  }

  // --- Разбор добычи ---------------------------------------------------------
  //
  // Три решения игрока над каждой находкой. Тонкие обёртки над профилем:
  // правило живёт в ядре, экран только зовёт и перерисовывается.

  bool keepLoot(Item item) {
    if (!_profile.keepLoot(item)) return false;
    feedback.play(Sfx.deploy, bump: Bump.light);
    _changed();
    return true;
  }

  bool meltLoot(Item item) {
    if (!_profile.meltLoot(item)) return false;
    _changed();
    return true;
  }

  bool sellLoot(Item item) {
    if (!_profile.sellLoot(item)) return false;
    _changed();
    return true;
  }

  /// Разобрать остальное за игрока: лучшее в сундук, прочее в золото.
  void autoSortLoot() {
    if (!_profile.hasPendingLoot) return;
    _profile.autoSortLoot();
    _changed();
  }

  /// Идентификатор уведомления контракта. Выводится из сида, а не из счётчика:
  /// после перезапуска счётчик начался бы заново и отменял чужие уведомления.
  static int notificationIdFor(Contract contract) =>
      contract.seed.abs() % 100000;

  /// Выставляет Клеймо Бездны на следующий спуск (GDD §2.5). Ранг выше
  /// открытого не ставится — открывает его достигнутая глубина.
  bool setBrandRank(int rank) {
    if (!_profile.setBrandRank(rank)) return false;
    _changed();
    return true;
  }

  /// Берёт узел дерева пассивок: общая прокачка за достигнутую глубину.
  bool allocatePassive(String nodeId) {
    final done = _profile.allocatePassive(nodeId);
    if (done) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return done;
  }

  bool refundPassive(String nodeId) {
    final done = _profile.refundPassive(nodeId);
    if (done) {
      feedback.bump(Bump.light);
      _changed();
    }
    return done;
  }

  void resetPassives() {
    _profile.passives.reset();
    feedback.bump(Bump.medium);
    _changed();
  }

  /// Отзывает наёмника: контракт закрывается здесь и сейчас, добыча ждёт
  /// получения. Штрафа нет — см. `PlayerProfile.recall`.
  bool recall(Contract contract) {
    if (!_profile.recall(contract, now)) return false;

    // Уведомление о гибели больше не про что: наёмник возвращается живым.
    unawaited(_notifier.cancel(notificationIdFor(contract)));
    _changed();
    return true;
  }

  /// Что ждёт на ближайших этажах. Глубину обзора даёт Картограф.
  ///
  /// Глубину начала спрашиваем у вызывающего: боевой экран знает её из
  /// повтора, а карточка на Заставе — из формулы по времени. Считать её здесь
  /// значило бы завести третий ответ на вопрос «на каком он этаже», и он
  /// разошёлся бы с заголовком экрана — что и случилось на эмуляторе.
  /// Прогноз этажей вперёд. Считается один раз на глубину и держится в
  /// памяти до следующего этажа.
  ///
  /// Экран боя перестраивается каждый кадр, и без кэша прогноз на восемь
  /// этажей пересчитывался шестьдесят раз в секунду — с раскруткой потоков
  /// случайных чисел на каждый этаж. Это и был один из источников рывков.
  List<FloorOutlook> forecastFrom(Contract contract, int depth) {
    final floors = _profile.outpost.forecastFloors;
    // Решения на развилках входят в ключ: игрок выбрал третий путь — прогноз
    // обязан пересчитаться, иначе он продолжит описывать путь приказа.
    final key = '${contract.seed}:$depth:${contract.forkPolicy.name}:$floors'
        ':${contract.riftDay}:${contract.forkChoices.join(",")}';
    if (_forecastKey == key) return _forecastCache;

    _forecastKey = key;
    return _forecastCache = Forecast.ahead(
      seed: contract.seed,
      fromDepth: depth,
      floors: floors,
      policy: contract.forkPolicy,
      rift: contract.riftModifier,
      choices: contract.forkChoices,
      startDepth: contract.startDepth,
    );
  }

  String? _forecastKey;
  List<FloorOutlook> _forecastCache = const [];

  Haul? collect(Contract contract) {
    if (!contract.awaitingCollection) return null;
    unawaited(_notifier.cancel(notificationIdFor(contract)));
    final haul = _profile.collect(contract);
    feedback.play(Sfx.reward, bump: Bump.medium);
    justFinished.remove(contract);
    _changed();
    return haul;
  }

  // --- Сборка билда ----------------------------------------------------------
  //
  // Всё это доступно только пока наёмник в резерве: лоадаут заперт с момента
  // отправки и до гибели (`docs/03-DECISIONS.md`, раунд 9).

  bool canEdit(Mercenary m) => _profile.roster.reserve.contains(m);

  /// Ставит предмет из сундука в слот. Вытесненное возвращается в сундук.
  bool equip(Mercenary m, int slot, Item item) {
    if (!canEdit(m) || !_profile.stash.remove(item)) return false;

    final displaced = m.gear.equipTo(slot, item);
    if (displaced.length == 1 && identical(displaced.first, item)) {
      // Не подошло — возвращаем на место, чтобы предмет не пропал.
      _profile.stash.add(item);
      return false;
    }
    _profile.stash.addAll(displaced);
    _changed();
    return true;
  }

  bool unequip(Mercenary m, int slot) {
    if (!canEdit(m)) return false;
    final item = m.gear.unequip(slot);
    if (item == null) return false;
    _profile.stash.add(item);
    _changed();
    return true;
  }

  /// Ставит способность в слот. `null` очищает слот.
  bool setAbility(Mercenary m, int slot, String? id) {
    if (!canEdit(m)) return false;

    // Слоты конкретного наёмника: «Оберег молчания» удваивает их под
    // пассивные умения, и экран обязан считать так же, как симуляция.
    final slots = _profile.abilitySlotsFor(m);
    final next = List<String>.from(m.abilities);
    while (next.length < slots) {
      next.add('');
    }
    if (slot < 0 || slot >= slots) return false;

    // Одна и та же способность не может занимать два слота: это не билд,
    // а способ обойти ограничение в четыре слота.
    if (id != null && next.contains(id) && next[slot] != id) return false;

    // Запреты реликтов. Раньше их знала только симуляция: экран позволял
    // выставить четыре активных умения под «Венцом одержимого», показывал их
    // как рабочие, а вниз уходило одно. Число, которому противоречит экран,
    // хуже отсутствующего.
    if (id != null) {
      final def = ContentPack.current.ability(id);
      if (def != null) {
        // Проверяем на сборке БЕЗ этого слота: иначе замена активного умения
        // на другое активное упиралась бы сама в себя.
        final probe = [
          for (var i = 0; i < next.length; i++)
            if (i != slot && next[i].isNotEmpty) next[i],
        ];
        if (_profile.abilityBlockedReason(m, def, loadout: probe) != null) {
          return false;
        }
      }
    }

    next[slot] = id ?? '';
    m.abilities
      ..clear()
      ..addAll(next.where((e) => e.isNotEmpty));
    _changed();
    return true;
  }

  /// Меняет приказ на развилку. Как и лоадаут, доступен только в резерве:
  /// спуск посчитан целиком в момент отправки, и приказ задним числом
  /// переписал бы уже случившийся ран.
  bool setForkPolicy(Mercenary m, ForkPolicy policy) {
    if (!canEdit(m)) return false;
    if (m.forkPolicy == policy) return false;
    m.forkPolicy = policy;
    _changed();
    return true;
  }

  // --- Кузница ---------------------------------------------------------------
  //
  // Крафт — единственное, что не устаревает вместе с предметами (GDD §5.3),
  // поэтому операции над ним живут рядом с остальными действиями игрока,
  // а не прячутся в экране.

  /// Распыляет вещь из сундука в золото. Возвращает полученное или `null`,
  /// если вещи в сундуке уже нет.
  double? salvage(Item item) {
    final gold = _profile.salvage(item);
    if (gold != null) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return gold;
  }

  Shard? extractShard(Item item, int affixIndex) {
    final shard = _profile.extractShard(item, affixIndex);
    if (shard != null) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return shard;
  }

  Item? imprintShard(Item item, Shard shard, {int? slotIndex}) {
    final result = _profile.imprintShard(
      item,
      shard,
      slotIndex: slotIndex,
      rng: Rng(now.microsecondsSinceEpoch),
    );
    if (result != null) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return result;
  }

  Item? rerollAffix(Item item, int affixIndex) {
    final result = _profile.rerollAffix(
      item,
      affixIndex,
      Rng(now.microsecondsSinceEpoch ^ affixIndex),
    );
    if (result != null) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return result;
  }

  Item? deepenRelic(Item item) {
    final result = _profile.deepenRelic(item);
    if (result != null) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return result;
  }

  bool upgrade(Building building) {
    final done = _profile.upgradeBuilding(building);
    if (done) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return done;
  }

  /// Покупает узел древа Эха. Пачкой не покупается: узлы разные, и
  /// «вложить всё» отменило бы единственный выбор, который древо и есть.
  bool buyEchoNode(String nodeId) {
    final done = _profile.buyEchoNode(nodeId);
    if (done) {
      feedback.play(Sfx.reward, bump: Bump.light);
      _changed();
    }
    return done;
  }

  // --- Производные для экранов -----------------------------------------------

  /// Все идущие сейчас спуски. Слотов может быть больше одного, и экран
  /// обязан показывать их все: контракт, которого не видно, — это контракт,
  /// про который забыли.
  /// Наёмники, которые сейчас в бездне: и те, кто идёт, и те, кто стоит на
  /// развилке.
  ///
  /// Стоящий на развилке — тоже активный контракт, и держать его отдельным
  /// списком значило бы, что он пропадает с Заставы ровно в тот момент, когда
  /// он игроку нужнее всего.
  List<Contract> get activeContracts => [
        for (final c in _profile.contracts)
          if (c.descending || c.atFork) c,
      ];

  /// Все спуски, чья добыча ждёт получения.
  List<Contract> get collectableContracts =>
      [for (final c in _profile.contracts) if (c.awaitingCollection) c];

  Contract? get activeContract =>
      activeContracts.isEmpty ? null : activeContracts.first;

  Contract? get collectableContract =>
      collectableContracts.isEmpty ? null : collectableContracts.first;

  /// Хватает ли золота на найм.
  bool canAfford(double cost) => _profile.gold >= cost;

  /// Хватает ли Эха на следующий узел древа. Столбик «сколько узлов сразу»
  /// больше не считается: узлы разные, и покупаются по одному.
  bool get canBuyEchoNode =>
      !_profile.tree.complete && _profile.echo >= _profile.tree.nextNodeCost;

  void _changed() {
    notifyListeners();
    unawaited(saveNow());
  }
}
