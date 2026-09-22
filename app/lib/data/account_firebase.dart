import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'account.dart';

export 'account.dart';

/// Аккаунт на Firebase Auth: анонимный вход молча, привязка к Google по
/// кнопке.
///
/// ## Почему анонимный вход, а не сразу Google
///
/// Игра обещает «открыл и играешь». Экран входа перед первым кадром — это
/// стена ровно там, где обещание проверяется, и часть игроков за неё не
/// пойдёт: заводить аккаунт ради idle-игры, в которую ещё не поиграл, никто
/// не хочет.
///
/// Анонимный вход даёт ту же техническую вещь — uid, под которым лежит
/// сейв, — и не спрашивает ничего. Дальше игрок играет, и если игра ему
/// зашла, привязка к Google становится не входным барьером, а способом не
/// потерять сорок этажей. Разговор в этот момент совершенно другой.
///
/// **Про честность анонимного аккаунта надо говорить прямо.** Он живёт,
/// пока стоит игра: uid хранится в данных приложения и стирается вместе с
/// ними. Переустановка, «очистить данные», новый телефон — и сейв в облаке
/// остаётся, а ключа к нему нет. Поэтому в настройках привязка подписана
/// тем, что она делает, а не словом «войти».
///
/// ## Что нужно в консоли Firebase
///
/// 1. Authentication → Sign-in method → включить **Anonymous** и **Google**.
/// 2. В карточке Android-приложения добавить **отпечатки SHA-1** ключей
///    подписи — и отладочного, и релизного. Без SHA-1 Google-вход на Android
///    не работает вовсе, а ошибка приходит невнятная (`ApiException: 10`).
/// 3. Скачать `google-services.json` ЗАНОВО. Файл, скачанный до включения
///    Google-провайдера, не содержит веб-клиента OAuth, из которого плагин
///    берёт `serverClientId`, — и вход молча не выдаёт `idToken`.
class FirebaseAccountService implements AccountService {
  FirebaseAccountService._(this._auth);

  final FirebaseAuth _auth;

  Account _current = Account.none;

  @override
  Account get current => _current;

  /// Поднимает службу. `null` — Firebase недоступен, игра идёт без аккаунта.
  ///
  /// Отказ здесь ШТАТЕН по тому же правилу, что и в `AnalyticsSetup`:
  /// `google-services.json` не лежит в репозитории, Play Services есть не на
  /// каждом устройстве, а сети может не быть вовсе. Ни один из этих случаев
  /// не повод не пустить игрока в игру — он повод не синхронизировать сейв.
  static Future<AccountService> create() async {
    try {
      // Firebase поднимается здесь, а не берётся уже поднятым из
      // `AnalyticsSetup`. Повторный вызов ничего не стоит — он возвращает то
      // же приложение, — а зависимость от ЧУЖОГО порядка загрузки стоила бы
      // аккаунтов у всех, кому однажды переставят две строки в `boot()`.
      await Firebase.initializeApp();
      return FirebaseAccountService._(FirebaseAuth.instance);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[account] Firebase Auth недоступен: $e');
      return const NoAccountService();
    }
  }

  /// Сколько ждём сеть на входе.
  ///
  /// Граница жёсткая, потому что вход стоит ПЕРЕД первым кадром: без неё
  /// игрок без сети смотрит в чёрный экран столько, сколько отмерит своим
  /// таймаутом чужая библиотека. Игра обещает открываться в метро, и обещание
  /// не может зависеть от настроек SDK.
  ///
  /// Ничего не теряется: аккаунт заведётся при следующем запуске с сетью, а
  /// сейв к тому моменту уже есть и уедет в облако целиком.
  static const Duration _patience = Duration(seconds: 8);

  @override
  Future<Account> signInSilently() async {
    try {
      // `currentUser` не требует сети вовсе: SDK держит вошедшего на диске.
      // Ждать приходится только на ПЕРВОМ запуске.
      final cached = _auth.currentUser;
      if (cached != null) return _current = _read(cached);

      final result = await _auth.signInAnonymously().timeout(_patience);
      return _current = _read(result.user);
    } on Object catch (e) {
      // Сюда попадает игрок без сети на первом запуске. Он играет локально,
      // а аккаунт заведётся при следующем запуске с сетью — сейв к этому
      // моменту уже есть, и он уедет в облако целиком.
      if (kDebugMode) debugPrint('[account] анонимный вход не удался: $e');
      return _current = Account.none;
    }
  }

