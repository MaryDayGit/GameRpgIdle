import '../model/build_power.dart';
import '../model/haul.dart';
import '../model/outpost.dart';
import '../model/player_profile.dart';
import '../model/tags.dart';
import '../save/save_head.dart';
import '../save/save_sync.dart';
import '../sim/descent.dart';
import 'analytics_event.dart';

/// Каталог событий игры: единственное место, где домен превращается в
/// измерение.
///
/// ## Зачем каталог, а не `log('run_ended', {...})` по месту
///
/// Схема аналитики — это контракт с будущим собой. Параметр, который в одном
/// вызове зовётся `depth`, а в другом `maxDepth`, разъезжается в отчёте на
/// две колонки, и заметить это можно только через неделю после релиза, когда
/// переписывать данные уже нечем: GA4 не пересобирает историю. Поэтому имена
/// собираются здесь, один раз, и стерегутся тестом.
///
/// ## Почему это в ядре, а не в приложении
///
/// Событие строится из `Contract`, `RunResult`, `PlayerProfile` — то есть из
/// того, что живёт в ядре. Сборщик рядом с данными можно прогнать headless:
/// `test/telemetry_test.dart` гоняет настоящий спуск через `Descent` и
/// проверяет, что `runEnded` донёс глубину и причину гибели. Живой прогон на
/// телефоне такого не покажет — он покажет пустой отчёт через сутки.
///
/// ## Что мы НЕ измеряем
///
/// Ничего, что указывает на человека: ни рекламного идентификатора (он
/// выключен в `AndroidManifest.xml`), ни устройства сверх того, что Firebase
/// собирает сам, ни текста, который игрок ввёл. Всё ниже — состояние ИГРЫ.
/// Причина не только юридическая: персональные данные надо объявлять в Play
/// Data Safety и хранить по правилам, а на вопрос «где игроки упираются в
/// стену» они не отвечают вовсе.
abstract final class GameEvents {
  // --- Петля: спуск ----------------------------------------------------------

  /// Наёмник отправлен вниз.
  ///
  /// Снимается ДО спуска, потому что описывает решение игрока — сборку, ранг
  /// Клейма, приказ на развилку. Всё это заперто до конца контракта
  /// (`03-DECISIONS.md`, раунд 9), значит в паре с `run_ended` даёт честную
  /// связку «что собрал → как далеко ушёл».
  static AnalyticsEvent runStarted(Contract c, PlayerProfile p) =>
      AnalyticsEvent('run_started', {
        'depth_start': c.startDepth,
        'brand_rank': c.brandRank,
        'rift': c.isRift,
        'merc_rank': c.mercenary.rank.name,
        'merc_trait': c.mercenary.trait.name,
        'fork_policy': c.forkPolicy.name,
        'abilities': abilityFingerprint(c.abilities),
        'build_axis': buildAxis(c.abilities),
        'gear_slots': c.mercenary.gear.filledSlots,
        'echo_nodes': c.echoNodes.length,
        'passive_nodes': c.passiveNodes.length,
        'max_depth_ever': p.maxDepthEver,
        'depth_bucket': depthBucket(p.maxDepthEver),
        'gold': p.gold.round(),
        'echo': p.echo,
        'stash': p.stash.length,
      });

  /// Спуск кончился: гибель, отзыв или упор в лимит.
  ///
  /// Главное событие игры. Из него считается всё, ради чего аналитика вообще
  /// ставится: распределение достигнутой глубины, кто убивает, работает ли
  /// Клеймо, растёт ли рекорд от спуска к спуску.
  ///
  /// `record` отмечает спуск, обновивший рекорд. Без него «игра встала» и
  /// «игрок фармит на комфортной глубине» выглядят в отчёте одинаково, а это
  /// две разные болезни с разным лечением.
  static AnalyticsEvent runEnded(
    Contract c,
    RunResult r,
    PlayerProfile p, {
    required bool record,
  }) =>
      AnalyticsEvent('run_ended', {
        'ending': r.ending.name,
        'max_depth': r.maxDepth,
        'depth_bucket': depthBucket(r.maxDepth),
        'depth_start': c.startDepth,
        'floors': r.floors.length,
        'seconds': r.totalSeconds.round(),
        'killed_by': r.killedBy ?? 'none',
        'echo': r.echo,
        'gold': r.gold.round(),
        'items': r.itemsFound,
        'bosses': r.bossesKilled.length,
        'forks': r.forksTaken,
        // Сколько развилок игрок выбрал сам. Остальные достались приказу:
        // `Contract.forkChoices` пополняется только из `chooseFork`, а спуск
        // без решения читает политику (`descent.dart`, «decided»). Доля
        // `forks_player / forks` — прямая проверка ставки игры на то, что за
        // развилкой возвращаются.
        'forks_player': c.forkChoices.length,
        'waited': c.waitedSeconds.round(),
        'brand_rank': c.brandRank,
        'rift': c.isRift,
        'anomalies': r.anomalies,
        'merc_rank': c.mercenary.rank.name,
        'record': record,
        'abilities': abilityFingerprint(c.abilities),
        'build_axis': buildAxis(c.abilities),
        'top_damage': topDamage(r),
        'gear_slots': c.mercenary.gear.filledSlots,
        'max_depth_ever': p.maxDepthEver,
      });

