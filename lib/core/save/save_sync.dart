import 'save_head.dart';
import 'season.dart';

/// Что делать с парой «сейв на телефоне — сейв в облаке».
enum SyncAction {
  /// Играем локальным. Облако либо отстало, либо его нет.
  keepLocal,

  /// Берём облачный: переустановка, новое устройство, откат локального файла.
  takeRemote,

  /// Разошлись. Выбирает игрок — молча выбрать за него значит стереть
  /// половину прогресса тому, кто про этот выбор даже не узнает.
  ask,

  /// Локальный сейв — из прошлого сезона. Он не загружается: убирается в
  /// архив, игра начинается заново (`season.dart`).
  newSeason,
}

/// Решение с объяснением.
///
/// [reason] короткий и машинный не для красоты: он уезжает в аналитику
/// (`save_conflict`). Синхронизация сейвов — то место, где ошибка стоит
/// аккаунта, а воспроизвести её дома нельзя: нужны два устройства, которые
/// разошлись именно так. Разрез по причинам — единственный способ увидеть,
/// какая ветка решения вообще срабатывает у живых игроков и не срабатывает
/// ли `ask` там, где должно было хватить `keepLocal`.
class SyncDecision {
  const SyncDecision(this.action, this.reason, {this.local, this.remote});

  final SyncAction action;
  final String reason;

  final SaveHead? local;
  final SaveHead? remote;

  bool get needsPlayer => action == SyncAction.ask;

  @override
  String toString() => '${action.name} ($reason)';
}

/// Разрешение расхождений между сейвом на телефоне и сейвом в облаке.
///
/// Чистая функция от двух паспортов (`save_head.dart`): ни файлов, ни сети,
/// ни Firebase. Это сделано ради теста — все ветки решения проверяются
/// headless, за миллисекунды, включая те, до которых вручную не добраться
/// (два устройства, разошедшиеся из общей точки). Ошибка здесь стоит чужого
/// аккаунта, и ловить её на живых игроках нельзя.
///
/// ## Почему нельзя просто «кто новее»
///
/// Правило «побеждает свежая отметка времени» ломается на самом обычном
/// сценарии из всех — переустановке. Игра, поставленная заново, заводит
/// пустой профиль с отметкой «сейчас», и по времени он побеждает облачный
/// сейв на сорок этажей. Игрок открывает игру и видит чистый лист, а через
/// минуту автосейв затирает облако. Аккаунта больше нет, и восстановить его
/// нечем.
///
/// Часам нельзя доверять и по мелочи: их переводят вручную, они разъезжаются
/// между устройствами, а часовой пояс меняется в самолёте.
///
/// ## На чём решение стоит вместо этого
///
/// На паре чисел: [SaveHead.revision] («сколько раз меня записали») и
/// [SaveHead.mirroredRevision] («на какой записи я последний раз сошёлся с
/// облаком»). Вместе они отвечают на единственный важный вопрос —
/// **расходились ли мы с тех пор, как сходились**:
///
/// * облако не двигалось с нашей последней выгрузки → мы его потомок,
///   играем локальным;
/// * мы не двигались с последней выгрузки, а облако двинулось → это другое
///   устройство, берём облачный;
/// * двинулись оба → две ветки из общей точки, и объединить их нельзя
///   (сейв — это не текст, «слить» два разных Хранилища не значит ничего).
///   Спрашиваем игрока.
///
/// Отметка времени остаётся, но только чтобы ПОКАЗАТЬ её игроку в диалоге.
/// Решений на ней не строится.
abstract final class SaveSync {
  /// [local] — паспорт файла на телефоне, [remote] — документа в облаке.
  /// `null` означает «нет вовсе», а не «не смогли прочитать»: не прочитанное
  /// облако — это отсутствие связи, и вести себя надо как при её отсутствии,
  /// то есть играть локальным.
  static SyncDecision resolve({SaveHead? local, SaveHead? remote}) {
    // Сейв прошлого сезона проверяется ПЕРВЫМ и до всего остального.
    // Сравнивать прогресс разных сезонов бессмысленно: сорок этажей нулевого
    // сезона — это не «больше», чем два этажа первого, это другая игра.
    if (local != null && !local.isCurrentSeason) {
      return SyncDecision(SyncAction.newSeason, 'local_season_${local.seasonId}',
          local: local, remote: remote);
    }

    // Документ в облаке лежит по адресу с сезоном, так что чужой сезон
    // означает мусор от будущей или прошлой версии. Не берём и не трогаем:
    // затирать документ чужого сезона — это стирать архив.
    final cloud = remote != null && remote.isCurrentSeason ? remote : null;

    if (cloud == null) {
      return SyncDecision(SyncAction.keepLocal,
          remote == null ? 'no_remote' : 'remote_other_season',
          local: local, remote: remote);
    }
    if (local == null) {
      return SyncDecision(SyncAction.takeRemote, 'no_local',
          remote: cloud);
    }

    // Переустановка и новое устройство. Главная ветка ради которой всё
    // затевалось: локальный сейв свежий по времени и пустой по существу.
    if (local.progress.isNewGame && !cloud.progress.isNewGame) {
      return SyncDecision(SyncAction.takeRemote, 'fresh_install',
          local: local, remote: cloud);
    }

    // Обратный случай: в облаке пусто, на телефоне игра. Спрашивать не о чем
    // — выбора между чем-то и ничем не существует.
    if (cloud.progress.isNewGame && !local.progress.isNewGame) {
      return SyncDecision(SyncAction.keepLocal, 'remote_empty',
          local: local, remote: cloud);
    }

    // Облако не двигалось с нашей последней выгрузки: то, что там лежит, —
    // наш же предок.
    if (cloud.revision <= local.mirroredRevision) {
      return SyncDecision(SyncAction.keepLocal, 'local_ahead',
          local: local, remote: cloud);
    }

    // Мы не двигались с последней выгрузки, а облако двинулось: писало
    // другое устройство.
    if (local.revision <= local.mirroredRevision) {
      return SyncDecision(SyncAction.takeRemote, 'remote_ahead',
          local: local, remote: cloud);
    }

    // Двинулись оба. Отдельная причина для смены аккаунта: это не «две ветки
    // одной жизни», а два разных игрока на одном телефоне, и в отчёте их
    // надо видеть отдельно.
    final swapped = local.accountId != null &&
        cloud.accountId != null &&
        local.accountId != cloud.accountId;
    return SyncDecision(
        SyncAction.ask, swapped ? 'other_account' : 'diverged',
        local: local, remote: cloud);
  }

  /// Имя архивного файла для сейва прошлого сезона.
  ///
  /// Архив, а не удаление: сезон кончается, доказанное в нём — нет
  /// (`season.dart`). Файл остаётся на диске под именем своего сезона, и
  /// если окажется, что обнулили не то, вернуть его — это переименование.
  static String archiveName(String baseName, String seasonId) {
    final dot = baseName.indexOf('.');
    final stem = dot <= 0 ? baseName : baseName.substring(0, dot);
    final rest = dot <= 0 ? '' : baseName.substring(dot);
    final clean = seasonId.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return '$stem.$clean$rest';
  }

  /// Сезон, с которого начинается новый сейв.
  static String get currentSeasonId => Season.current.id;
}
