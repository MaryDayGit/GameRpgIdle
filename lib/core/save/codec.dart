import '../content/content_pack.dart';
import '../model/echo_tree.dart';
import '../model/equipment.dart';
import '../model/gear.dart';
import '../model/haul.dart';
import '../model/item.dart';
import '../model/mercenary.dart';
import '../model/outpost.dart';
import '../model/passive_tree.dart';
import '../model/player_profile.dart';
import '../model/quest_log.dart';
import '../model/shard.dart';
import '../model/stat_key.dart';
import '../model/tags.dart';
import '../sim/descent.dart';
import '../sim/fork.dart';
import 'save_issue.dart';

/// Перевод игрового состояния в JSON и обратно.
///
/// Собран в одном файле, а не размазан методами по моделям, по двум причинам.
/// Первая: формат сейва меняется по своим правилам и версиям, и держать эти
/// правила рядом с миграциями дешевле, чем в двадцати классах. Вторая:
/// загрузка обязана быть СНИСХОДИТЕЛЬНОЙ — сейв должен открыться, даже если
/// контент с тех пор урезали, — а это общая логика, которую не хочется
/// повторять в каждом `fromJson`.
///
/// Правило по перечислениям: в сейв идёт ИМЯ, а не индекс. Перестановка
/// значений в enum не должна превращать «Легенду» в «Оборванца».
class SaveCodec {
  SaveCodec._();

  // --- Профиль ---------------------------------------------------------------

  static Map<String, dynamic> encodeProfile(PlayerProfile p) => {
        'gold': p.gold,
        'echo': p.echo,
        'maxDepthEver': p.maxDepthEver,
        'brandRank': p.brandRank,
        'bestDepthByBrand': {
          for (final e in p.bestDepthByBrand.entries) '${e.key}': e.value,
        },
        // Задания: что закрыто и сколько всего пройдено. Счётчики истории
        // нигде больше не живут — профиль хранит состояние, а не прошлое.
        'quests': {
          'completed': p.quests.completed.toList(),
          'runsCompleted': p.quests.runsCompleted,
          'relicsFound': p.quests.relicsFound,
        },
        'echoNodes': p.tree.bought.toList(),
        'passiveNodes': p.passives.allocated.toList(),
        'outpost': p.outpost.toJson(),
        'roster': encodeRoster(p.roster),
        'stash': [for (final item in p.stash) encodeItem(item)],
        // Добыча, ждущая разбора. Спуск может кончиться ночью, а разбирать
        // его игрок придёт утром — потерять её значило бы потерять ран.
        'pendingLoot': [for (final item in p.pendingLoot) encodeItem(item)],
        // Разлом дня: когда ходили и как глубоко. Без первого он стал бы
        // бесконечным, без второго — безымянным.
        if (p.riftDoneOn != null) 'riftDoneOn': p.riftDoneOn,
        'riftBestDepth': p.riftBestDepth,
        'shards': [for (final shard in p.shards) encodeShard(shard)],
        'contracts': [for (final c in p.contracts) encodeContract(c)],
      };