  /// Выбор пути на развилке.
  ///
  /// Ради развилки переписывался спуск: она — единственное решение игрока
  /// между отправкой и гибелью, и ставка игры в том, что за ним возвращаются.
  /// [byPlayer] проверяет ровно эту ставку. Если развилки в основном
  /// достаются приказу, значит окно ожидания короче, чем ритм жизни игрока,
  /// и лечится это `Tuning.forkWaitSeconds`, а не текстом карточки.
  static AnalyticsEvent forkChoice({
    required int depth,
    required int option,
    required bool byPlayer,
    required int waitedSeconds,
    required String policy,
  }) =>
      AnalyticsEvent('fork_choice', {
        'depth': depth,
        'depth_bucket': depthBucket(depth),
        'option': option,
        'by_player': byPlayer,
        'waited': waitedSeconds,
        'policy': policy,
      });

  /// Добыча забрана.
  ///
  /// [latencySeconds] — сколько добыча пролежала между гибелью наёмника и
  /// приходом игрока. Это и есть главная метрика idle: не «сколько играют»,
  /// а «через сколько возвращаются». Она же говорит, работают ли уведомления:
  /// медиана в восемь часов означает, что игрок узнаёт о гибели утром, а не
  /// из шторки.
  static AnalyticsEvent haulCollected(Haul h, {required int latencySeconds}) =>
      AnalyticsEvent('haul_collected', {
        'items': h.itemCount,
        'gold': h.totalGold.round(),
        'shards': h.shards.length,
        'salvaged_gold': h.salvagedGold.round(),
        'best_ilvl': h.bestIlvl,
        'latency': latencySeconds,
        'latency_bucket': latencyBucket(latencySeconds),
      });

  /// Решение над одной находкой: в сундук, в осколок, в золото.
  ///
  /// По одному событию на предмет — дюжина на спуск, и это не много: GA4 не
  /// берёт денег за события, а доля «оставил / переплавил / продал» отвечает
  /// на вопрос, ради которого сундук вообще конечен. Если оставляют всё
  /// подряд, давления нет и Хранилище не нужно; если не оставляют ничего —
  /// добыча не стоит разбора.
  static AnalyticsEvent lootDecision({
    required String kind,
    required int ilvl,
    required bool auto,
  }) =>
      AnalyticsEvent('loot_decision', {
        'kind': kind,
        'ilvl': ilvl,
        'auto': auto,
      });

  // --- Мета-прогресс ---------------------------------------------------------

  static AnalyticsEvent outpostUpgrade(Building b, PlayerProfile p) =>
      AnalyticsEvent('outpost_upgrade', {
        'building': b.name,
        'level': p.outpost.levelOf(b),
        'max_depth_ever': p.maxDepthEver,
        'gold': p.gold.round(),
      });

  static AnalyticsEvent echoNode(String nodeId, PlayerProfile p) =>
      AnalyticsEvent('echo_node', {
        'node': nodeId,
        'bought': p.tree.nodesBought,
        'echo_left': p.echo,
      });

  static AnalyticsEvent passiveAlloc(String nodeId, PlayerProfile p) =>
      AnalyticsEvent('passive_alloc', {
        'node': nodeId,
        'spent': p.passives.spent,
        'points': p.passivePoints,
      });

  static AnalyticsEvent passiveReset(PlayerProfile p) =>
      AnalyticsEvent('passive_reset', {'points': p.passivePoints});

  /// Игрок поднял (или опустил) Клеймо Бездны.
  ///
  /// Добровольная сложность — та часть игры, о которой нельзя догадаться по
  /// внутренним прогонам: балансировщик берёт любой ранг, живой игрок берёт
  /// тот, который решается взять.
  static AnalyticsEvent brandRank(int rank, PlayerProfile p) =>
      AnalyticsEvent('brand_rank', {
        'rank': rank,
        'unlocked': p.brandRankUnlocked,
        'max_depth_ever': p.maxDepthEver,
      });

