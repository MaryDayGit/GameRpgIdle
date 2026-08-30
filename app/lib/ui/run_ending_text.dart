import 'package:rift/core/model/grammar.dart';
import 'package:rift/core/sim/descent.dart';

/// Исход спуска одним словом — для карточки на Заставе и заголовков.
/// Сам журнал живёт в `journal_screen.dart`.
///
/// Согласуется с наёмником: половина имён в пуле женские, и «Мирена
/// Последняя погиб» — это ровно то «странное слово», на которое пожаловался
/// живой прогон.
String endingRu(RunEnding ending, [Gender gender = Gender.masculine]) {
  final she = gender == Gender.feminine;
  return switch (ending) {
    RunEnding.death => she ? 'погибла' : 'погиб',
    RunEnding.stalled => she ? 'упёрлась в стену' : 'упёрся в стену',
    RunEnding.timeCap => she ? 'отозвана по времени' : 'отозван по времени',
    RunEnding.floorCap => she ? 'дошла до предела' : 'дошёл до предела',
    RunEnding.recalled => she ? 'отозвана' : 'отозван',
    // Спуск не кончился — наёмник стоит на развилке. Слово в настоящем
    // времени намеренно: остальные исходы уже случились, этот происходит.
    RunEnding.atFork => she ? 'на развилке' : 'на развилке',
  };
}