  static PlayerProfile decodeProfile(
      Map<String, dynamic> j, SaveIssues issues) {
    final roster = decodeRoster(_map(j['roster']), issues, 'roster');

    final profile = PlayerProfile(
      outpost: Outpost.fromJson(_map(j['outpost'])),
      roster: roster,
      tree: EchoTree(bought: _strings(j['echoNodes'])),
      passives: PassiveTree(allocated: _strings(j['passiveNodes'])),
      gold: _double(j['gold']),
      echo: _int(j['echo']),
      maxDepthEver: _int(j['maxDepthEver']),
      brandRank: _int(j['brandRank']),
      // Сейвы до лестницы поля не знают, и это правда: они играли на нулевом
      // ранге, и доказывать им было нечего.
      bestDepthByBrand: _intMap(j['bestDepthByBrand']),
      // Сейвы до заданий журнала не знают, и это правда: у них всё было
      // открыто древом Эха. Пустой журнал вернёт их к стартовому набору —
      // зато цепочки будут проходиться заново и в правильном порядке.
      quests: QuestLog(
        completed: _strings(_map(j['quests'])['completed']),
        runsCompleted: _int(_map(j['quests'])['runsCompleted']),
        relicsFound: _int(_map(j['quests'])['relicsFound']),
      ),
    );

    profile
      ..riftDoneOn = j['riftDoneOn'] == null ? null : _int(j['riftDoneOn'])
      ..riftBestDepth = _int(j['riftBestDepth']);

    for (final raw in _list(j['pendingLoot'])) {
      final item = decodeItem(_map(raw), issues, 'pendingLoot');
      if (item != null) profile.pendingLoot.add(item);
    }

    for (final raw in _list(j['stash'])) {
      final item = decodeItem(_map(raw), issues, 'stash');
      if (item != null) profile.stash.add(item);
    }

    // Наёмник в контракте — тот же объект, что лежит в ростере. Хранить его
    // дважды значило бы получить после загрузки двух разных наёмников с одним
    // именем: снаряжение вернулось бы одному, а погиб бы другой.
    final byId = <String, Mercenary>{
      for (final m in [
        ...roster.candidates,
        ...roster.reserve,
        ...roster.deployed,
        ...roster.fallen,
      ])
        m.id: m,
    };

    for (final raw in _list(j['shards'])) {
      final shard = decodeShard(_map(raw), issues);
      if (shard != null) profile.shards.add(shard);
    }

    for (final raw in _list(j['contracts'])) {
      final contract = decodeContract(_map(raw), byId, issues);
      if (contract != null) profile.contracts.add(contract);
    }

    // Незаконченные спуски пересчитываются из решений: в файле их результата
    // нет намеренно — см. `PlayerProfile.restoreContracts`.
    profile.restoreContracts();

    return profile;
  }

  // --- Ростер ----------------------------------------------------------------

  static Map<String, dynamic> encodeRoster(Roster r) => {
        'activeSlots': r.activeSlots,
        'candidates': [for (final m in r.candidates) encodeMercenary(m)],
        'reserve': [for (final m in r.reserve) encodeMercenary(m)],
        'deployed': [for (final m in r.deployed) encodeMercenary(m)],
        'fallen': [for (final m in r.fallen) encodeMercenary(m)],
      };

  static Roster decodeRoster(
      Map<String, dynamic> j, SaveIssues issues, String path) {
    final roster = Roster(activeSlots: _int(j['activeSlots'], or: 1));

    void fill(List<Mercenary> target, String key) {
      for (final raw in _list(j[key])) {
        final merc = decodeMercenary(_map(raw), issues, '$path.$key');
        if (merc != null) target.add(merc);
      }
    }

    fill(roster.candidates, 'candidates');
    fill(roster.reserve, 'reserve');
    fill(roster.deployed, 'deployed');
    fill(roster.fallen, 'fallen');
    return roster;
  }

  // --- Наёмник ---------------------------------------------------------------

  static Map<String, dynamic> encodeMercenary(Mercenary m) => {
        'id': m.id,
        'name': m.name,
        'rank': m.rank.name,
        'trait': m.trait.name,
        'abilities': m.abilities,
        'gear': encodeEquipment(m.gear),
        'forkPolicy': m.forkPolicy.name,
      };

  static Mercenary? decodeMercenary(
      Map<String, dynamic> j, SaveIssues issues, String path) {
    final rank = _enum(MercRank.values, j['rank']);
    final trait = _enum(MercTrait.values, j['trait']);

    if (rank == null || trait == null) {
      // Ранг и черта определяют статы. Наёмник без них — не наёмник, а строка
      // с именем; тихо подставить «Оборванца» значило бы украсть у игрока
      // «Легенду».
      issues.add(path, 'наёмник «${j['name']}» без ранга или черты — выброшен');
      return null;
    }

    return Mercenary(
      id: _string(j['id']),
      name: _string(j['name']),
      rank: rank,
      trait: trait,
      gear: decodeEquipment(j['gear'], issues, '$path.gear'),
      abilities: _abilities(j['abilities'], issues, path),
      forkPolicy: _enum(ForkPolicy.values, j['forkPolicy']) ?? ForkPolicy.loot,
    );
  }