  @override
  Future<LinkOutcome> linkGoogle() async {
    final GoogleSignInAccount googleUser;
    try {
      // `initialize` обязателен и ровно один раз за процесс — плагин
      // 7.x требует дождаться его до любого другого вызова. Повторный
      // безвреден, поэтому зовётся здесь, а не в загрузке: тянуть Google
      // Identity Services в каждый запуск ради кнопки, которую нажмут раз в
      // жизни, незачем.
      await GoogleSignIn.instance.initialize();
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Закрытое окно выбора аккаунта — не ошибка. Показывать игроку
      // «не удалось войти» после того, как он сам нажал «отмена», значит
      // обвинять его в собственном решении.
      return e.code == GoogleSignInExceptionCode.canceled
          ? LinkOutcome.cancelled
          : _fail('google', e);
    } on Object catch (e) {
      return _fail('google', e);
    }

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      // Почти всегда означает одно: в `google-services.json` нет веб-клиента
      // OAuth, потому что файл скачан до включения Google-провайдера.
      return _fail('token', 'Google не выдал idToken');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final user = _auth.currentUser;

    try {
      if (user == null) {
        await _auth.signInWithCredential(credential);
      } else {
        await user.linkWithCredential(credential);
      }
      _current = _read(_auth.currentUser);
      return LinkOutcome.ok;
    } on FirebaseAuthException catch (e) {
      // Игрок уже играл под этим Google на другом телефоне. Это не ошибка, а
      // ровно тот случай, ради которого привязка и нужна: входим в его
      // аккаунт, а два сейва — здешний и облачный — сводит общее правило
      // (`rift/core/save/save_sync.dart`).
      //
      // `provider-already-linked` и `credential-already-in-use` разведены
      // намеренно: первое означает «уже привязан», то есть успех, о котором
      // игрок и просил.
      if (e.code == 'provider-already-linked') {
        _current = _read(_auth.currentUser);
        return LinkOutcome.ok;
      }
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        try {
          await _auth.signInWithCredential(credential);
          _current = _read(_auth.currentUser);
          return LinkOutcome.alreadyInUse;
        } on Object catch (e) {
          return _fail('signin', e);
        }
      }
      return _fail('link', e);
    } on Object catch (e) {
      return _fail('link', e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await GoogleSignIn.instance.signOut();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[account] выход не удался: $e');
    }
    _current = Account.none;
  }

  @override
  Future<DeleteOutcome> confirmForDeletion() async {
    final user = _auth.currentUser;
    if (user == null || !_isGoogle(user)) return DeleteOutcome.ok;

    // Google-аккаунт Firebase удаляет только после свежего входа
    // (`requires-recent-login`). Входим заново ЗДЕСЬ, до удаления облака:
    // закрытое окно выбора аккаунта должно оставить всё как было.
    try {
      await GoogleSignIn.instance.initialize();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) return _deleteFail('token', 'Google не выдал idToken');
      await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(idToken: idToken));
      return DeleteOutcome.ok;
    } on GoogleSignInException catch (e) {
      return e.code == GoogleSignInExceptionCode.canceled
          ? DeleteOutcome.cancelled
          : _deleteFail('google', e);
    } on Object catch (e) {
      // В том числе `user-mismatch`: выбран другой Google-аккаунт. Удалять
      // чужой аккаунт по входу в свой нельзя, и Firebase это правильно режет.
      return _deleteFail('reauth', e);
    }
  }

  @override
  Future<DeleteOutcome> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      _current = Account.none;
      return DeleteOutcome.ok;
    }
    final google = _isGoogle(user);
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // Анонимный аккаунт после долгой игры тоже просит свежего входа, а
      // войти заново в анонимный нельзя. О человеке в нём нет ничего — только
      // uid, облако под которым уже стёрто, — поэтому выходим, и запись
      // остаётся сиротой без данных. Google-аккаунт сюда не доходит: его
      // подтвердили только что, в [confirmForDeletion].
      if (e.code == 'requires-recent-login' && !google) {
        await _auth.signOut();
      } else {
        return _deleteFail('delete', e);
      }
    } on Object catch (e) {
      return _deleteFail('delete', e);
    }

    // Отзываем и разрешение, выданное игре Google-аккаунтом: иначе
    // следующая привязка молча вошла бы без вопроса, как будто удаления не было.
    if (google) {
      try {
        await GoogleSignIn.instance.disconnect();
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[account] отзыв Google не удался: $e');
      }
    }
    _current = Account.none;
    return DeleteOutcome.ok;
  }

  static bool _isGoogle(User user) =>
      user.providerData.any((p) => p.providerId == 'google.com');

  static DeleteOutcome _deleteFail(String stage, Object error) {
    if (kDebugMode) debugPrint('[account] удаление ($stage): $error');
    return DeleteOutcome.failed;
  }

  Account _read(User? user) {
    if (user == null) return Account.none;
    final google =
        user.providerData.any((p) => p.providerId == 'google.com');
    return Account(
      kind: google ? AccountKind.google : AccountKind.anonymous,
      uid: user.uid,
      email: google ? user.email : null,
    );
  }

  static LinkOutcome _fail(String stage, Object error) {
    if (kDebugMode) debugPrint('[account] привязка ($stage): $error');
    return LinkOutcome.failed;
  }
}
