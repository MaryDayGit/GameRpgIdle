import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/core/content/content_pack.dart';
import 'package:rift_app/data/content.dart';
import 'package:rift_app/data/save_store.dart';
import 'package:rift_app/trailer/demo_profile.dart';
import 'package:rift_app/trailer/trailer_app.dart';
import 'package:rift_app/trailer/trailer_camera.dart';
import 'package:rift_app/trailer/trailer_caption.dart';
import 'package:rift_app/trailer/trailer_film.dart';
import 'package:rift_app/ui/coach_mark.dart';
import 'package:rift_app/ui/echo_tree_screen.dart';
import 'package:rift_app/ui/forge_screen.dart';
import 'package:rift_app/ui/journal_screen.dart';
import 'package:rift_app/ui/loot_sort_screen.dart';
import 'package:rift_app/ui/mercenary_screen.dart';
import 'package:rift_app/ui/passive_tree_screen.dart';
import 'package:rift_app/ui/quests_screen.dart';
import 'package:rift_app/ui/stash_screen.dart';

/// Трейлер — инструмент, а не игра, и всё-таки он тут проверяется.
///
/// Причина простая: сломанный трейлер обнаруживается на съёмке, когда телефон
/// уже в штативе, а свет уже поставлен. Дешевле узнать здесь.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;

  setUpAll(() {
    final raw = <String, Object?>{};
    for (final name in ContentPack.fileNames) {
      raw[name] =
          jsonDecode(File('assets/content/$name.json').readAsStringSync());
    }
    content = ContentBundle(raw: raw, pack: ContentPack.parse(raw));
    content.pack.apply();
  });

  test('демо-профиль: Застава, в которой уже жили', () {
    final p = DemoProfile.build();

    // Пустая Застава в кадре показывает не игру, а её первую минуту.
    expect(p.maxDepthEver, greaterThan(20),
        reason: 'глубина рекорда должна быть похожа на прожитую игру');
    expect(p.stash, isNotEmpty, reason: 'сундук в кадре не должен быть пуст');
    expect(p.roster.reserve.length, greaterThanOrEqualTo(2),
        reason: 'отправку надо показать на ком-то, и список должен быть списком');
    expect(p.tree.bought, isNotEmpty, reason: 'древо Эха должно быть начато');
  });

  test('демо-профиль повторим: второй дубль показывает ту же Заставу', () {
    final a = DemoProfile.build();
    final b = DemoProfile.build();

    // Без этого неудачный кусок нельзя переснять — только перемонтировать
    // весь ролик.
    expect(a.maxDepthEver, b.maxDepthEver);
    expect(a.gold, b.gold);
    expect(a.stash.length, b.stash.length);
  });

  testWidgets('кадр не замирает: камера дышит и на стоящем плане',
      (tester) async {
    // Подъезд кончается вместе с планом, и кадр, доехавший до места, дальше
    // стоял мёртво — ровно тогда, когда его начинают читать. Интерфейс сам не
    // шевелится, и неподвижная картинка неотличима от скриншота.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: TrailerCamera(
        shot: TrailerShot(zoom: 1.2, push: 0),
        child: ColoredBox(color: Color(0xFF101010)),
      ),
    ));

    Matrix4 lens() => tester
        .widget<Transform>(find
            .descendant(
                of: find.byType(TrailerCamera), matching: find.byType(Transform))
            .first)
        .transform;

    // Ждём, пока подъезд отработает: дальше двигать кадр нечему, кроме дыхания.
    await tester.pump(const Duration(seconds: 6));
    final a = lens().clone();
    await tester.pump(const Duration(milliseconds: 400));
    final b = lens().clone();

    expect(a == b, isFalse,
        reason: 'за четыреста миллисекунд кадр не сдвинулся ни на пиксель — '
            'это снимок экрана, а не съёмка');

    // И при этом не трясётся: дыхание должно быть на грани заметности.
    final shift = (a.getTranslation() - b.getTranslation()).length;
    expect(shift, lessThan(12),
        reason: 'камера гуляет на $shift точек — это уже трясущиеся руки');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('подъезд не проезжает сквозь потолок по ширине', (tester) async {
    // Найдено на записи: панель построек к концу плана лишилась первой буквы
    // у каждой строки — «Buildings» стало «uildings», «Vault» стало «ault».
    // Наезд ширину соблюдал, а подъезд считался поверх него и спокойно
    // проезжал сквозь потолок.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: TrailerCamera(
        // Подъезд нарочно велик: с прежним кодом он увёл бы масштаб далеко за
        // предел, и цель потеряла бы края.
        shot: const TrailerShot(anchor: 'wide.panel', fill: 0.25, push: 0.4),
        child: Align(
          alignment: Alignment.topCenter,
          child: TutorialAnchor(
            id: 'wide.panel',
            // Во всю ширину — как почти любая панель в игре.
            child: SizedBox(width: double.infinity, height: 200),
          ),
        ),
      ),
    ));

    await tester.pump(const Duration(seconds: 6));

    final scale = tester
        .widget<Transform>(find
            .descendant(
                of: find.byType(TrailerCamera), matching: find.byType(Transform))
            .first)
        .transform
        .getMaxScaleOnAxis();

    // Цель шириной во весь кадр: больше 1/keepWidth увеличивать её нельзя,
    // иначе края уезжают за рамку.
    expect(scale, lessThanOrEqualTo(1 / TrailerShot.keepWidth + 0.01),
        reason: 'камера увеличила цель до $scale — края срезаны');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('круг проходится целиком и заходит во все разделы',
      (tester) async {
    // Вертикальный кадр телефона, а не стандартные 800×600 теста: подписи и
    // наезды рассчитаны на 9:16.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('rift_trailer_test');
    // Windows держит файл автосохранения открытым дольше, чем живёт тест, и
    // уборка временного каталога иногда не проходит. Это не повод ронять тест.
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // пусть остаётся системе
      }
    });

    var passes = 0;
    await tester.pumpWidget(TrailerApp(
      content: content,
      store: SaveStore(dir),
      onPass: () => passes++,
    ));

    final seen = <Type>{};
    var minScale = double.infinity;
    var maxScale = 0.0;
    var darkest = 0.0;
    var widestPlate = 0.0;
    var sawCard = false;
    const screens = [
      MercenaryScreen,
      JournalScreen,
      LootSortScreen,
      EchoTreeScreen,
      PassiveTreeScreen,
      ForgeScreen,
      StashScreen,
      QuestsScreen,
    ];

    // Шаг крупный. Кадр трейлера — это вся Застава плюс наезд камеры, и
    // мелкий шаг тратит минуты на плавность, которой в тесте никто не видит.
    for (var i = 0; i < 400 && passes == 0; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      for (final screen in screens) {
        if (find.byType(screen).evaluate().isNotEmpty) seen.add(screen);
      }
      // Масштаб камеры читается прямо из матрицы: наезд, посчитанный
      // неправильно, виден только так. Раньше рамка бралась как минимум из
      // ширины и высоты, для панелей во всю ширину давала 1.0, и трейлер
      // показывал неподвижный снимок экрана.
      final lens = find.descendant(
        of: find.byType(TrailerCamera),
        matching: find.byType(Transform),
      );
      if (lens.evaluate().isNotEmpty) {
        final scale =
            tester.widget<Transform>(lens.first).transform.getMaxScaleOnAxis();
        minScale = math.min(minScale, scale);
        maxScale = math.max(maxScale, scale);
      }

      // Затемнение переходов. Без него смена экрана показывала зрителю
      // механику показа: маршрут уезжает, следом второй, камера прыгает.
      final film = find.byType(TrailerFilm);
      if (film.evaluate().isNotEmpty) {
        darkest = math.max(darkest, tester.widget<TrailerFilm>(film).veil.opacity);
      }

      // Подложка подписи. Её высота и есть то, насколько текст закрывает игру.
      final plate = find.byKey(TrailerCaptionLayer.plate);
      if (plate.evaluate().isNotEmpty) {
        widestPlate =
            math.max(widestPlate, tester.getRect(plate.first).height);
      }
      if (find.byKey(TrailerCaptionLayer.cardPlate).evaluate().isNotEmpty) {
        sawCard = true;
      }
    }

    expect(tester.takeException(), isNull);
    expect(passes, greaterThan(0), reason: 'сценарий должен дойти до конца');
    expect(seen, containsAll(screens),
        reason: 'трейлер обязан показать всю игру, а не половину');
    // Потолок наезда задаёт ширина цели, а не вкус: панели игры прижаты к
    // краям, и лишний процент увеличения срезает у списка первую букву каждой
    // строки. Отсюда и порог — он ниже прежнего нарочно.
    expect(maxScale, greaterThan(1.18),
        reason: 'камера обязана наезжать, а не показывать снимок экрана');
    expect(maxScale - minScale, greaterThan(0.12),
        reason: 'кадр обязан меняться: одинаковый масштаб весь ролик — это '
            'статичная картинка');

    expect(darkest, greaterThan(0.9),
        reason: 'переходы между экранами обязаны уходить в темноту. Иначе '
            'зритель видит, КАК показывают: маршрут уезжает вбок, следом '
            'второй, камера прыгает на новую метку, список докручивается — '
            'четыре движения на одно событие, и ни одно не про игру');

    // 1920 точек кадра. Раньше затемнение под подписью шло от края до 42 %
    // высоты — постоянная штора на две строки текста.
    expect(widestPlate, lessThan(1920 * 0.22),
        reason: 'подложка подписи закрывает пятую часть кадра или больше: '
            'показывать надо игру, а не фон под титром');
    expect(widestPlate, greaterThan(0),
        reason: 'подписи не нашлось вовсе — проверка ничего не проверила');

    expect(sawCard, isTrue,
        reason: 'ролик обязан закончиться карточкой с названием. Последний '
            'кадр с подписью в углу читается как «запись оборвалась»');

    // Снимаем дерево: контроллер держит таймер часов и автосохранения, и без
    // этого тест падает на «A Timer is still pending».
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