  /// Способности наёмника. Исчезнувшая из контента просто выпадает из
  /// лоадаута: слот освободится, а наёмник останется.
  static List<String>? _abilities(
      Object? raw, SaveIssues issues, String path) {
    if (raw is! List) return null;

    final out = <String>[];
    for (final id in raw) {
      if (id is! String) continue;
      if (ContentPack.isLoaded && ContentPack.current.ability(id) == null) {
        issues.add('$path.abilities', 'способность «$id» исчезла — снята');
        continue;
      }
      out.add(id);
    }
    return out;
  }

  // --- Снаряжение ------------------------------------------------------------

  static List<dynamic> encodeEquipment(Equipment e) =>
      [for (final item in e.slots) item == null ? null : encodeItem(item)];

  static Equipment decodeEquipment(
      Object? raw, SaveIssues issues, String path) {
    final equipment = Equipment();
    final slots = _list(raw);

    for (var i = 0; i < slots.length && i < Equipment.slotCount; i++) {
      if (slots[i] == null) continue;
      final item = decodeItem(_map(slots[i]), issues, '$path[$i]');
      if (item == null) continue;

      // Предмет обязан попасть в слот СВОЕГО типа: перестановка слотов между
      // версиями иначе положила бы шлем в ботинки.
      if (Equipment.slotKinds[i] != item.kind) {
        issues.add('$path[$i]', 'предмет ${item.kind.name} в чужом слоте');
        continue;
      }
      equipment.equipAt(i, item);
    }
    return equipment;
  }

  // --- Предмет ---------------------------------------------------------------

  static Map<String, dynamic> encodeItem(Item item) => {
        'kind': item.kind.name,
        'ilvl': item.ilvl,
        'rarity': item.rarity.name,
        'twoHanded': item.twoHanded,
        if (item.deepenings > 0) 'deepenings': item.deepenings,
        if (item.bonusAffixSlots > 0) 'bonusSlots': item.bonusAffixSlots,
        if (item.implicit != null) 'implicit': encodeAffix(item.implicit!),
        'affixes': [for (final a in item.affixes) encodeAffix(a)],
        if (item.triggerAffixId != null) 'trigger': item.triggerAffixId,
        if (item.relicId != null) 'relic': item.relicId,
      };

  static Item? decodeItem(
      Map<String, dynamic> j, SaveIssues issues, String path) {
    final kind = _enum(GearKind.values, j['kind']);
    if (kind == null) {
      issues.add(path, 'предмет неизвестного типа «${j['kind']}» — выброшен');
      return null;
    }

    final affixes = <AffixRoll>[];
    for (final raw in _list(j['affixes'])) {
      final roll = decodeAffix(_map(raw), issues, path);
      if (roll != null) affixes.add(roll);
    }

    // Триггер и реликт — ссылки в контент. Если контента больше нет, предмет
    // остаётся: у него есть посчитанные значения аффиксов, и терять его целиком
    // из-за вырезанного эффекта — потеря прогресса из-за правки JSON.
    String? triggerId = _stringOrNull(j['trigger']);
    if (triggerId != null && !_hasTrigger(triggerId)) {
      issues.add(path, 'триггер «$triggerId» исчез из контента — снят');
      triggerId = null;
    }

    final relicId = _stringOrNull(j['relic']);
    final relicDef =
        relicId == null ? null : _relicDef(relicId);
    if (relicId != null && relicDef == null) {
      issues.add(path, 'реликт «$relicId» исчез из контента — снят');
    }

    return Item(
      kind: kind,
      ilvl: _int(j['ilvl']),
      rarity: _enum(Rarity.values, j['rarity']) ?? Rarity.common,
      affixes: affixes,
      implicit: j['implicit'] == null
          ? null
          : decodeAffix(_map(j['implicit']), issues, '$path.implicit'),
      triggerAffixId: triggerId,
      relicId: relicDef == null ? null : relicId,
      relicEffect: relicDef?.effect,
      twoHanded: _bool(j['twoHanded']),
      deepenings: _int(j['deepenings']),
      bonusAffixSlots: _int(j['bonusSlots']),
    );
  }

  // --- Осколок ---------------------------------------------------------------

  static Map<String, dynamic> encodeShard(Shard shard) => {
        'id': shard.affixId,
        'stat': shard.stat.name,
        'percentile': shard.percentile,
        if (shard.tag != null) 'tag': shard.tag!.name,
      };

