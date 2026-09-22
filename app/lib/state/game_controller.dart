import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rift/core/balance/tuning.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/haul.dart';
import 'package:rift/core/model/item.dart';
import 'package:rift/core/model/shard.dart';
import 'package:rift/core/model/mercenary.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_issue.dart';
import 'package:rift/core/save/save_sync.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift/core/sim/fork.dart';
import 'package:rift/core/sim/forecast.dart';
import 'package:rift/core/sim/relay_forecast.dart';
import 'package:rift/core/sim/rng.dart';

import '../data/account_firebase.dart';
import '../data/analytics.dart';
import '../data/analytics_firebase.dart';
import '../data/cloud_save_firestore.dart';
import '../data/cloud_sync.dart';
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
    Analytics? analytics,
    AccountService? account,
    this.mirror,
    int? seed,
  })  : _profile = profile,
        account = account ?? const NoAccountService(),
        _tavernSeed =
            seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
        _clock = clock ?? DateTime.now,
        _notifier = notifier,
        _settingsStore = settings,
        settings = initialSettings ?? AppSettings(),
        // По умолчанию — в никуда. Тесты и дев-экраны поднимают контроллер
        // десятками; каждый из них, разговаривающий с Firebase, испортил бы
        // ту самую статистику, ради которой всё и делается.
        analytics = analytics ?? Analytics(enabled: false),
        feedback = feedback ?? GameFeedback();

  /// Загружает контент и сейв. Новый сейв заводится, только если старого нет.
  ///
  /// ## Порядок здесь не случайный ни в одном месте
  ///
  /// **Настройки → контент.** От языка зависит, какие накладки перевода
  /// накладывать при разборе, а разобрать контент дважды значит показать
  /// первый кадр не на том языке.
  ///
  /// **Аккаунт → облако → сейв.** Сейв ищется по uid, поэтому вход идёт
  /// раньше. И весь этот кусок идёт ДО первого кадра: с первого же кадра
  /// игрок может нажать «отправить», а спуск, начатый в профиле, который
  /// через секунду заменят облачным, — это спуск, которого не было.
  ///
  /// **Ни один отказ здесь не мешает играть.** Нет ключей Firebase, нет Play
  /// Services, нет сети, кончилась квота — всё это ожидаемые исходы, после
  /// каждого из которых игра идёт дальше на локальном сейве. Обратный
  /// порядок означал бы, что игра не запускается в метро.
  static Future<GameController> boot() async {
    final documents = await SaveStore.forApp();
    final settingsStore = SettingsStore(documents.directory);
    final settings = settingsStore.load();
    Lang.current = settings.lang;
    // Идентификатор устройства мог родиться только что — тогда его надо
    // записать сразу. Сейв, выгруженный с устройства, которое при следующем
    // запуске назовётся иначе, выглядит как сейв с другого телефона.
    settingsStore.save(settings);

    final content = await ContentBundle.load(lang: settings.lang);
    content.pack.apply();

    final notifier = await LocalDeathNotifier.create();

    final feedback = GameFeedback(
      sound: settings.sound,
      haptics: settings.haptics,
    );
    await feedback.init();

    // Аналитика поднимается ЗДЕСЬ, после настроек и до первого кадра: с
    // первого же кадра игрок может нажать «отправить», а событие, отправленное
    // в ещё не поднятый сток, теряется молча. Отказ Firebase подняться —
    // штатный исход (см. `AnalyticsSetup`), игра идёт дальше.
    final analytics = await AnalyticsSetup.create(enabled: settings.analytics);

    // Хранилище заводится заново, уже с именем устройства и с жалобами,
    // подключёнными к аналитике. До этого битый сейв и неудачная запись
    // происходили молча — то есть игрок терял прогресс, а мы об этом не
    // узнавали никогда.
    final store = SaveStore(
      documents.directory,
      deviceId: settings.deviceId,
      onTrouble: (kind, stage) => analytics.log(kind == 'recovered'
          ? GameEvents.saveRecovered(stage)
          : GameEvents.saveFailed(stage)),
    );

    // Вход молчаливый и анонимный: экран входа перед первым кадром — это
    // стена ровно там, где игра обещала «открыл и играешь»
    // (`account_firebase.dart`).
    final account = await FirebaseAccountService.create();
    await account.signInSilently();
    store.accountId = account.current.uid;

    final mirror = CloudMirror(
      store: store,
      cloud: await FirestoreCloudSaveStore.create(),
      account: account,
      onEvent: (kind, stage) {
        if (kind == 'error') analytics.log(GameEvents.cloudError(stage));
      },
    );

    final opening = await _openSave(store, mirror, analytics);

    final controller = GameController(
      content: content,
      store: store,
      notifier: notifier,
      feedback: feedback,
      settings: settingsStore,
      initialSettings: settings,
      analytics: analytics,
      account: account,
      mirror: mirror,
      profile: opening.profile,
    )..pendingSync = opening.pending;

    // Разрезы, в которых будет читаться всё остальное, ставятся до первого
    // события: свойство, выставленное позже, не задним числом описывает уже
    // отправленные события.
    controller._syncAnalyticsProfile();

    // Разрешение на уведомления спрашивает ЭКРАН, а не загрузка (см.
    // `askForNotifications`): системный диалог, поднятый здесь, встаёт ровно
    // поверх вступительного окна первого запуска и закрывает ему середину.
    return controller;
  }

  /// Открывает сейв: сводит локальный с облачным и решает, чем играть.
  ///
  /// Единственное место, где решение (`rift/core/save/save_sync.dart`)
  /// превращается в действие. Правило считается в ядре и проверяется
  /// headless; здесь только последствия — забрать облачный, убрать в архив
  /// прошлый сезон, отложить вопрос игроку.
  static Future<_Opening> _openSave(
    SaveStore store,
    CloudMirror mirror,
    Analytics analytics,
  ) async {
    final sync = await mirror.resolveOnBoot();
    analytics.log(GameEvents.saveSync(sync.decision));

    switch (sync.decision.action) {
      // Сейв прошлого сезона. Он не загружается и не удаляется: уезжает в
      // архив под своим именем, и если однажды выяснится, что обнулили не
      // то, вернуть его — это одно переименование (`season.dart`).
      case SyncAction.newSeason:
        final was = sync.decision.local?.seasonId ?? '';
        await store.archiveSeason(was);
        analytics.log(GameEvents.seasonStart(was, Season.current.id));

        // В новом сезоне на этом аккаунте уже может быть сейв — с другого
        // устройства. Второй раз в сеть за ним не ходим: он приехал вместе
        // с решением.
        final remote = sync.remote;
        if (remote != null && Season.isCurrent(remote.head.seasonId)) {
          return _Opening((await mirror.adopt(remote)).profile);
        }
        return _Opening(_newProfile());

      case SyncAction.takeRemote:
        final remote = sync.remote;
        if (remote != null) {
          try {
            return _Opening((await mirror.adopt(remote)).profile);
          } on Object catch (e) {
            // Облачный сейв не открылся. Это не повод остаться без игры:
            // падаем на локальный, каким бы он ни был.
            if (kDebugMode) debugPrint('[save] облачный сейв не читается: $e');
            analytics.log(GameEvents.saveFailed('adopt'));
          }
        }
        return _Opening(await _loadLocal(store, analytics));

      // Расхождение. Профиль берётся локальный — это то, во что игрок играл
      // на этом телефоне, и до его ответа менять это нельзя. Вопрос
      // откладывается до первого кадра: диалог, поднятый отсюда, поднимался
      // бы до того, как есть, поверх чего его рисовать.
      case SyncAction.ask:
        return _Opening(await _loadLocal(store, analytics), pending: sync);

      case SyncAction.keepLocal:
        return _Opening(await _loadLocal(store, analytics));
    }
  }

  /// Читает локальный сейв. Нечитаемый убирается в сторону, а не затирается:
  /// он не открылся СЕГОДНЯШНЕЙ версией игры, и причина может оказаться
  /// нашей ошибкой, которую починят завтра.
  static Future<PlayerProfile> _loadLocal(
      SaveStore store, Analytics analytics) async {
    try {
      final saved = await store.load();
      return saved?.profile ?? _newProfile();
    } on SaveException catch (e) {
      if (kDebugMode) debugPrint('[save] сейв не читается: $e');
      await store.quarantine();
      return _newProfile();
    }
  }

  static PlayerProfile _newProfile() => PlayerProfile.newGame(
      seed: DateTime.now().millisecondsSinceEpoch & 0x7fffffff);

  /// Контент на текущем языке.
  ///
  /// Не `final`: смена языка перезагружает пакет целиком. Экраны читают
  /// контент через контроллер, а не держат свою ссылку, — иначе после
  /// переключения половина игры осталась бы на прежнем языке.
  ContentBundle content;

  final SaveStore store;
  final DeathNotifier _notifier;

  /// Звук и вибрация. Экраны говорят, ЧТО случилось, а не как это озвучить.
  final GameFeedback feedback;

  /// Аналитика. Экраны её не трогают вовсе.
  ///
  /// Событие снимается ЗДЕСЬ, в контроллере, по той же причине, по которой
  /// здесь же лежит профиль: экран может позвать «отправить» из двух разных
  /// мест, и одно из них рано или поздно забудут обвешать счётчиком. Все
  /// действия игры проходят через этот объект — значит и все измерения тоже.
  ///
  /// Ядро при этом ничего не отправляет само: оно только УМЕЕТ построить
  /// событие (`GameEvents`). Симуляция, дёргающая аналитику, перестала бы
  /// быть headless.
  final Analytics analytics;

  /// Кто играет. Экраны спрашивают его только ради подписи в настройках.
  final AccountService account;

  /// Облачное зеркало сейва. `null` — сборка без Firebase: игра идёт целиком,
  /// просто сейв никуда не уезжает.
  final CloudMirror? mirror;

  /// Расхождение, о котором надо спросить игрока.
  ///
  /// Заполняется на загрузке и ждёт первого кадра: диалог требует экрана,
  /// а решение принимается раньше, чем экран существует. `null` — сводить
  /// было нечего или свелось само.
  CloudSyncResult? pendingSync;

  bool get hasPendingSync => pendingSync?.needsPlayer ?? false;

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

  /// Включает или выключает отправку статистики.
  ///
  /// Выключение доходит до самого Firebase, а не только до наших вызовов:
  /// иначе автоматические события SDK продолжали бы уходить, и галочка
  /// выключала бы не то, что подписана выключать.
  void setAnalytics(bool on) {
    settings.analytics = on;
    analytics.enabled = on;
    if (on) _syncAnalyticsProfile();
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Обновляет разрезы игрока. Зовётся там, где меняется то, что в них
  /// входит: рекорд, Клеймо, древо, Застава, язык.
  void _syncAnalyticsProfile() => analytics.setProperties(
        GameEvents.properties(
          _profile,
          lang: settings.lang.code,
          season: Season.current.id,
          account: account.current.analyticsValue,
        ),
      );

  void setHaptics(bool on) {
    settings.haptics = on;
    feedback.haptics = on;
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Переключает язык игры.
  ///
  /// Контент перечитывается целиком, а не подменяется по строчке: имена,
  /// описания и шаблоны аффиксов разбираются вместе с числами, и наложить
  /// перевод на уже разобранный пакет нельзя, не собрав его заново.
  ///
  /// Профиль не трогается вовсе. Сейв хранит идентификаторы — `cleave`,
  /// `max_hp_flat`, — а не показанные слова, поэтому смена языка не меняет
  /// ни одной вещи в сундуке и ни одного узла в дереве. Это и есть причина,
  /// по которой перевод делается накладкой на контент, а не правкой сейва.
  Future<void> setLanguage(Lang lang) async {
    if (lang == settings.lang) return;

    final loaded = await ContentBundle.load(lang: lang);

    // Статик ядра переключается только после успешной загрузки: упади разбор
    // на полпути — игра осталась бы с языком, для которого нет контента.
    Lang.current = lang;
    loaded.pack.apply();
    content = loaded;

    settings.lang = lang;
    _settingsStore?.save(settings);
    analytics.log(GameEvents.languageSet(lang.code));
    _syncAnalyticsProfile();
    notifyListeners();
  }

  /// Обучение пройдено или пропущено — второй раз не показывается.
  ///
  /// [skipped] различает две очень разные вещи: игрок дочитал сценарий до
  /// конца или закрыл его кнопкой. В отчёте это одно событие с разрезом, а
  /// не два счётчика, — потому что интересна доля, а не абсолютные числа.
  void finishTutorial({bool skipped = false}) {
    if (settings.tutorialDone) return;
    settings.tutorialDone = true;
    _settingsStore?.save(settings);
    analytics.log(GameEvents.tutorialDone(skipped: skipped));
    notifyListeners();
  }

  /// Шаги обучения, которые уже показаны или уже опоздали.
  Set<String> get tutorialSeen => settings.tutorialSeen;

  /// Записывает шаги пройденными. Пачкой, потому что за один кадр гасится
  /// сразу несколько опоздавших: игрок, разобравшийся сам, обгоняет сценарий
  /// не на один шаг.
  void markTutorialSeen(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      if (settings.tutorialSeen.add(id)) {
        changed = true;
        // Шаг снимается один раз за игру — множество уже это гарантирует.
        // Воронка первого запуска строится по этим событиям, и повтор в ней
        // выглядел бы как возврат игрока на пройденный шаг.
        analytics.log(GameEvents.tutorialStep(id));
      }
    }
    if (!changed) return;
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Пройти обучение заново.
  ///
  /// Нужно ровно потому, что обучение пропускается одной кнопкой: промахнуться
  /// по ней легко, а вернуть её без этой команды нельзя ничем, кроме сноса
  /// игры. Профиль не трогается — переигрывать спуски не надо, подсказки
  /// сами найдут то место, на котором игрок стоит.
  void restartTutorial() {
    settings.tutorialDone = false;
    settings.tutorialSeen.clear();
    _settingsStore?.save(settings);
    notifyListeners();
  }

  /// Разрешение спрашивается один раз за запуск.
  bool _askedForNotifications = false;

  /// Спрашивает разрешение на уведомления. Зовётся при первой отправке.
  ///
  /// **Не на загрузке, и это проверено на телефоне.** Системный диалог
  /// рисуется поверх игры и появляется через долю секунды после первого
  /// кадра — ровно туда, где на первом запуске стоит вступительное окно.
  /// Игрок читал четыре абзаца о том, как устроена игра, с вырезанной
  /// серединой.
  ///
  /// Момент выбран не «попозже», а по смыслу: наёмник только что ушёл вниз,
  /// и уведомлять теперь есть о чём. Прежнее правило — «спросить на старте» —
  /// боялось не успеть к первой развилке; отправка успевает с запасом,
  /// развилка будет только через несколько этажей.
  ///
  /// Вызов отдельным методом, а не из конструктора: так тесты и дев-экраны
  /// поднимают контроллер, не трогая системный диалог.
  Future<void> askForNotifications() async {
    if (_askedForNotifications) return;
    _askedForNotifications = true;
    final granted = await _notifier.ensurePermission();
    analytics.log(GameEvents.notificationsAnswer(granted: granted));
  }

  /// Профиль игрока.
  ///
  /// Не `final` — по той же причине, что и [content]: его целиком заменяют.
  /// Замена ровно одна и происходит ровно в одном месте — когда игрок в
  /// диалоге расхождения выбрал облачный сейв ([takeCloudSave]). Экраны от
  /// этого не страдают: они читают профиль через геттер на каждой перестройке
  /// и своей копии не держат — свою копию держал бы тот, у кого золото на
  /// экране разъехалось бы с золотом в сейве.
  PlayerProfile _profile;
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
      snapshot: () => SaveData(
        lastSeenUtc: now,
        profile: _profile,
        seasonId: Season.current.id,
      ),
      // Выгрузка в облако решается зеркалом, а не расписанием сейва: файл
      // пишется раз в минуту, а Firestore даёт 20 000 записей в сутки на
      // весь проект (`cloud_sync.dart`). `leaving` — уход в фон, последний
      // момент, когда сейв ещё можно выгрузить: процесс после него снимают
      // без предупреждения.
      onSaved: (saved, {required leaving}) {
        // Уход в фон — последний момент, когда смену ещё можно посчитать
        // вперёд: дальше игра не считает ничего до следующего открытия.
        if (leaving) _scheduleRelayNotice();
        unawaited(mirror?.push(saved, force: leaving) ?? Future<void>.value());
      },
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

  /// Последний тик по настенным часам. По нему считается, сколько прошло
  /// «при игроке»: часы тикают, только пока игра на экране.
  DateTime? _tickedAtUtc;

  /// Насколько большой шаг часов ещё считается непрерывным присутствием.
  ///
  /// Шаг ровно секунда, и три секунды — это запас на подтормаживание кадра.
  /// Всё, что больше, означает, что приложение сворачивали: движок Flutter в
  /// фоне засыпает вместе с таймерами, и проснувшийся тик приносит на себе
  /// весь перерыв. Засчитать его наёмнику значило бы записать ночь в фоне как
  /// ночь при игроке.
  static const _attendedStepCap = Duration(seconds: 3);

  /// Шаг часов: переводит дошедшие до конца контракты в «ждёт получения».
  void tick() {
    // Рекорд запоминается ДО обновления: `refreshContracts` его и поднимает,
    // и спросив после, мы бы сравнивали новый рекорд сам с собой — каждый
    // спуск оказался бы рекордным.
    final recordBefore = _profile.maxDepthEver;

    _countAttendance();

    // Концы отрезков ДО пересчёта: по их смене видно, что наёмник перестал
    // ждать и пошёл дальше сам, — а это новый отрезок и новое время, на
    // которое надо переставить будильник (`_scheduleContractNotice`).
    final segmentsBefore = {
      for (final c in _profile.contracts) c: c.segmentEndsAtUtc,
    };
    final atForkBefore = {
      for (final c in _profile.contracts) if (c.atFork) c,
    };

    final countBefore = _profile.contracts.length;
    final finished = _profile.refreshContracts(now);

    // Сменщики, ушедшие вниз за этот тик: смена дописывает их контракты в
    // конец списка. Прогноз конца смены после этого другой — людей в очереди
    // стало меньше.
    if (_profile.contracts.length > countBefore) {
      for (final contract in _profile.contracts.skip(countBefore)) {
        analytics.log(GameEvents.relayTakeover(contract, _profile));
      }
      _scheduleRelayNotice();
    }

    if (finished.isNotEmpty) {
      justFinished.addAll(finished);
      feedback.play(Sfx.death, bump: Bump.heavy);
      for (final contract in finished) {
        _reportRunEnded(contract, recordBefore: recordBefore);
      }
      _syncAnalyticsProfile();

      // Конец спуска выгружается в облако немедленно, минуя промежуток между
      // выгрузками. Это тот момент, после которого игрок закрывает игру чаще
      // всего: наёмник погиб, добыча ждёт, делать до утра нечего. Отложить
      // выгрузку на пять минут здесь значит регулярно терять в облаке
      // последний спуск.
      unawaited(saveNow(toCloud: true));
    }

    for (final contract in _profile.contracts) {
      if (!contract.descending && !contract.atFork) continue;
      if (segmentsBefore[contract] == contract.segmentEndsAtUtc) continue;
      _scheduleContractNotice(contract);
    }

    if (_profile.contracts
        .any((c) => c.atFork && !atForkBefore.contains(c))) {
      feedback.play(Sfx.fork, bump: Bump.medium);
    }

    notifyListeners();
  }

  /// Засчитывает прошедшую секунду стоящим на развилке — как время с игроком.
  void _countAttendance() {
    final at = now;
    final was = _tickedAtUtc;
    _tickedAtUtc = at;
    if (was == null) return;

    final step = at.difference(was);
    if (step <= Duration.zero || step > _attendedStepCap) return;
    _profile.attendForks(step.inMilliseconds / 1000.0);
  }

  /// Снимает `run_ended` — главное событие игры (`docs/11-ANALYTICS.md` §3).
  ///
  /// Одно место на все три конца спуска: гибель, отзыв, упор в лимит. Разнеси
  /// их по методам — и в отчёте появились бы три несравнимых события вместо
  /// одного с разрезом `ending`, а вопрос «какая доля спусков кончается
  /// отзывом» перестал бы иметь ответ.
  void _reportRunEnded(Contract contract, {required int recordBefore}) {
    final result = contract.result;
    if (result == null) return;

    analytics.log(GameEvents.runEnded(
      contract,
      result,
      _profile,
      record: result.maxDepth > recordBefore,
    ));

    // Предохранители шины сработали в живом спуске. На своих прогонах их
    // ноль, и интересен ровно обратный случай.
    if (result.anomalies > 0) {
      analytics.log(GameEvents.anomaly(contract, result));
    }
  }

  /// Сохраняет немедленно. [toCloud] отменяет промежуток между выгрузками:
  /// так уходит в облако конец спуска — событие, после которого игрок
  /// закрывает игру чаще всего.
  Future<void> saveNow({bool toCloud = false}) =>
      _scheduler?.saveNow(leaving: toCloud) ?? Future<void>.value();

  // --- Аккаунт и облако ------------------------------------------------------

  /// Привязывает аккаунт к Google.
  ///
  /// Единственное место, где игра показывает системный экран, и зовётся оно
  /// только по кнопке в настройках. Возвращает исход как есть: `alreadyInUse`
  /// — это не ошибка, а игрок, который уже играл под этим Google, и разговор
  /// с ним другой (`account.dart`).
  Future<LinkOutcome> linkGoogle() async {
    final outcome = await account.linkGoogle();
    analytics.log(GameEvents.accountLink(outcome.name));

    if (outcome == LinkOutcome.ok || outcome == LinkOutcome.alreadyInUse) {
      store.accountId = account.current.uid;
      mirror?.reset();
      _syncAnalyticsProfile();

      // Вошли в чужой (точнее, в свой второй) аккаунт — значит под ним может
      // лежать другой сейв. Сводим заново тем же правилом, что и на запуске.
      if (outcome == LinkOutcome.alreadyInUse) {
        pendingSync = await mirror?.resolveOnBoot();
        if (pendingSync != null) {
          analytics.log(GameEvents.saveSync(pendingSync!.decision));
        }
      } else {
        // Привязали пустой аккаунт к своему сейву — выгружаем немедленно.
        // Ради этого привязку и нажимали.
        await saveNow(toCloud: true);
      }
    }
    _changed();
    return outcome;
  }

  /// Выходит из аккаунта. Сейв на устройстве остаётся: выход — это не
  /// удаление прогресса, и превращать одно в другое нельзя.
  Future<void> signOutAccount() async {
    await account.signOut();
    store.accountId = null;
    mirror?.reset();
    _syncAnalyticsProfile();
    _changed();
  }

  /// Удаляет аккаунт и всё, что игра о нём хранит, и начинает новую игру.
  ///
  /// Требование Google Play: игрок, который может завести аккаунт, должен
  /// суметь его и удалить — из самой игры (`docs/13-RELEASE.md` §3.3).
  /// Удаляется: облачные сейвы всех сезонов, аккаунт Firebase, сейв на
  /// телефоне с копией и архивами, отложенные уведомления, идентификатор
  /// аналитики. Остаются настройки — язык, звук, — это не данные игрока.
  ///
  /// ## Порядок — от того, что можно отменить, к тому, что нельзя
  ///
  /// 1. **Подтверждение.** Google-аккаунт входит заново; закрытое окно
  ///    оставляет всё как было.
  /// 2. **Облако.** Нет сети — останавливаемся, пока своё цело: удалить
  ///    аккаунт при целом облаке значит оставить сейв без ключа навсегда.
  /// 3. **Аккаунт.**
  /// 4. **Телефон.** Последним: это единственное, что нельзя вернуть, — и
  ///    до этого шага отказ любого из предыдущих оставляет игру играбельной.
  ///
  /// Автосейв стоит на всё время удаления: иначе через минуту он записал бы
  /// старый профиль на диск и выгрузил его в облако заново.
  Future<DeleteOutcome> deleteAccountAndData() async {
    final confirmed = await account.confirmForDeletion();
    if (confirmed != DeleteOutcome.ok) return confirmed;

    final wasRunning = _scheduler != null || _timer != null;
    stop();

    DeleteOutcome fail() {
      if (wasRunning) start();
      return DeleteOutcome.failed;
    }

    final uid = account.current.uid;
    final mirror = this.mirror;
    if (uid != null && uid.isNotEmpty && mirror != null) {
      if (!await mirror.cloud.deleteAll(uid: uid)) return fail();
    }
    if (await account.deleteAccount() != DeleteOutcome.ok) return fail();

    // Уведомления о контрактах, которых больше нет, иначе через час игрок
    // получил бы «наёмник погиб» про наёмника из стёртой игры.
    for (final contract in _profile.contracts) {
      unawaited(_notifier.cancel(notificationIdFor(contract)));
      unawaited(_notifier.cancel(runEndIdFor(contract)));
    }
    unawaited(_notifier.cancel(relayNoticeId));

    await store.deleteEverything();
    store.accountId = null;
    mirror?.reset();
    await analytics.resetData();

    _profile = _newProfile();
    pendingSync = null;
    justFinished.clear();
    // Новая игра — значит и обучение заново: игрок, стёрший всё, начинает с
    // того же, с чего начинал в первый раз.
    restartTutorial();

    // Новый анонимный аккаунт, с прежним не связанный ничем: игра и дальше
    // бережёт прогресс в облаке, но это уже прогресс другого игрока.
    await account.signInSilently();
    store.accountId = account.current.uid;
    _syncAnalyticsProfile();

    if (wasRunning) start();
    _changed();
    return DeleteOutcome.ok;
  }

  /// Ответ игрока на расхождение сейвов.
  ///
  /// [takeCloud] — взять облачный. Локальный при этом не пропадает бесследно:
  /// он становится резервной копией обычным порядком записи
  /// (`SaveStore.save`).
  Future<void> resolveSync({required bool takeCloud}) async {
    final pending = pendingSync;
    pendingSync = null;
    if (pending == null) return;

    analytics.log(GameEvents.saveConflictResolved(
      tookRemote: takeCloud,
      local: pending.decision.local?.progress,
      remote: pending.decision.remote?.progress,
    ));

    final remote = pending.remote;
    if (takeCloud && remote != null) {
      try {
        _profile = (await mirror!.adopt(remote)).profile;
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[save] облачный сейв не читается: $e');
        analytics.log(GameEvents.saveFailed('adopt'));
      }
      _syncAnalyticsProfile();
    } else {
      // Игрок оставил своё — значит облако обязано об этом узнать сейчас, а
      // не через пять минут: до тех пор второе устройство считает хозяином
      // себя, и следующий запуск здесь снова спросил бы то же самое.
      await saveNow(toCloud: true);
    }
    _changed();
  }

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
      analytics.log(GameEvents.mercHired(m.rank.name, _profile));
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

    // Снимается здесь, а не при гибели: сборка заперта на весь контракт, и
    // это единственный момент, когда решение игрока — решение, а не
    // задокументированный итог.
    analytics.log(GameEvents.runStarted(contract, _profile));

    // Разрешение на уведомления спрашивается здесь — в момент, когда оно
    // впервые о чём-то. Не ждём ответа: спуск уже идёт.
    unawaited(askForNotifications());
    _scheduleContractNotice(contract);
    _scheduleRelayNotice();

    _changed();
    return contract;
  }

  /// Ставит уведомления на конец текущего ОТРЕЗКА спуска — и, если отрезок
  /// упирается в развилку, на конец всего спуска заодно.
  ///
  /// Отрезок кончается либо гибелью, либо развилкой, и уведомление нужно в
  /// обоих случаях: гибель зовёт забрать добычу, развилка — принять решение,
  /// пока наёмник ждёт. Пересчитывается при каждом решении, потому что новый
  /// отрезок — это новое время.
  ///
  /// **Почему уведомлений два.** Пока приложение закрыто, игра не считает
  /// ничего: переставить будильник в момент, когда наёмник устал ждать и
  /// пошёл дальше, некому. Одно уведомление на отрезок означало, что игрок,
  /// проспавший развилку, о спуске больше не слышал ничего — наёмник доходил
  /// и погибал в тишине. Поэтому вместе с зовом к развилке ставится и весть
  /// о гибели, посчитанная вперёд по приказу
  /// ([PlayerProfile.projectUnattendedEnd]). Придёт игрок и решит сам —
  /// обе переставятся по факту решения.
  void _scheduleContractNotice(Contract contract) {
    final endsAt = contract.segmentEndsAtUtc;
    if (endsAt == null) return;

    final atFork = contract.result?.awaitingFork ?? false;
    final name = contract.mercenary.name;

    // Смена ждёт — значит гибель этого наёмника не конец: вниз в ту же секунду
    // уйдёт следующий. Весть о каждой гибели будила бы игрока ночью ради того,
    // что случится и без него, поэтому гибели под сменой молчат, а конец всей
    // смены сообщает одно уведомление (`_scheduleRelayNotice`). Зов к развилке
    // остаётся: решать на ней по-прежнему игроку.
    final relieved = _profile.roster.relay.isNotEmpty;

    if (atFork || !relieved) {
      unawaited(_notifier.scheduleContractEvent(
        id: notificationIdFor(contract),
        whenUtc: endsAt,
        mercName: name,
        depth: contract.result?.maxDepth ?? 0,
        atFork: atFork,
        // Зов к развилке живёт ровно столько, сколько наёмник стоит. Дальше он
        // зовёт туда, где никого нет, — и именно это игрок и увидел на пробе:
        // открыл игру по уведомлению, а развилки там уже не было.
        expiresAfter: atFork
            ? Duration(seconds: Tuning.forkWaitAwaySeconds.round())
            : null,
      ));
    } else {
      unawaited(_notifier.cancel(notificationIdFor(contract)));
    }

    final ahead =
        atFork && !relieved ? _profile.projectUnattendedEnd(contract) : null;
    if (ahead == null) {
      // Отрезок последний: вести о гибели, посчитанной вперёд, больше нет —
      // её место занимает уведомление выше, и старая обязана уйти.
      unawaited(_notifier.cancel(runEndIdFor(contract)));
      return;
    }

    unawaited(_notifier.scheduleContractEvent(
      id: runEndIdFor(contract),
      whenUtc: ahead.endsAtUtc,
      mercName: name,
      depth: ahead.depth,
      atFork: false,
    ));
  }

  /// Сколько наёмник ещё простоит на этой развилке, прежде чем решит сам.
  Duration forkWaitLeft(Contract contract, DateTime at) =>
      contract.forkWaitLeftAt(at);

  /// Выбор пути на развилке. Возвращает `false`, если наёмник не ждёт.
  ///
  /// Ради этого метода переписывался спуск: до него игра не спрашивала игрока
  /// ни о чём между отправкой и гибелью — восемь минут без единого решения.
  bool chooseFork(Contract contract, int option) {
    // Снимается ДО выбора: решение продолжает спуск, и `result` после вызова
    // описывает уже следующий отрезок — глубина в нём другая.
    final depth = contract.result?.maxDepth ?? 0;
    final arrived = contract.forkArrivedAtUtc;
    final waited = arrived == null
        ? 0
        : now.difference(arrived).inSeconds;

    if (!_profile.chooseFork(contract, option, now)) return false;

    analytics.log(GameEvents.forkChoice(
      depth: depth,
      option: option,
      byPlayer: true,
      waitedSeconds: waited,
      policy: contract.forkPolicy.name,
    ));

    feedback.play(Sfx.deploy, bump: Bump.light);
    _scheduleContractNotice(contract);
    _scheduleRelayNotice();
    _changed();
    return true;
  }

  // --- Смена (GDD §9.4) ------------------------------------------------------

  /// Идентификатор уведомления о конце смены. Одно на всю игру: смена общая
  /// для всех слотов, и конец у неё один. Вне диапазона контрактов:
  /// [notificationIdFor] и [runEndIdFor] не выходят за 200 000.
  static const relayNoticeId = 300000;

  /// Ставит наёмника из резерва в смену у Костра.
  bool queueRelay(Mercenary m) {
    if (!_profile.queueRelay(m)) return false;
    feedback.bump(Bump.light);
    analytics.log(GameEvents.relayQueued(_profile));
    _rescheduleForRelay();
    _changed();
    return true;
  }

  /// Возвращает сменщика в резерв.
  bool unqueueRelay(Mercenary m) {
    if (!_profile.unqueueRelay(m)) return false;
    feedback.bump(Bump.light);
    _rescheduleForRelay();
    _changed();
    return true;
  }

  /// Смена появилась или опустела — уведомления о гибели идущих вниз
  /// меняются вместе с ней: под сменой они молчат, без неё — возвращаются.
  void _rescheduleForRelay() {
    for (final contract in activeContracts) {
      _scheduleContractNotice(contract);
    }
    _scheduleRelayNotice();
  }

  /// Ставит уведомление на гибель последнего наёмника смены.
  ///
  /// Пока приложение закрыто, переставить будильник в момент, когда сменщик
  /// ушёл вниз, некому, — поэтому вся смена считается вперёд
  /// (`RelayForecast`), и уведомление одно. Пересчитывается всякий раз, когда
  /// меняется то, из чего смена считается: отправка, развилка, отзыв, очередь,
  /// уход сменщика вниз и уход игры в фон.
  void _scheduleRelayNotice() {
    unawaited(_notifier.cancel(relayNoticeId));
    final forecast = RelayForecast.of(_profile);
    if (forecast == null) return;
    unawaited(_notifier.scheduleRelayEnd(
      id: relayNoticeId,
      whenUtc: forecast.endsAtUtc,
      runs: forecast.runs,
      depth: forecast.depth,
    ));
  }

  // --- Разбор добычи ---------------------------------------------------------
  //
  // Три решения игрока над каждой находкой. Тонкие обёртки над профилем:
  // правило живёт в ядре, экран только зовёт и перерисовывается.

  bool keepLoot(Item item) {
    if (!_profile.keepLoot(item)) return false;
    feedback.play(Sfx.deploy, bump: Bump.light);
    _logLoot('keep', item);
    _changed();
    return true;
  }

  bool meltLoot(Item item) {
    if (!_profile.meltLoot(item)) return false;
    _logLoot('melt', item);
    _changed();
    return true;
  }

  bool sellLoot(Item item) {
    if (!_profile.sellLoot(item)) return false;
    _logLoot('sell', item);
    _changed();
    return true;
  }

  /// Разобрать остальное за игрока: лучшее в сундук, прочее в золото.
  void autoSortLoot() {
    if (!_profile.hasPendingLoot) return;

    // Список снимается до разбора: после него `pendingLoot` пуст, и сказать,
    // сколько вещей игрок отдал автомату, будет уже нечем.
    final handed = [..._profile.pendingLoot];
    _profile.autoSortLoot();
    for (final item in handed) {
      _logLoot('auto', item, auto: true);
    }
    _changed();
  }

  void _logLoot(String kind, Item item, {bool auto = false}) =>
      analytics.log(
        GameEvents.lootDecision(kind: kind, ilvl: item.ilvl, auto: auto),
      );

  /// Идентификатор уведомления контракта. Выводится из сида, а не из счётчика:
  /// после перезапуска счётчик начался бы заново и отменял чужие уведомления.
  static int notificationIdFor(Contract contract) =>
      contract.seed.abs() % 100000;

  /// Идентификатор вести о гибели, посчитанной вперёд. Своё число, а не то же
  /// самое: зов к развилке и весть о гибели висят одновременно и говорят
  /// разное, и вторая не имеет права затереть первую.
  static int runEndIdFor(Contract contract) =>
      notificationIdFor(contract) + 100000;

  /// Выставляет Клеймо Бездны на следующий спуск (GDD §2.5). Ранг выше
  /// открытого не ставится — открывает его достигнутая глубина.
  bool setBrandRank(int rank) {
    if (!_profile.setBrandRank(rank)) return false;
    analytics.log(GameEvents.brandRank(_profile.brandRank, _profile));
    _syncAnalyticsProfile();
    _changed();
    return true;
  }

  /// Вызывает стража в логове. `null` — вызов невозможен: причину словами
  /// отдаёт `PlayerProfile.lairBlockedReason`.
  ///
  /// Бой считается сразу, и исход приходит в ответе: экран показывает его,
  /// а не ждёт уведомления — у логова нет пути, только поединок.
  LairChallenge? challengeGuardian(Mercenary m, String guardianId) {
    final challenge = _profile.challengeGuardian(m, guardianId);
    if (challenge == null) return null;

    feedback.play(challenge.fight.won ? Sfx.reward : Sfx.death,
        bump: Bump.medium);
    analytics.log(GameEvents.lairChallenge(challenge, _profile));
    _syncAnalyticsProfile();
    _changed();
    return challenge;
  }

  /// Берёт узел дерева пассивок: общая прокачка за достигнутую глубину.
  bool allocatePassive(String nodeId) {
    final done = _profile.allocatePassive(nodeId);
    if (done) {
      feedback.play(Sfx.buy, bump: Bump.light);
      analytics.log(GameEvents.passiveAlloc(nodeId, _profile));
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
    analytics.log(GameEvents.passiveReset(_profile));
    _changed();
  }

  /// Отзывает наёмника: контракт закрывается здесь и сейчас, добыча ждёт
  /// получения. Штрафа нет — см. `PlayerProfile.recall`.
  bool recall(Contract contract) {
    final recordBefore = _profile.maxDepthEver;
    if (!_profile.recall(contract, now)) return false;

    // Отзыв — такой же конец спуска, как гибель, и снимается тем же событием:
    // «какая доля спусков не дошла до смерти» — вопрос про баланс, а не про
    // интерфейс, и ответить на него можно только если оба конца в одном
    // разрезе (`ending`).
    _reportRunEnded(contract, recordBefore: recordBefore);
    _syncAnalyticsProfile();

    // Уведомление о гибели больше не про что: наёмник возвращается живым.
    // Оба: и зов к развилке, и посчитанная вперёд весть о гибели.
    unawaited(_notifier.cancel(notificationIdFor(contract)));
    unawaited(_notifier.cancel(runEndIdFor(contract)));
    // Отзыв смену не зовёт, а прогноз её конца считал этого наёмника
    // погибшим позже — и со сменщиком следом.
    _scheduleRelayNotice();
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
    unawaited(_notifier.cancel(runEndIdFor(contract)));

    // Сколько добыча пролежала. Снимается до `collect`, потому что дальше
    // контракт закрыт и момент его конца — уже история.
    final endedAt = contract.segmentEndsAtUtc;
    final latency =
        endedAt == null ? 0 : now.difference(endedAt).inSeconds.clamp(0, 1 << 30);

    final haul = _profile.collect(contract);
    analytics.log(GameEvents.haulCollected(haul, latencySeconds: latency));
    // Реликт в добыче звучит своим звуком: самая редкая находка игры не
    // должна узнаваться только из журнала.
    feedback.play(
      haul.items.any((item) => item.isRelic) ? Sfx.relic : Sfx.reward,
      bump: Bump.medium,
    );
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
      feedback.play(Sfx.buy, bump: Bump.light);
      _changed();
    }
    return gold;
  }

  Shard? extractShard(Item item, int affixIndex) {
    final shard = _profile.extractShard(item, affixIndex);
    if (shard != null) {
      feedback.play(Sfx.buy, bump: Bump.light);
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
      feedback.play(Sfx.buy, bump: Bump.light);
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
      feedback.play(Sfx.buy, bump: Bump.light);
      _changed();
    }
    return result;
  }

  Item? deepenRelic(Item item) {
    final result = _profile.deepenRelic(item);
    if (result != null) {
      feedback.play(Sfx.buy, bump: Bump.light);
      _changed();
    }
    return result;
  }

  bool upgrade(Building building) {
    final done = _profile.upgradeBuilding(building);
    if (done) {
      feedback.play(Sfx.buy, bump: Bump.light);
      analytics.log(GameEvents.outpostUpgrade(building, _profile));
      _syncAnalyticsProfile();
      _changed();
    }
    return done;
  }

  /// Покупает узел древа Эха. Пачкой не покупается: узлы разные, и
  /// «вложить всё» отменило бы единственный выбор, который древо и есть.
  bool buyEchoNode(String nodeId) {
    final done = _profile.buyEchoNode(nodeId);
    if (done) {
      feedback.play(Sfx.buy, bump: Bump.light);
      analytics.log(GameEvents.echoNode(nodeId, _profile));
      _syncAnalyticsProfile();
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

  /// Хватает ли Эха на уровень Отзвука глубины (GDD §8.3.1).
  bool get canBuyResonance =>
      _profile.tree.resonanceOpen &&
      _profile.echo >= _profile.tree.resonanceCost;

  /// Покупает уровень Отзвука. [all] — столько, сколько хватает Эха.
  ///
  /// Здесь «вложить всё» можно, а в древе нельзя: узлы древа разные, и кнопка
  /// «всё» отняла бы выбор. У Отзвука выбора нет — только «сколько», а за
  /// ночь смены Эха набегает на десятки уровней.
  bool buyResonance({bool all = false}) {
    var bought = 0;
    while (_profile.buyResonance()) {
      bought++;
      if (!all) break;
    }
    if (bought == 0) return false;
    feedback.play(Sfx.buy, bump: Bump.light);
    analytics.log(GameEvents.echoNode('resonance', _profile));
    _syncAnalyticsProfile();
    _changed();
    return true;
  }

  void _changed() {
    notifyListeners();
    unawaited(saveNow());
  }
}

/// Чем открылся сейв: профиль и, если сейвы разошлись, отложенный вопрос
/// игроку.
///
/// Отдельный тип, а не пара, потому что второе поле легко потерять: `ask`
/// без заданного вопроса — это молча выбранный за игрока сейв.
class _Opening {
  const _Opening(this.profile, {this.pending});

  final PlayerProfile profile;
  final CloudSyncResult? pending;
}
