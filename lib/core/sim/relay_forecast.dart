import '../model/player_profile.dart';
import '../save/codec.dart';
import '../save/save_issue.dart';

/// Чем кончится смена, если игрок так и не придёт (GDD §9.4).
///
/// Нужна ровно для одного — уведомления. Пока приложение закрыто, игра не
/// считает ничего, и переставить будильник в момент, когда сменщик ушёл вниз,
/// некому. Поэтому вся смена считается вперёд в момент ухода игрока, и
/// уведомление ставится на гибель ПОСЛЕДНЕГО наёмника очереди.
///
/// **Считается тем же кодом, что и настоящий догон.** Профиль копируется через
/// сейв и перематывается `refreshContracts` на год вперёд — как если бы игрок
/// открыл игру через год. Своя упрощённая модель смены разошлась бы с
/// настоящей в первой же правке; копия через сейв расходиться не умеет.
class RelayForecast {
  const RelayForecast({
    required this.endsAtUtc,
    required this.runs,
    required this.depth,
  });

  /// Когда погибнет последний наёмник — и смена, и все остальные спуски.
  final DateTime endsAtUtc;

  /// Сколько сменщиков успеет уйти вниз.
  final int runs;

  /// Глубочайший этаж, до которого дойдут все спуски вместе.
  final int depth;

  /// Прогноз смены. `null` — смены нет или ей некого сменять.
  static RelayForecast? of(PlayerProfile profile) {
    if (profile.roster.relay.isEmpty) return null;
    if (!profile.contracts.any((c) => c.descending || c.atFork)) return null;

    final copy = SaveCodec.decodeProfile(
      SaveCodec.encodeProfile(profile),
      SaveIssues(),
    );
    final before = copy.contracts.length;

    // Отсчёт — от самого позднего известного конца, а не от системных часов:
    // прогноз обязан быть функцией профиля, иначе тест его не проверит.
    // Год — заведомо дольше любой смены: спуск идёт меньше часа, мест в
    // очереди не больше шести.
    final ends = [
      for (final c in copy.contracts)
        if (c.segmentEndsAtUtc != null) c.segmentEndsAtUtc!,
    ];
    if (ends.isEmpty) return null;
    final latest = ends.reduce((a, b) => b.isAfter(a) ? b : a);
    copy.refreshContracts(latest.add(const Duration(days: 365)));

    final runs = copy.contracts.length - before;
    if (runs <= 0) return null;

    var endsAt = latest;
    var depth = 0;
    for (final c in copy.contracts) {
      final end = c.segmentEndsAtUtc;
      if (end != null && end.isAfter(endsAt)) endsAt = end;
      final reached = c.result?.maxDepth ?? 0;
      if (reached > depth) depth = reached;
    }
    return RelayForecast(endsAtUtc: endsAt, runs: runs, depth: depth);
  }
}