  static Shard? decodeShard(Map<String, dynamic> j, SaveIssues issues) {
    final stat = _enum(StatKey.values, j['stat']);
    if (stat == null) {
      issues.add('shards', 'осколок на неизвестный стат «${j['stat']}»');
      return null;
    }
    return Shard(
      affixId: _string(j['id']),
      stat: stat,
      percentile: _double(j['percentile']),
      tag: _enum(Tag.values, j['tag']),
    );
  }

  // --- Ролл аффикса ----------------------------------------------------------

  static Map<String, dynamic> encodeAffix(AffixRoll a) => {
        'id': a.affixId,
        'stat': a.stat.name,
        'percentile': a.percentile,
        'value': a.value,
        if (a.tag != null) 'tag': a.tag!.name,
        if (a.rerolls > 0) 'rerolls': a.rerolls,
      };

  static AffixRoll? decodeAffix(
      Map<String, dynamic> j, SaveIssues issues, String path) {
    final stat = _enum(StatKey.values, j['stat']);
    if (stat == null) {
      issues.add(path, 'аффикс на неизвестный стат «${j['stat']}» — выброшен');
      return null;
    }

    // Значение уже посчитано при ролле и лежит в сейве. Поэтому аффикс
    // переживает даже удаление своего определения из контента: описание
    // потеряется, сила — нет.
    return AffixRoll(
      affixId: _string(j['id']),
      stat: stat,
      percentile: _double(j['percentile'], or: 1.0),
      value: _double(j['value']),
      tag: _enum(Tag.values, j['tag']),
      rerolls: _int(j['rerolls']),
    );
  }

  // --- Контракт и результат --------------------------------------------------

  static Map<String, dynamic> encodeContract(Contract c) => {
        'mercenaryId': c.mercenary.id,
        'seed': c.seed,
        'brandRank': c.brandRank,
        'startedAtUtc': c.startedAtUtc.toUtc().toIso8601String(),
        // Ключ остаётся прежним: старые сохранения обязаны читаться. Поле
        // переименовано, потому что сменило смысл (конец ОТРЕЗКА, а не рана),
        // а ключ — часть формата на диске, и его смена сломала бы совместимость.
        if (c.segmentEndsAtUtc != null)
          'endedAtUtc': c.segmentEndsAtUtc!.toUtc().toIso8601String(),
        'state': c.state.name,
        'loadout': encodeEquipment(c.loadout),
        'abilities': c.abilities,
        'echoTreeBonus': c.echoTreeBonus,
        'echoNodes': c.echoNodes,
        'passiveNodes': c.passiveNodes,
        'startDepthBonus': c.startDepthBonus,
        'forkPolicy': c.forkPolicy.name,
        if (c.riftDay != null) 'riftDay': c.riftDay,
        // Решения на развилках и остановки — ЕДИНСТВЕННОЕ, что нужно, чтобы
        // восстановить спуск: он функция от снимка, сида и этого списка.
        // Состояние симуляции не хранится нигде, оно пересчитывается за
        // три-шесть миллисекунд.
        'forkChoices': c.forkChoices,
        'forkWaitingSpent': c.forkWaitingSpent,
        'pauses': [
          for (final pause in c.pauses)
            {
              'at': pause.startUtc.toUtc().toIso8601String(),
              if (pause.seconds != null) 'seconds': pause.seconds,
            },
        ],
        'outpost': {
          'salvageRate': c.outpost.salvageRate,
          'lootQuality': c.outpost.lootQuality,
          'lootQuantity': c.outpost.lootQuantity,
          'restHealBonus': c.outpost.restHealBonus,
        },
        if (c.result != null) 'result': encodeRun(c.result!),
      };