  /// Игрок вызвал стража в логове.
  ///
  /// Главный вопрос логова — «чем идти», и балансировщик на него не отвечает:
  /// он не надевает Проводников. Поэтому пишется и исход, и запас: страж,
  /// которого берут с 90 % здоровья, и страж, которого берут с 5 %, — разные
  /// стражи, хотя оба «побеждены».
  static AnalyticsEvent lairChallenge(LairChallenge c, PlayerProfile p) =>
      AnalyticsEvent('lair_challenge', {
        'guardian': c.guardian.id,
        'circle': c.circle,
        'won': c.fight.won,
        'first_win': c.firstWin,
        'hp_left': (c.fight.hpLeft * 100).round(),
        'seconds': c.fight.seconds.round(),
        'merc_rank': c.mercenary.rank.name,
        'max_depth_ever': p.maxDepthEver,
        'lair_trophies': p.lairTrophies,
      });

  static AnalyticsEvent mercHired(String rank, PlayerProfile p) =>
      AnalyticsEvent('merc_hired', {
        'merc_rank': rank,
        'reserve': p.roster.reserve.length,
        'gold': p.gold.round(),
      });

  /// Сменщик встал в смену (GDD §9.4). Длина смены против вместимости — то,
  /// по чему видно, пользуются ли ею вообще.
  static AnalyticsEvent relayQueued(PlayerProfile p) =>
      AnalyticsEvent('relay_queued', {
        'queued': p.roster.relay.length,
        'capacity': p.relayCapacity,
        'max_depth_ever': p.maxDepthEver,
      });

  /// Сменщик ушёл вниз вместо павшего. `unattended` — без игрока: ради таких
  /// уходов смена и заведена, и их доля — её главный замер.
  static AnalyticsEvent relayTakeover(Contract c, PlayerProfile p) =>
      AnalyticsEvent('relay_takeover', {
        'merc_rank': c.mercenary.rank.name,
        'unattended': c.forkWaitingSpent,
        'left': p.roster.relay.length,
        'max_depth_ever': p.maxDepthEver,
      });

  // --- Первый запуск и здоровье ---------------------------------------------

  /// Шаг обучения показан. Воронка первого запуска: где именно из неё
  /// выпадают. `first_open` GA4 ставит сам, дальше — наши шаги.
  static AnalyticsEvent tutorialStep(String id) =>
      AnalyticsEvent('tutorial_step', {'step': id});

  static AnalyticsEvent tutorialDone({required bool skipped}) =>
      AnalyticsEvent('tutorial_done', {'skipped': skipped});

  /// Ответ на системный запрос уведомлений.
  ///
  /// Отдельным событием, потому что от него зависит вся петля отсутствия:
  /// игрок, отказавший в уведомлениях, узнаёт о гибели наёмника только когда
  /// сам откроет игру. Если отказов много, «через сколько возвращаются»
  /// придётся читать двумя разными кривыми, а не одной.
  static AnalyticsEvent notificationsAnswer({required bool granted}) =>
      AnalyticsEvent('notifications_answer', {'granted': granted});

  static AnalyticsEvent languageSet(String code) =>
      AnalyticsEvent('language_set', {'lang': code});

  /// Предохранители шины событий сработали в живом спуске.
  ///
  /// `RunResult.anomalies` — признак поломки баланса, а не нормальной работы
  /// (`02-TECH.md` §2.3). На своих прогонах он ноль; интересен ровно тот
  /// случай, когда на телефоне игрока он не ноль. Сид отправляется вместе с
  /// ним: спуск детерминирован, и по сиду поломка воспроизводится дома.
  static AnalyticsEvent anomaly(Contract c, RunResult r) =>
      AnalyticsEvent('anomaly', {
        'count': r.anomalies,
        'depth': r.maxDepth,
        'seed': c.seed,
        'brand_rank': c.brandRank,
        'abilities': abilityFingerprint(c.abilities),
      });

  // --- Сейв, аккаунт, сезон ---------------------------------------------------

