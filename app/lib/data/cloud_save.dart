import 'package:rift/core/save/save_data.dart';
import 'package:rift/core/save/save_head.dart';

/// Сейв, лежащий в облаке: паспорт отдельно, тело отдельно.
///
/// Тело — строка, а не разобранный профиль, и это главное решение всего
/// облачного слоя. Разбирать чужой сейв, чтобы решить, брать ли его,
/// значит прогнать его через снисходительную загрузку (`codec.dart`),
/// которая молча починит всё, что не сошлось с текущим контентом. Сравнивали
/// бы мы после этого не облачный сейв, а то, что от него осталось.
///
/// Строка же доезжает до `SaveData.decode` ровно такой, какой её записали, —
/// один формат, один разбор, ни одного места, где локальный сейв и облачный
/// могли бы разъехаться.
class CloudSave {
  const CloudSave({required this.head, required this.payload});

  final SaveHead head;

  /// Тело сейва: то же самое, что лежит в локальном файле.
  final String payload;

  /// Разбирает тело. Бросает `SaveException`, если сейв не читается вовсе —
  /// это правильно: взять облачный сейв и не суметь его открыть надо
  /// заметить, а не проглотить.
  SaveData decode() => SaveData.decode(payload);
}

/// Облачное зеркало сейва.
///
/// **Зеркало, а не хозяин.** Хозяин — файл на телефоне
/// (`docs/02-TECH.md` §4): спуск считается на устройстве и обязан считаться
/// без сети, а idle-игра, которую нельзя открыть в метро, не idle-игра.
/// Облако отвечает на два вопроса, на которые файл ответить не может:
/// «я переустановил игру» и «я играю с планшета».
///
/// Интерфейс отдельно от Firestore по тому же правилу, что `AnalyticsSink` и
/// `AccountService`: реализация тянет Play Services, а проверять надо
/// поведение, а не плагин.
abstract class CloudSaveStore {
  /// Читает сейв сезона. `null` — его там нет.
  ///
  /// Бросает при отказе сети: «нет документа» и «не смогли спросить» —
  /// разные вещи, и путать их нельзя. Первое означает «выгружай своё»,
  /// второе — «не трогай ничего».
  Future<CloudSave?> fetch({required String uid, required String seasonId});

  /// Записывает сейв. Возвращает `false`, если не получилось: вызывающий по
  /// этому решает, поднимать ли `mirroredRevision`, а соврать здесь значит
  /// объявить сейв синхронизированным, когда он никуда не уехал.
  Future<bool> push({required String uid, required SaveData data});

  /// Стирает все сейвы игрока — всех сезонов, не только нынешнего.
  ///
  /// `false` — не получилось (нет сети, отказ сервера). Вызывающий обязан
  /// остановиться: удалить аккаунт при целом облаке значит оставить сейв,
  /// к которому больше нет ключа, — и удалить его потом не сможет никто.
  Future<bool> deleteAll({required String uid});
}

/// Облака нет. Значение по умолчанию: тесты, дев-экраны, сборка без ключей.
class NoCloudSaveStore implements CloudSaveStore {
  const NoCloudSaveStore();

  @override
  Future<CloudSave?> fetch({required String uid, required String seasonId}) async =>
      null;

  @override
  Future<bool> push({required String uid, required SaveData data}) async =>
      false;

  /// Облака нет — и стирать в нём нечего. Это успех, а не отказ: иначе
  /// игрок без Firebase не смог бы удалить даже то, что лежит на телефоне.
  @override
  Future<bool> deleteAll({required String uid}) async => true;
}

/// Облако в памяти. Для тестов, которым нужно свести два устройства.
class FakeCloudSaveStore implements CloudSaveStore {
  final Map<String, CloudSave> docs = {};

  /// Сколько раз писали. Ради этого счётчика тест и существует: облако,
  /// в которое пишут на каждом автосейве, — это сожжённая квота Firestore.
  int pushes = 0;

  /// Отказ сети, которым можно управлять.
  bool offline = false;

  String _key(String uid, String season) => '$uid/$season';

  @override
  Future<CloudSave?> fetch(
      {required String uid, required String seasonId}) async {
    if (offline) throw StateError('облако недоступно');
    return docs[_key(uid, seasonId)];
  }

  @override
  Future<bool> push({required String uid, required SaveData data}) async {
    if (offline) return false;
    pushes++;
    docs[_key(uid, data.seasonId)] =
        CloudSave(head: data.head, payload: data.encode());
    return true;
  }

  @override
  Future<bool> deleteAll({required String uid}) async {
    if (offline) return false;
    docs.removeWhere((key, _) => key.startsWith('$uid/'));
    return true;
  }
}