  static Contract? decodeContract(Map<String, dynamic> j,
      Map<String, Mercenary> byId, SaveIssues issues) {
    final id = _string(j['mercenaryId']);
    final merc = byId[id];
    if (merc == null) {
      issues.add('contracts', 'контракт без наёмника «$id» — выброшен');
      return null;
    }

    final contract = Contract(
      mercenary: merc,
      seed: _int(j['seed']),
      brandRank: _int(j['brandRank']),
      startedAtUtc: _time(j['startedAtUtc']) ?? DateTime.now().toUtc(),
      loadout: decodeEquipment(j['loadout'], issues, 'contracts.loadout'),
      abilities: _abilities(j['abilities'], issues, 'contracts'),
      echoTreeBonus: _double(j['echoTreeBonus']),
      echoNodes: _strings(j['echoNodes']),
      passiveNodes: _strings(j['passiveNodes']),
      startDepthBonus: _int(j['startDepthBonus']),
      // Приказ — часть снимка: спуск, посчитанный с одной политикой, нельзя
      // повторять с другой. Отсутствие поля означает сейв до второй версии,
      // где политика была одна.
      forkPolicy: _enum(ForkPolicy.values, j['forkPolicy']) ?? ForkPolicy.loot,
      outpost: _outpostSnapshot(_map(j['outpost'])),
      riftDay: j['riftDay'] == null ? null : _int(j['riftDay']),
    )
      ..state = _enum(ContractState.values, j['state']) ??
          ContractState.awaitingCollection
      ..segmentEndsAtUtc = _time(j['endedAtUtc'])
      ..forkWaitingSpent = j['forkWaitingSpent'] == true;

    // Сейвы до живых развилок их не знают: пустой список означает спуск,
    // целиком решённый приказом, и это ровно то, чем он и был.
    contract.forkChoices.addAll([
      for (final value in _list(j['forkChoices'])) _int(value),
    ]);
    for (final raw in _list(j['pauses'])) {
      final pause = _map(raw);
      final at = _time(pause['at']);
      if (at == null) continue;
      contract.pauses.add(ForkPause(
        at,
        pause['seconds'] == null ? null : _double(pause['seconds']),
      ));
    }

    if (j['result'] != null) {
      contract.result = decodeRun(_map(j['result']), issues);
    }
    return contract;
  }

  static Map<String, dynamic> encodeRun(RunResult r) => {
        'maxDepth': r.maxDepth,
        'ending': r.ending.name,
        'totalSeconds': r.totalSeconds,
        'echo': r.echo,
        'gold': r.gold,
        'itemsFound': r.itemsFound,
        'anomalies': r.anomalies,
        if (r.killedBy != null) 'killedBy': r.killedBy,
        // Ран, лежащий в незакрытом контракте, переживает перезапуск. Задания
        // проверяются при получении добычи — значит и их сырьё обязано
        // доехать до этого момента, а не пропасть вместе с сессией.
        'damageByType': {
          for (final e in r.damageByType.entries) e.key.name: e.value,
        },
        'bossesKilled': r.bossesKilled.toList(),
        'haul': encodeHaul(r.haul),
        'floors': [
          for (final f in r.floors)
            {
              'depth': f.depth,
              'seconds': f.seconds,
              'damageTaken': f.damageTaken,
              'survived': f.survived,
              'itemsFound': f.itemsFound,
              'gold': f.gold,
              'lowestHp': f.lowestHpFraction,
              if (f.modifierId != null) 'modifier': f.modifierId,
            }
        ],
      };

  static RunResult decodeRun(Map<String, dynamic> j, SaveIssues issues) =>
      RunResult(
        maxDepth: _int(j['maxDepth']),
        ending: _enum(RunEnding.values, j['ending']) ?? RunEnding.death,
        totalSeconds: _double(j['totalSeconds']),
        echo: _int(j['echo']),
        gold: _double(j['gold']),
        itemsFound: _int(j['itemsFound']),
        anomalies: _int(j['anomalies']),
        killedBy: _stringOrNull(j['killedBy']),
        damageByType: {
          for (final e in _map(j['damageByType']).entries)
            if (_enum(DamageType.values, e.key) case final type?)
              type: _double(e.value),
        },
        bossesKilled: _strings(j['bossesKilled']).toSet(),
        haul: decodeHaul(_map(j['haul']), issues),
        floors: [
          for (final raw in _list(j['floors']))
            if (raw is Map)
              FloorRecord(
                depth: _int(raw['depth']),
                seconds: _double(raw['seconds']),
                damageTaken: _double(raw['damageTaken']),
                survived: _bool(raw['survived']),
                itemsFound: _int(raw['itemsFound']),
                gold: _double(raw['gold']),
                modifierId: _stringOrNull(raw['modifier']),
                lowestHpFraction: _double(raw['lowestHp'], or: 1.0),
              ),
        ],
      );

