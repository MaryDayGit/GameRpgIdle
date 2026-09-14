/// Чем игрок опознан.
enum AccountKind {
  /// Аккаунта нет: нет сети, нет Play Services, нет ключей Firebase или
  /// игрок вышел сам. Игра при этом работает целиком — просто сейв никуда
  /// не уезжает.
  none,

  /// Анонимный. Заводится молча на первом запуске, живёт, пока стоит игра.
  /// Переустановку НЕ переживает: uid хранится в данных приложения, и
  /// вместе с ними удаляется.
  anonymous,

  /// Привязан к Google. Единственный вид, переживающий переустановку и
  /// смену телефона, — ради него всё остальное и делается.
  google,
}

/// Кто играет.
///
/// Не «пользователь» и не профиль: игра не знает про человека ничего, кроме
/// того, что нужно, чтобы найти его сейв. Почта хранится только для того,
/// чтобы показать её в настройках — иначе «вы вошли» невозможно проверить
/// глазами, и игрок не знает, в какой из двух своих Google-аккаунтов попал.
class Account {
  const Account({this.kind = AccountKind.none, this.uid, this.email});

  static const Account none = Account();

  final AccountKind kind;
  final String? uid;
  final String? email;

  /// Есть ли, кому принадлежит сейв. Только при этом условии включается
  /// облачное зеркало.
  bool get hasId => uid != null && uid!.isNotEmpty;

  /// Переживёт ли этот аккаунт переустановку игры.
  bool get isPermanent => kind == AccountKind.google;

  /// Значение свойства аналитики `account`. Короткое: у свойств GA4 на
  /// значение 36 символов, и тратить их на слово «anonymous» незачем.
  String get analyticsValue => switch (kind) {
        AccountKind.none => 'none',
        AccountKind.anonymous => 'anon',
        AccountKind.google => 'google',
      };

  @override
  String toString() => '${kind.name}:${uid ?? '-'}';
}

/// Чем кончилась привязка к Google.
///
/// Перечисление, а не `bool`, потому что один из исходов не является ни
/// успехом, ни ошибкой: [alreadyInUse] — это игрок, который уже играл под
/// этим Google на другом телефоне. Ему нужен не повтор попытки, а выбор
/// между двумя сейвами, и свести этот случай к «не получилось» значит
/// показать ему ошибку вместо его же аккаунта.
enum LinkOutcome {
  ok,

  /// Под этим Google уже есть аккаунт. Вошли в него; сейв, нажитый анонимно,
  /// остался на устройстве и разбирается общим правилом (`save_sync.dart`).
  alreadyInUse,

  /// Игрок закрыл окно выбора аккаунта. Не ошибка, показывать нечего.
  cancelled,

  /// Всё остальное: нет сети, нет Play Services, провайдер не включён в
  /// консоли, не совпал отпечаток ключа подписи.
  failed,
}

/// Аккаунт игрока: вход, привязка, выход.
///
/// Интерфейс отдельно от Firebase по тому же правилу, что и `AnalyticsSink`:
/// реализация тянет за собой Play Services, а тесты и дев-экраны поднимают
/// игру десятками раз. Плюс тот же второй выигрыш — сменить поставщика
/// опознания значит написать один класс, не трогая ни одного места, которое
/// про аккаунт спрашивает.
abstract class AccountService {
  Account get current;

  /// Молча завести или поднять анонимный аккаунт. Зовётся на запуске и
  /// НИЧЕГО не показывает игроку: экран входа перед первым кадром — это
  /// стена там, где игра обещала «нажал и играешь».
  Future<Account> signInSilently();

  /// Привязать текущий аккаунт к Google. Показывает системный выбор
  /// аккаунта, поэтому зовётся только из настроек, по кнопке.
  Future<LinkOutcome> linkGoogle();

  /// Выйти. Сейв на устройстве остаётся: выход из аккаунта — это не удаление
  /// прогресса, и превращать одно в другое нельзя ни при каких условиях.
  Future<void> signOut();
}

/// Аккаунта нет и не будет. Значение по умолчанию везде, где служба не
/// задана: в тестах, в дев-экранах, в сборке без ключей Firebase.
///
/// Не `null` — по той же причине, что и `NoopAnalyticsSink`: `account?.uid`
/// в десятке мест это десяток шансов забыть вопросительный знак.
class NoAccountService implements AccountService {
  const NoAccountService();

  @override
  Account get current => Account.none;

  @override
  Future<Account> signInSilently() async => Account.none;

  @override
  Future<LinkOutcome> linkGoogle() async => LinkOutcome.failed;

  @override
  Future<void> signOut() async {}
}

/// Аккаунт понарошку. Для тестов, которым нужен uid, но не нужен Firebase.
class FakeAccountService implements AccountService {
  FakeAccountService({this.uid = 'test_uid', this.linkResult = LinkOutcome.ok});

  final String uid;
  LinkOutcome linkResult;

  Account _current = Account.none;

  @override
  Account get current => _current;

  @override
  Future<Account> signInSilently() async =>
      _current = Account(kind: AccountKind.anonymous, uid: uid);

  @override
  Future<LinkOutcome> linkGoogle() async {
    if (linkResult == LinkOutcome.ok) {
      _current = Account(
          kind: AccountKind.google, uid: uid, email: 'test@example.com');
    }
    return linkResult;
  }

  @override
  Future<void> signOut() async => _current = Account.none;
}
