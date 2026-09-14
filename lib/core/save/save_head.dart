import '../model/outpost.dart';
import '../model/player_profile.dart';
import 'season.dart';

/// Сколько в сейве нажито. Четыре числа, а не весь профиль.
///
/// Нужно ровно в двух местах, и оба важнее, чем кажется.
///
/// **Игроку — в диалоге расхождения.** Когда сейв на телефоне и сейв в
/// облаке разошлись, выбирать между ними приходится ему. «Сохранение от 3
/// сентября» — это не выбор: даты у идл-игры почти всегда близкие, потому
/// что игру открывают каждый день. Выбор — это «рекорд 47, 12 спусков,
/// Застава 9» против «рекорд 12, 2 спуска, Застава 1».
///
/// **Коду — чтобы отличить пустой сейв от нажитого.** Свежая установка
/// заводит профиль с нулями и СВЕЖЕЙ отметкой времени. По времени такой сейв
/// побеждает любой облачный, и правило «новее — значит хозяин» стёрло бы
/// аккаунт ровно тому, кто переустановил игру. Поэтому решение смотрит не
/// только на часы (`save_sync.dart`).
class SaveProgress {
  const SaveProgress({
    this.maxDepth = 0,
    this.runs = 0,
    this.outpostLevel = 0,
    this.gold = 0.0,
  });

  factory SaveProgress.of(PlayerProfile p) => SaveProgress(
        maxDepth: p.maxDepthEver,
        runs: p.quests.runsCompleted,
        outpostLevel: totalOutpostLevel(p),
        gold: p.gold,
      );

  /// Рекорд глубины. Первое, что игрок назовёт, если спросить, что у него в
  /// сейве.
  final int maxDepth;

  /// Законченных спусков. Единственное число, которое растёт всегда: рекорд
  /// упирается в стену, золото тратится, Застава упирается в потолок.
  final int runs;

  /// Сумма уровней построек Заставы.
  final int outpostLevel;

  final double gold;

  /// Сейв, в котором ещё ничего не случилось.
  ///
  /// Именно «ничего не случилось», а не «профиль по умолчанию»:
  /// `PlayerProfile.newGame` выдаёт первого наёмника и раскладывает таверну,
  /// то есть отличается от пустого профиля — но не отличается от него ничем,
  /// что игроку было бы жалко потерять.
  ///
  /// **Золото в проверку не входит намеренно**, хотя и лежит рядом. От этого
  /// признака зависит восстановление после переустановки (`save_sync.dart`):
  /// сейв, ошибочно посчитанный нажитым, отменяет автоматический подъём из
  /// облака и вместо него показывает игроку диалог — или, хуже, оставляет
  /// его с чистым листом. Стартовое золото — вопрос баланса, и решение
  /// выдать новичку первые 250 монет не должно ломать восстановление
  /// аккаунтов. Три остальных числа так не меняются: они растут только от
  /// игры.
  bool get isNewGame => runs == 0 && maxDepth == 0 && outpostLevel == 0;

  /// Заведомо больше другого по всем осям сразу.
  ///
  /// Нужно для случая, когда спрашивать игрока не о чем: сейв, который
  /// одновременно глубже, дольше и богаче, — это тот же сейв, доигранный
  /// дальше, а не второй вариант жизни.
  bool dominates(SaveProgress other) =>
      maxDepth >= other.maxDepth &&
      runs >= other.runs &&
      outpostLevel >= other.outpostLevel &&
      (maxDepth > other.maxDepth ||
          runs > other.runs ||
          outpostLevel > other.outpostLevel);

  Map<String, dynamic> toJson() => {
        'maxDepth': maxDepth,
        'runs': runs,
        'outpostLevel': outpostLevel,
        'gold': gold,
      };

  factory SaveProgress.fromJson(Map<String, dynamic> j) => SaveProgress(
        maxDepth: j['maxDepth'] is num ? (j['maxDepth'] as num).toInt() : 0,
        runs: j['runs'] is num ? (j['runs'] as num).toInt() : 0,
        outpostLevel:
            j['outpostLevel'] is num ? (j['outpostLevel'] as num).toInt() : 0,
        gold: j['gold'] is num ? (j['gold'] as num).toDouble() : 0.0,
      );

  static int totalOutpostLevel(PlayerProfile p) {
    var sum = 0;
    for (final b in Building.values) {
      sum += p.outpost.levelOf(b);
    }
    return sum;
  }

  @override
  String toString() =>
      'глубина $maxDepth, спусков $runs, Застава $outpostLevel, '
      'золота ${gold.round()}';
}

