import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift/core/model/lang.dart';
import 'package:rift/core/model/outpost.dart';
import 'package:rift/core/model/player_profile.dart';
import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/season.dart';
import 'package:rift_app/data/account.dart';
import 'package:rift_app/data/cloud_save.dart';
import 'package:rift_app/data/cloud_sync.dart';
import 'package:rift_app/data/analytics.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/data/settings_store.dart';
import 'package:rift_app/state/game_controller.dart';

/// Проводка аналитики: события снимаются там, где игрок что-то сделал.
///
/// Сама схема проверена в ядре (`test/telemetry_test.dart`) — здесь проверяется
/// ровно то, что ядро проверить не может: что контроллер эти события зовёт.
/// Забытый вызов не ломает ничего видимого, и без теста обнаруживается тем же
/// способом, что и всё остальное в аналитике, — пустой колонкой в отчёте через
/// неделю после релиза.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ContentBundle content;
  late DateTime clock;
  late RecordingAnalyticsSink sink;
  late GameController controller;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  GameController build({bool enabled = true}) {
    sink = RecordingAnalyticsSink();
    return GameController(
      content: content,
      store: SaveStore(dir),
      profile: PlayerProfile.newGame(seed: 1)..gold = 100000,
      clock: () => clock,
      seed: 20260828,
      initialSettings: AppSettings(tutorialDone: true, analytics: enabled),
      analytics: Analytics(sink: sink, enabled: enabled),
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rift_analytics_test');
    clock = DateTime.utc(2026, 6, 1, 12);
    controller = build();
  });

  tearDown(() {
    controller.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Полный круг: отправить, дождаться конца, забрать. Возвращает закрытый
  /// контракт. Часы после него стоят на моменте гибели, а не на месяце
  /// вперёд, — иначе задержка возвращения считалась бы от перемотки.
  Contract finishRun() {
    final merc = controller.profile.roster.reserve.first;
    final contract = controller.deploy(merc)!;

    clock = clock.add(const Duration(days: 30));
    controller.tick();
    clock = contract.segmentEndsAtUtc ?? clock;

    return contract;
  }

  group('петля спуска', () {
    test('отправка снимает run_started со сборкой', () {
      final merc = controller.profile.roster.reserve.first;

      controller.deploy(merc);

      final event = sink.last('run_started');
      expect(event, isNotNull);
      expect(event!.params['fork_policy'], merc.forkPolicy.name);
      expect(event.params['brand_rank'], 0);
    });

    test('гибель снимает run_ended, забор — haul_collected с задержкой', () {
      final contract = finishRun();

      final ended = sink.last('run_ended');
      expect(ended, isNotNull);
      expect(ended!.params['max_depth'], contract.result!.maxDepth);

      // Игрок пришёл за добычей через два часа после гибели. Ради этого числа
      // событие и снимается: «через сколько возвращаются» — главная метрика
      // idle, и взять её больше неоткуда.
      clock = clock.add(const Duration(hours: 2));
      controller.collect(contract);

      final collected = sink.last('haul_collected');
      expect(collected, isNotNull);
      expect(collected!.params['latency_bucket'], '1-6h');
    });

    test('отзыв снимает тот же run_ended, но с другим концом', () {
      // Отдельным событием он был бы несравним с гибелью, и вопрос «какая
      // доля спусков не дошла до смерти» остался бы без ответа.
      final merc = controller.profile.roster.reserve.first;
      final contract = controller.deploy(merc)!;

      clock = clock.add(const Duration(minutes: 2));
      controller.recall(contract);

      expect(sink.last('run_ended')!.params['ending'], 'recalled');
    });
  });

  group('мета-прогресс', () {
    // Уровни Заставы открывает достигнутая глубина, а не золото, поэтому
    // прежде чем строить, надо сходить вниз.
    test('постройка и найм доезжают', () {
      controller.collect(finishRun());

      expect(controller.upgrade(Building.tavern), isTrue);
      expect(sink.last('outpost_upgrade')!.params['building'], 'tavern');

      final candidate = controller.profile.roster.candidates.first;
      controller.hire(candidate);
      expect(sink.last('merc_hired')!.params['merc_rank'], candidate.rank.name);
    });

    test('свойства игрока обновляются вместе с профилем', () {
      controller.collect(finishRun());
      controller.upgrade(Building.tavern);

      expect(sink.properties['outpost_level'], isNotNull);
      expect(sink.properties['depth_bucket'], isNotNull);
      expect(sink.properties['lang'], Lang.ru.code);
      // Сезон и вид аккаунта — разрезы, без которых после первого обнуления
      // отчёт складывает две разные игры в одну кучу.
      expect(sink.properties['season'], Season.current.id);
      expect(sink.properties['account'], 'none');
    });
  });

  // Сейв — единственная подсистема, поломка которой стоит игроку аккаунта, и
  // при этом до сих пор она ломалась МОЛЧА: битый файл, неудачная запись,
  // отвалившееся облако не оставляли следа нигде. Игрок, потерявший час
  // прогресса, не пишет в поддержку — он удаляет игру.
  group('сейв и аккаунт', () {
    test('подъём с резервной копии доезжает до отчёта', () async {
      final store = SaveStore(dir);
      await store.save(SaveData(
          lastSeenUtc: clock, profile: PlayerProfile(gold: 100)));
      await store.save(SaveData(
          lastSeenUtc: clock, profile: PlayerProfile(gold: 200)));
      File('${dir.path}/rift.save.json').writeAsStringSync('{битый');

      final reporting = SaveStore(
        dir,
        onTrouble: (kind, stage) => controller.analytics.log(
            kind == 'recovered'
                ? GameEvents.saveRecovered(stage)
                : GameEvents.saveFailed(stage)),
      );
      await reporting.load();

      expect(sink.last('save_recovered')!.params['stage'], 'primary');
    });

    test('сведение сейвов снимается на каждом запуске, а не только при споре',
        () async {
      // По одним расхождениям нельзя сказать, редки они или часты:
      // знаменателя нет. А знать надо именно долю — `ask` показывает диалог
      // поверх первого кадра.
      final cloud = FakeCloudSaveStore();
      final account = FakeAccountService(uid: 'uid_1');
      await account.signInSilently();

      final store = SaveStore(dir, deviceId: 'phone')
        ..accountId = 'uid_1';
      await store.save(SaveData(
          lastSeenUtc: clock,
          profile: PlayerProfile(gold: 10),
          seasonId: Season.current.id));

      final mirror =
          CloudMirror(store: store, cloud: cloud, account: account);
      controller.analytics
          .log(GameEvents.saveSync((await mirror.resolveOnBoot()).decision));

      final event = sink.last('save_sync')!;
      expect(event.params['action'], 'keepLocal');
      expect(event.params['reason'], 'no_remote');
    });

    test('привязка аккаунта снимается вместе с исходом', () async {
      final account = FakeAccountService(uid: 'uid_1');
      await account.signInSilently();
      controller.dispose();

      sink = RecordingAnalyticsSink();
      controller = GameController(
        content: content,
        store: SaveStore(dir),
        profile: PlayerProfile.newGame(seed: 1),
        clock: () => clock,
        seed: 20260828,
        initialSettings: AppSettings(tutorialDone: true),
        analytics: Analytics(sink: sink),
        account: account,
      );

      await controller.linkGoogle();
      expect(sink.last('account_link')!.params['outcome'], 'ok');
      expect(sink.properties['account'], 'google');
    });

    test('отказ привязки — тоже событие, а не тишина', () async {
      final account = FakeAccountService(uid: 'uid_1')
        ..linkResult = LinkOutcome.alreadyInUse;
      await account.signInSilently();
      controller.dispose();

      sink = RecordingAnalyticsSink();
      controller = GameController(
        content: content,
        store: SaveStore(dir),
        profile: PlayerProfile.newGame(seed: 1),
        clock: () => clock,
        seed: 20260828,
        initialSettings: AppSettings(tutorialDone: true),
        analytics: Analytics(sink: sink),
        account: account,
      );

      await controller.linkGoogle();
      expect(sink.last('account_link')!.params['outcome'], 'alreadyInUse');
    });
  });

  group('выключатель', () {
    test('выключенная аналитика молчит совсем', () {
      controller.dispose();
      controller = build(enabled: false);

      controller.collect(finishRun());
      controller.upgrade(Building.tavern);

      expect(sink.events, isEmpty);
      expect(sink.properties, isEmpty);
    });

    test('выключение доходит до поставщика, а не только до наших вызовов', () {
      // Иначе галочка гасила бы наши события и оставляла автоматические —
      // `session_start`, открытие приложения, — про которые игрок ничего не
      // выключал.
      controller.setAnalytics(false);

      expect(sink.collectionEnabled, isFalse);
      expect(controller.settings.analytics, isFalse);

      controller.deploy(controller.profile.roster.reserve.first);
      expect(sink.named('run_started'), isEmpty);
    });

    test('выбор переживает перезапуск', () {
      final store = SettingsStore(dir);
      store.save(AppSettings(analytics: false));

      expect(store.load().analytics, isFalse);
    });

    test('сейв без поля читается как согласие', () {
      // Файл настроек, написанный версией до аналитики, принадлежит игроку,
      // который об отказе не просил. Обратное правило означало бы, что после
      // обновления молчат все, кто уже играл.
      final file = File('${dir.path}/rift.settings.json')
        ..writeAsStringSync(jsonEncode({'lang': 'ru', 'sound': true}));
      expect(file.existsSync(), isTrue);

      expect(SettingsStore(dir).load().analytics, isTrue);
    });
  });
}