  /// Чем кончилось сведение сейва на телефоне с сейвом в облаке.
  ///
  /// Снимается на КАЖДОМ запуске, где есть аккаунт, а не только при
  /// расхождении. Разница принципиальная: по одним расхождениям нельзя
  /// сказать, редки они или часты, — знаменателя нет. А знать надо именно
  /// долю, потому что `ask` — это диалог поверх первого кадра, и если он
  /// показывается чаще, чем раз в сто запусков, значит правило разрешения
  /// (`save/save_sync.dart`) считает расхождением что-то, что им не является.
  ///
  /// [reason] приезжает из самого решения. Синхронизацию нельзя отладить
  /// дома: нужны два устройства, разошедшиеся определённым образом, — и
  /// разрез по ветке решения это единственное, что показывает, какие из них
  /// вообще случаются у живых игроков.
  static AnalyticsEvent saveSync(SyncDecision d) => AnalyticsEvent('save_sync', {
        'action': d.action.name,
        'reason': d.reason,
        'local_depth': d.local?.progress.maxDepth,
        'remote_depth': d.remote?.progress.maxDepth,
        'local_runs': d.local?.progress.runs,
        'remote_runs': d.remote?.progress.runs,
      });

  /// Игрок выбрал в диалоге расхождения.
  ///
  /// Отдельно от [saveSync] потому, что это решение ЧЕЛОВЕКА, а не ветка
  /// кода. Сопоставление «что предлагали — что выбрали» отвечает на вопрос,
  /// который иначе не задать: понятен ли диалог. Игрок, который системно
  /// выбирает вариант беднее, диалог не понял — и лечится это подписями,
  /// а не правилом разрешения.
  static AnalyticsEvent saveConflictResolved({
    required bool tookRemote,
    required SaveProgress? local,
    required SaveProgress? remote,
  }) =>
      AnalyticsEvent('save_conflict', {
        'picked': tookRemote ? 'cloud' : 'local',
        'local_depth': local?.maxDepth,
        'remote_depth': remote?.maxDepth,
        'local_runs': local?.runs,
        'remote_runs': remote?.runs,
      });

  /// Основной файл сейва не прочитался — играем резервной копией.
  ///
  /// Сегодня это происходит МОЛЧА (`SaveStore.load`), и в этом вся проблема:
  /// битый сейв на телефоне игрока — самая дорогая поломка в игре и
  /// единственная, о которой мы не узнаём никак. Игрок, потерявший час
  /// прогресса, не пишет в поддержку — он удаляет игру.
  ///
  /// [stage] говорит, на чём споткнулись: `primary` — основной файл битый,
  /// копия спасла; `both` — не открылись оба, и это уже потеря аккаунта.
  static AnalyticsEvent saveRecovered(String stage) =>
      AnalyticsEvent('save_recovered', {'stage': stage});

  /// Запись сейва не удалась.
  ///
  /// Тоже молчаливая поломка: место на диске кончилось, каталог недоступен,
  /// файл занят. Игра при этом выглядит работающей ровно до перезапуска.
  static AnalyticsEvent saveFailed(String stage) =>
      AnalyticsEvent('save_failed', {'stage': stage});

  /// Облако не ответило.
  ///
  /// [stage] — что именно не получилось: `auth`, `read`, `write`. Разделено
  /// потому, что лечится разным: отказ `auth` у многих означает, что игра
  /// вышла на устройствах без Play Services, а отказ `write` — что кончилась
  /// квота Firestore, и это надо увидеть до того, как перестанет
  /// синхронизироваться у всех.
  static AnalyticsEvent cloudError(String stage) =>
      AnalyticsEvent('cloud_error', {'stage': stage});

  /// Игрок привязал анонимный аккаунт к Google — или не смог.
  ///
  /// Исходы перечислены отдельно, потому что среди них есть один, который
  /// выглядит ошибкой, а является жизнью: `already_in_use` — это игрок,
  /// который уже играл на другом телефоне под тем же Google. Ему нужен не
  /// повтор, а выбор между двумя сейвами, и увидеть, часто ли это
  /// случается, можно только отсюда.
  static AnalyticsEvent accountLink(String outcome) =>
      AnalyticsEvent('account_link', {'outcome': outcome});

  /// Сейв прошлого сезона убран в архив, сезон начат заново.
  ///
  /// Сегодня не отправляется ни разу: сезон один (`save/season.dart`).
  /// Событие заведено вместе с форматом намеренно — первое обнуление
  /// случится у всех игроков сразу и ровно один раз, и не измерить его
  /// нельзя: доля тех, кто после обнуления не вернулся, — это и есть цена
  /// сезонной модели.
  static AnalyticsEvent seasonStart(String from, String to) =>
      AnalyticsEvent('season_start', {'from': from, 'to': to});

  /// Достижение открыто.
  ///
  /// Достижений в игре пока нет — есть место под них в сейве
  /// (`PlayerProfile.achievements`) и это событие. Имя и параметры
  /// фиксируются сейчас, потому что схема GA4 не переписывается задним
  /// числом: событие, отправленное первую неделю с другим именем, останется
  /// в отчёте отдельной колонкой навсегда.
  static AnalyticsEvent achievementUnlocked(String id, PlayerProfile p) =>
      AnalyticsEvent('achievement_unlocked', {
        'achievement': id,
        'total': p.achievements.length,
        'max_depth': p.maxDepthEver,
        'runs': p.quests.runsCompleted,
      });

