import 'save_issue.dart';

/// Одна ступень цепочки миграций: сейв версии [from] превращается в [from] + 1.
class SaveMigration {
  const SaveMigration(this.from, this.apply);

  final int from;

  /// Меняет сырой JSON на месте или возвращает новый.
  final Map<String, dynamic> Function(Map<String, dynamic> raw) apply;
}

/// Цепочка миграций сейва.
///
/// Заводится с первого дня, а не «когда понадобится» (`docs/02-TECH.md` §4).
/// Причина простая: первая же миграция, придуманная задним числом, приходит
/// вместе с уже существующими сейвами у игроков — и делать её приходится
/// в спешке и вслепую. Пустая цепочка стоит ничего, отсутствующая — аккаунтов.
class SaveMigrations {
  const SaveMigrations([this.steps = _defaults]);

  /// Реальная цепочка.
  static const List<SaveMigration> _defaults = [
    SaveMigration(1, _addForkPolicy),
    SaveMigration(2, _namedEchoNodes),
    SaveMigration(3, _accountAndSeason),
    SaveMigration(4, _recentDepths),
    SaveMigration(5, _lairs),
    SaveMigration(6, _relayAndResonance),
  ];

  final List<SaveMigration> steps;

  /// Поднимает сейв до [target]. Ступени применяются строго по одной:
  /// прыжок «из версии 1 сразу в 5» — это пять непроверенных переходов,
  /// свёрнутых в один непроверяемый.
  Map<String, dynamic> upgrade(
    Map<String, dynamic> raw, {
    required int from,
    required int target,
    SaveIssues? issues,
  }) {
    if (from > target) {
      throw SaveException(
          'сейв версии $from новее поддерживаемой $target — обновите игру');
    }

    var current = raw;
    for (var version = from; version < target; version++) {
      final step = _stepFrom(version);
      if (step == null) {
        throw SaveException(
            'нет миграции с версии $version — цепочка разорвана');
      }
      current = step.apply(current);
      issues?.add('save', 'миграция $version -> ${version + 1}');
    }
    return current;
  }

  SaveMigration? _stepFrom(int version) {
    for (final step in steps) {
      if (step.from == version) return step;
    }
    return null;
  }
}

/// 1 → 2: у контракта появился приказ на развилку.
///
/// Проставляется явно, а не оставляется на умолчание читателя: сейв должен
/// говорить, ЧТО было, а не полагаться на то, что умолчание никогда не
/// поменяется. Первый же спуск, посчитанный с одной политикой и повторённый
/// с другой, показал бы игроку бой, которого не было.
Map<String, dynamic> _addForkPolicy(Map<String, dynamic> raw) {
  final profile = raw['profile'];
  if (profile is! Map) return raw;

  final contracts = profile['contracts'];
  if (contracts is! List) return raw;

  for (final contract in contracts) {
    if (contract is Map && contract['forkPolicy'] == null) {
      contract['forkPolicy'] = 'loot';
    }
  }
  return raw;
}

/// 2 → 3: древо Эха стало именованным (GDD §8.3).
///
/// До этого древо было счётчиком одинаковых узлов «+8 % силы». Купленное
/// нельзя ни сохранить как есть, ни отобрать молча, поэтому счётчик
/// превращается в первые N узлов в каноническом порядке: столько же вложений,
/// та же цена следующего узла. Сила при этом изменится — узлы теперь дают
/// конкретные статы, и честнее это, чем оставить в сейве число, за которым
/// больше ничего не стоит.
///
/// Имена узлов зашиты здесь намеренно. Миграция описывает ПРОШЛОЕ, и брать их
/// из текущего контента нельзя: переименуют ветку — сломается миграция
/// двухлетней давности.
Map<String, dynamic> _namedEchoNodes(Map<String, dynamic> raw) {
  final profile = raw['profile'];
  if (profile is! Map) return raw;

  final bought = profile['nodesBought'];
  profile.remove('nodesBought');
  if (bought is! num || bought <= 0) {
    profile['echoNodes'] ??= <String>[];
    return raw;
  }

  final count = bought.round().clamp(0, _legacyOrder.length);
  profile['echoNodes'] = _legacyOrder.take(count).toList();

  // Старая «стартовая глубина» была отдельным полем, теперь это узлы ветки
  // «Бездна». Поле уходит: два источника одной величины разъедутся.
  profile.remove('startDepthBonus');
  return raw;
}