  // --- Рюкзак ----------------------------------------------------------------

  static Map<String, dynamic> encodeHaul(Haul h) => {
        'capacity': h.capacity,
        'salvageRate': h.salvageRate,
        'gold': h.gold,
        'shards': [for (final shard in h.shards) encodeShard(shard)],
        'shardsLost': h.shardsLost,
        'relics': h.relics,
        'lockpicks': h.lockpicks,
        'salvagedCount': h.salvagedCount,
        'salvagedGold': h.salvagedGold,
        'collected': h.collected,
        'items': [for (final item in h.items) encodeItem(item)],
      };

  static Haul decodeHaul(Map<String, dynamic> j, SaveIssues issues) {
    final haul = Haul(
      capacity: _int(j['capacity'], or: 12),
      salvageRate: _double(j['salvageRate'], or: 0.35),
    )
      ..gold = _double(j['gold'])
      ..shardsLost = _int(j['shardsLost'])
      ..relics = _int(j['relics'])
      ..lockpicks = _int(j['lockpicks'])
      ..salvagedCount = _int(j['salvagedCount'])
      ..salvagedGold = _double(j['salvagedGold'])
      ..collected = _bool(j['collected']);

    for (final raw in _list(j['shards'])) {
      final shard = decodeShard(_map(raw), issues);
      if (shard != null) haul.shards.add(shard);
    }

    // Напрямую в список, минуя addItem: тот пересортировал бы и заново
    // распылил излишек, начислив золото второй раз при каждой загрузке.
    for (final raw in _list(j['items'])) {
      final item = decodeItem(_map(raw), issues, 'haul');
      if (item != null) haul.items.add(item);
    }
    return haul;
  }

  // --- Мелочи ----------------------------------------------------------------

  static bool _hasTrigger(String id) =>
      ContentPack.isLoaded && ContentPack.current.triggerAffix(id) != null;

  static dynamic _relicDef(String id) =>
      ContentPack.isLoaded ? ContentPack.current.relic(id) : null;

  static Map<String, dynamic> _map(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : const {};

  static List<dynamic> _list(Object? raw) => raw is List ? raw : const [];

  static int _int(Object? raw, {int or = 0}) =>
      raw is num ? raw.toInt() : or;

  /// Карта «ранг → лучшая глубина». Ключи в JSON строковые, и чужое просто
  /// выпадает: сейв с мусором должен открыться, потеряв мусор.
  static Map<int, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <int, int>{};
    for (final entry in raw.entries) {
      final key = int.tryParse('${entry.key}');
      final value = entry.value;
      if (key != null && value is num) out[key] = value.round();
    }
    return out;
  }

  static double _double(Object? raw, {double or = 0.0}) =>
      raw is num ? raw.toDouble() : or;

  /// Вклад Заставы, записанный в контракт. У сейвов до раунда 22 его нет:
  /// тогда спуск считался по Заставе на момент ЧТЕНИЯ, и восстановить, какой
  /// она была при отправке, уже нельзя. Берутся базовые значения — это ближе
  /// к правде, чем сегодняшняя прокачанная Застава.
    static OutpostSnapshot _outpostSnapshot(Map<String, dynamic> j) => OutpostSnapshot(
        salvageRate: _double(j['salvageRate'], or: 0.35),
        lootQuality: _double(j['lootQuality']),
        lootQuantity: _double(j['lootQuantity']),
        restHealBonus: _double(j['restHealBonus']),
      );

  static bool _bool(Object? raw, {bool or = false}) =>
      raw is bool ? raw : or;

  static String _string(Object? raw) => raw is String ? raw : '';

  static String? _stringOrNull(Object? raw) => raw is String ? raw : null;

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

  static T? _enum<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Список строк из сейва. Чужие типы просто выпадают: сейв с мусором в списке
/// узлов должен открыться, потеряв мусор, а не отказаться открываться.
List<String> _strings(Object? raw) => [
      if (raw is List)
        for (final v in raw)
          if (v is String) v,
    ];