  // --- Свойства игрока -------------------------------------------------------

  /// Разрезы, в которых читается всё остальное.
  ///
  /// Свойство — не событие: оно описывает игрока и попадает в отчёт по всем
  /// его событиям сразу. Поэтому здесь то, что отвечает на «кто это»
  /// («рекорд 40–49, Клеймо 2, играет по-английски»), а не «что он сделал».
  static Map<String, String> properties(
    PlayerProfile p, {
    required String lang,
    String season = '',
    String account = '',
  }) =>
      {
        'depth_bucket': depthBucket(p.maxDepthEver),
        'brand_rank': '${p.brandRank}',
        'echo_nodes': '${p.tree.nodesBought}',
        'outpost_level': '${totalOutpostLevel(p)}',
        'lang': lang,
        // Сезон — разрез, без которого после первого обнуления весь отчёт
        // становится ложью: спуски нулевого и первого сезона сложатся в одну
        // кучу, и медиана глубины будет считаться по двум разным играм.
        // Ставится с первого дня, пока сезон один: свойство, добавленное
        // позже, не описывает задним числом уже отправленные события.
        if (season.isNotEmpty) 'season': season,
        // Как игрок опознан: `none`, `anon`, `google`. Разрез нужен ради
        // одного вопроса — доходит ли до привязки хоть кто-нибудь. Если
        // `google` близок к нулю, облачный сейв не работает ни для кого, и
        // виноват в этом не Firestore, а кнопка.
        if (account.isNotEmpty) 'account': account,
      };

  // --- Свёртки ---------------------------------------------------------------

  /// Глубина десятками, дальше сотнями: «47» в отчёте — это значение, по
  /// которому нельзя сгруппировать, а «40-49» — можно. Сырое число уезжает
  /// рядом, в `max_depth`: из него считаются медианы, из корзины строятся
  /// разрезы.
  static String depthBucket(int depth) {
    if (depth <= 0) return '0';
    if (depth < 100) {
      final low = depth ~/ 10 * 10;
      return '$low-${low + 9}';
    }
    if (depth < 1000) {
      final low = depth ~/ 100 * 100;
      return '$low-${low + 99}';
    }
    return '1000+';
  }

  /// Задержка возвращения — по порядкам, а не по секундам: разница между
  /// пятью минутами и часом важна, между 3600 и 3700 секундами — нет.
  static String latencyBucket(int seconds) => switch (seconds) {
        < 60 => '<1m',
        < 600 => '1-10m',
        < 3600 => '10-60m',
        < 21600 => '1-6h',
        < 86400 => '6-24h',
        _ => '>24h',
      };

  /// Сборка одной строкой: идентификаторы способностей по алфавиту.
  ///
  /// По алфавиту потому, что порядок слотов игрока не значит ничего для
  /// сравнения сборок, а без сортировки одна и та же четвёрка даёт до 24
  /// разных строк в отчёте.
  static String abilityFingerprint(Iterable<String> abilities) {
    final ids = [...abilities]..sort();
    return ids.join(',');
  }

  /// Ось сборки: оружие или чары (`08-BUILDS.md`). Считается по загруженному
  /// контенту; если контент не поднят — `unknown`, а не падение: аналитика
  /// не имеет права ронять игру.
  static String buildAxis(Iterable<String> abilities) {
    final defs = BuildPower.loadoutOf(abilities);
    if (defs.isEmpty) return 'unknown';
    var spells = 0;
    for (final def in defs) {
      if (def.isSpell) spells++;
    }
    if (spells == 0) return 'weapon';
    if (spells == defs.length) return 'spell';
    return 'hybrid';
  }

  /// Чем спуск бил на самом деле. Не то же, что сборка: пропитка делает
  /// автоатаку стихийной, и «огненный оружейник» в сборке неотличим от
  /// физического, а в уроне — отличим.
  static String topDamage(RunResult r) {
    DamageType? best;
    var top = 0.0;
    r.damageByType.forEach((type, value) {
      if (value > top) {
        top = value;
        best = type;
      }
    });
    return best?.name ?? 'none';
  }

  static int totalOutpostLevel(PlayerProfile p) {
    var sum = 0;
    for (final b in Building.values) {
      sum += p.outpost.levelOf(b);
    }
    return sum;
  }
}