/// Паспорт сейва: всё, что нужно знать о нём, не разбирая профиль.
///
/// Существует потому, что решение «какой сейв взять» принимается ДО загрузки.
/// Разбирать ради него оба профиля целиком — это лишние десятки килобайт
/// разбора на каждом запуске и, что хуже, снисходительная загрузка
/// (`codec.dart`) чужого сейва: она починит его молча, и сравнивать мы будем
/// уже не то, что лежит в облаке.
///
/// В Firestore эти поля лежат ОТДЕЛЬНО от тела сейва, на верхнем уровне
/// документа. Не для экономии — документ всё равно приезжает целиком, — а
/// потому что по ним можно строить запросы: таблица лидеров сезона это
/// `order by head.maxDepth`, и ей незачем читать чужие профили.
class SaveHead {
  const SaveHead({
    required this.version,
    required this.revision,
    required this.seasonId,
    required this.lastSeenUtc,
    this.mirroredRevision = 0,
    this.deviceId = '',
    this.accountId,
    this.progress = const SaveProgress(),
  });

  /// Версия формата сейва. Та же, что в [SaveData.version].
  final int version;

  /// Номер записи. Растёт на единицу с каждым сохранением и никогда не
  /// уменьшается.
  ///
  /// Заводится потому, что времени доверять нельзя. Часы на телефоне
  /// переводят, часовые пояса меняют, а два устройства расходятся на минуты
  /// без всякого злого умысла. Счётчик же говорит ровно то, что нужно
  /// решению: сколько раз этот сейв записывали.
  final int revision;

  /// До какой ревизии сейв доехал в облако. 0 — не доезжал ни разу.
  ///
  /// Это ключ ко всему разрешению конфликтов, и без него оно было бы
  /// гаданием. Пара «где я» + «где я был, когда последний раз синхронизировался»
  /// отвечает на единственный вопрос, который важен: расходились ли мы с
  /// облаком с тех пор, как в последний раз сходились. Одна ревизия на это
  /// не отвечает — числа `local=5, remote=7` одинаково выглядят и когда
  /// облако ушло вперёд, и когда две ветки разошлись из общей точки.
  final int mirroredRevision;

  /// Кто записал последним. Человекочитаемого имени тут нет намеренно —
  /// модель телефона это уже сведения об устройстве, а игра их не собирает
  /// (`docs/11-ANALYTICS.md` §5). Хватает того, что идентификаторы разные.
  final String deviceId;

  /// Аккаунт, которому принадлежит сейв. `null` — сейв старше аккаунтов
  /// или заведён без сети.
  final String? accountId;

  final String seasonId;

  final DateTime lastSeenUtc;

  final SaveProgress progress;

  bool get isCurrentSeason => Season.isCurrent(seasonId);

  Map<String, dynamic> toJson() => {
        'version': version,
        'revision': revision,
        'mirroredRevision': mirroredRevision,
        'deviceId': deviceId,
        if (accountId != null) 'accountId': accountId,
        'seasonId': seasonId,
        'lastSeenUtc': lastSeenUtc.toUtc().toIso8601String(),
        'progress': progress.toJson(),
      };

  /// Читает паспорт, прощая всё, кроме отсутствующей версии.
  ///
  /// Прощает потому, что паспорт читается у ЧУЖОГО документа — записанного
  /// другой версией игры, а то и наполовину. Отказ разбирать его означал бы
  /// отказ синхронизироваться вовсе; отсутствующее поле — это просто ноль,
  /// и решение с нулями всё ещё осмысленно.
  static SaveHead? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final version = j['version'];
    if (version is! int) return null;

    return SaveHead(
      version: version,
      revision: j['revision'] is num ? (j['revision'] as num).toInt() : 0,
      mirroredRevision: j['mirroredRevision'] is num
          ? (j['mirroredRevision'] as num).toInt()
          : 0,
      deviceId: j['deviceId'] is String ? j['deviceId'] as String : '',
      accountId: j['accountId'] is String ? j['accountId'] as String : null,
      seasonId:
          j['seasonId'] is String ? j['seasonId'] as String : Season.zero.id,
      lastSeenUtc:
          DateTime.tryParse('${j['lastSeenUtc']}')?.toUtc() ?? DateTime(1970),
      progress: SaveProgress.fromJson(
          j['progress'] is Map ? (j['progress'] as Map).cast() : const {}),
    );
  }

  @override
  String toString() => 'v$version r$revision/$mirroredRevision '
      '$seasonId ($progress)';
}