/// Порядок, в котором старые безымянные узлы становятся именованными:
/// поровну по веткам, как их и покупала автоматика.
const _legacyOrder = <String>[
  'blood_hp_1', 'blade_damage_1', 'abyss_depth_1',
  'blood_hp_2', 'blade_damage_2', 'abyss_depth_2',
  'blood_armor', 'blade_crit_chance', 'abyss_depth_3',
  'blood_regen', 'blade_crit_multi', 'abyss_ability_slot',
  'blood_resist', 'blade_speed', 'abyss_abilities_1',
  'blood_threshold', 'blade_cooldown', 'abyss_abilities_2',
  'abyss_affix_slot', 'abyss_keep_shard',
];

/// 3 → 4: у сейва появились аккаунт, сезон и номер записи.
///
/// Все четыре поля проставляются ЯВНО, а не оставляются на умолчания
/// читателя, — по тому же правилу, что и приказ на развилку в миграции 1 → 2:
/// сейв обязан говорить, что было, а не полагаться на то, что чужое
/// умолчание никогда не поменяется.
///
/// Значения выбраны так, чтобы разрешение конфликтов (`save_sync.dart`)
/// прочло их правильно:
///
/// * `revision = 1` — этот сейв записывали хотя бы раз, он существует.
/// * `mirroredRevision = 0` — в облако он не доезжал НИКОГДА, и это правда:
///   облака до этой версии не было. Ноль здесь означает «я не потомок ничего
///   облачного», и любой найденный облачный сейв будет честно считаться
///   расхождением, а не отставанием.
/// * `seasonId = season_0` — играли в нулевой сезон, просто тогда он ещё не
///   был подписан.
/// * `accountId` НЕ проставляется. Сейв заведён без аккаунта, и приписать
///   ему нынешний uid значило бы соврать: тот же файл на том же телефоне
///   может принадлежать другому человеку, и пометка «это его» помешала бы
///   заметить смену аккаунта.
/// Память о последних спусках, по которой считается задаток.
///
/// Пустой список, а не выведенный из рекорда, и это решение, а не лень.
/// Вывести из рекорда значило бы вернуть тот самый храповик: сейв, чей
/// владелец однажды дошёл до 133 этажа и с тех пор ходит на 60, открылся бы
/// с ценой найма 25× — то есть ровно в том тупике, из которого эта версия
/// его и вытаскивает. Пустая память отдаёт ему цену новичка на один спуск.
Map<String, dynamic> _recentDepths(Map<String, dynamic> raw) {
  final profile = raw['profile'];
  if (profile is Map) profile['recentDepths'] ??= <int>[];
  return raw;
}

/// 5 → 6: логова стражей.
///
/// Пустые круги и ноль вызовов — и это правда: логов до этой версии не было,
/// взятых кругов у сейва нет. Счётчик вызовов входит в сид боя, поэтому
/// проставляется явно: без него повторный вызов после перезапуска выпадал бы
/// на тот же сид, и проигранный бой можно было бы переиграть закрытием игры.
Map<String, dynamic> _lairs(Map<String, dynamic> raw) {
  final profile = raw['profile'];
  if (profile is Map) {
    profile['lairCircles'] ??= <String, dynamic>{};
    profile['lairAttempts'] ??= 0;
  }
  return raw;
}

/// 6 → 7: смена у Костра и Отзвук глубины (раунд 40).
///
/// Пустая смена и нулевой Отзвук — и это правда: ни того ни другого до этой
/// версии не было. Проставляется явно по правилу миграции 1 → 2: сейв говорит,
/// что было, а не полагается на умолчание читателя.
Map<String, dynamic> _relayAndResonance(Map<String, dynamic> raw) {
  final profile = raw['profile'];
  if (profile is Map) {
    profile['echoResonance'] ??= 0;
    final roster = profile['roster'];
    if (roster is Map) roster['relay'] ??= <dynamic>[];
  }
  return raw;
}

Map<String, dynamic> _accountAndSeason(Map<String, dynamic> raw) {
  raw['revision'] ??= 1;
  raw['mirroredRevision'] ??= 0;
  raw['deviceId'] ??= '';
  raw['seasonId'] ??= 'season_0';

  final profile = raw['profile'];
  if (profile is Map) profile['achievements'] ??= <String, dynamic>{};
  return raw;
}
