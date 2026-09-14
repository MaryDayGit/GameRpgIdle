import 'package:flutter/material.dart';

/// Палитра игры.
///
/// Одна на все экраны. До неё цвет задавался на месте: сто шестьдесят восемь
/// литералов `Color(0x…)` и столько же оттенков `Colors.whiteNN` по двадцати
/// файлам. Каждый экран был «тёмным и тёплым» по-своему, а вторичный текст —
/// `white38` на коричневом — давал контраст около 3:1, то есть ниже порога,
/// при котором мелкий текст читается на солнце.
///
/// Правило контраста здесь не вкусовое: [inkFaint] — самый тусклый цвет, в
/// который разрешено писать текст, и даже он держит не меньше 4.5:1 на
/// [surface]. Всё, что тусклее, — только для линий и декора.
abstract final class RiftColors {
  // --- Земля и поверхности -------------------------------------------------

  /// Фон экрана: самая глубокая темнота, из неё всё поднимается.
  static const ground = Color(0xFF130E0C);

  /// Карточка, лист, диалог.
  static const surface = Color(0xFF1D1613);

  /// Поднятая поверхность: поле, чип, клетка, строка под пальцем.
  static const raised = Color(0xFF281F1B);

  /// Самая светлая поверхность: выбранное, нажатое.
  static const lifted = Color(0xFF342823);

  /// Линия: рамка карточки, разделитель.
  static const line = Color(0xFF3A2D27);

  /// Линия, которую должно быть видно: контур кнопки, рамка поля.
  static const lineStrong = Color(0xFF5A4739);

  // --- Текст ---------------------------------------------------------------

  /// Основной текст. Не чистый белый: на тёмно-коричневом он режет глаз и
  /// выглядит светящимся.
  static const ink = Color(0xFFF3E9DF);

  /// Вторичный текст: пояснения, подписи строк. Около 9:1 на [surface].
  static const inkMuted = Color(0xFFC4B4A6);

  /// Третичный: подсказки, единицы, «из 70». Около 5:1 — нижняя граница.
  static const inkFaint = Color(0xFF9A897C);

  /// Недоступное. Текстом — только рядом с доступным аналогом.
  static const inkDisabled = Color(0xFF6B5D53);

  // --- Акценты -------------------------------------------------------------

  /// Угли: главное действие игры — отправить, забрать, купить.
  static const ember = Color(0xFFE8804F);

  /// Тёмная сторона углей: текст на кнопке.
  static const emberDeep = Color(0xFF3A1709);

  /// Золото — валюта и только валюта.
  static const gold = Color(0xFFEBC06A);

  /// Эхо — вторая валюта. Холодный фиолетовый, чтобы две цены на одном
  /// экране не путались ни по цвету, ни по значку.
  static const echo = Color(0xFFB5A3FF);

  /// Осколки и крафт.
  static const shard = Color(0xFF7FD1C7);

  // --- Смысл ---------------------------------------------------------------

  /// Хорошо: награда, прибавка.
  static const good = Color(0xFF9BD17F);

  /// Плохо: плата, опасность, минус.
  static const bad = Color(0xFFF08A6C);

  /// Внимание: почти кончилось, стоит заметить.
  static const warn = Color(0xFFF2B65E);

  /// Нейтральная информация.
  static const info = Color(0xFF7FB3E8);

  /// Мана в бою.
  static const mana = Color(0xFF6F9EF0);

  /// Здоровье в бою.
  static const health = Color(0xFF8CCB6E);

  // --- Стихии и теги -------------------------------------------------------
  //
  // Те же оттенки, что у вспышек и цифр урона в бою (`game/vfx.dart`), только
  // приглушённые до читаемости текстом. Тег «Огонь» в описании умения и огонь
  // на арене обязаны быть одним цветом: иначе игрок, собравший сборку вокруг
  // стихии, не узнаёт её, когда она наконец случается.

  static const fire = Color(0xFFF0874F);
  static const cold = Color(0xFF7CC8E6);
  static const lightning = Color(0xFFE8C95A);
  static const voidTone = Color(0xFFB48EF2);
  static const physical = Color(0xFFD6C9B6);
  static const arcane = Color(0xFF6FC4A4);
}

/// Шкала текста.
///
/// Ступени, а не «размер по месту». Прежние 11–13 точек были нормой для всего
/// подряд: название вещи, её свойства и сноска под ней — одним кеглем, и глаз
/// не находил, с чего начать. Нижняя ступень поднята до 12.5: ниже этого
/// кириллица на телефоне превращается в серую строчку.
abstract final class RiftText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Крупный заголовок и главное число экрана.
  static const display = TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: RiftColors.ink,
    letterSpacing: -0.3,
  );

  /// Заголовок карточки.
  static const title = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: RiftColors.ink,
  );

  /// Имя в строке: вещь, наёмник, узел.
  static const heading = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: RiftColors.ink,
  );

  /// Основной текст.
  static const body = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: RiftColors.ink,
  );

  /// Пояснение под именем.
  static const small = TextStyle(
    fontSize: 13.5,
    height: 1.38,
    color: RiftColors.inkMuted,
  );

  /// Сноска, единица, счётчик.
  static const caption = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    color: RiftColors.inkFaint,
  );

  /// Заголовок раздела: прописными, с разрядкой. Отделяет разделы, не споря
  /// с заголовками карточек.
  static const overline = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
    color: RiftColors.inkFaint,
  );

  /// Число в статистике.
  static const stat = TextStyle(
    fontSize: 20,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: RiftColors.ink,
    fontFeatures: _tabular,
  );

  /// Меняющееся число в строке: таймер, цена, проценты.
  static const number = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: RiftColors.ink,
    fontFeatures: _tabular,
  );
}

/// Размеры, которые повторяются.
abstract final class RiftSize {
  static const radius = 16.0;
  static const radiusSmall = 10.0;

  /// Высота главной кнопки. 48 — минимальная цель для большого пальца.
  static const button = 48.0;

  static const pad = 16.0;
  static const gap = 12.0;
}

/// Тема приложения — одна на всю игру.
///
/// [fontFamily] задаётся только снимкам экранов в тестах: стили компонентов
/// (кнопки, заголовок, строки списка) не наследуют семейство от текста темы,
/// и без явного семейства тест рисует их квадратами.
ThemeData riftTheme({String? fontFamily}) {
  TextStyle f(TextStyle s) =>
      fontFamily == null ? s : s.copyWith(fontFamily: fontFamily);

  final scheme = ColorScheme.fromSeed(
    seedColor: RiftColors.ember,
    brightness: Brightness.dark,
  ).copyWith(
    primary: RiftColors.ember,
    onPrimary: RiftColors.emberDeep,
    secondary: RiftColors.gold,
    onSecondary: RiftColors.emberDeep,
    tertiary: RiftColors.echo,
    error: RiftColors.bad,
    surface: RiftColors.surface,
    onSurface: RiftColors.ink,
    onSurfaceVariant: RiftColors.inkMuted,
    surfaceContainerLowest: RiftColors.ground,
    surfaceContainerLow: RiftColors.surface,
    surfaceContainer: RiftColors.surface,
    surfaceContainerHigh: RiftColors.raised,
    surfaceContainerHighest: RiftColors.lifted,
    outline: RiftColors.lineStrong,
    outlineVariant: RiftColors.line,
  );

  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(RiftSize.radiusSmall + 2)),
  );

  const buttonText = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  final base = ThemeData(
    fontFamily: fontFamily,
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: RiftColors.ground,
    canvasColor: RiftColors.ground,
    dividerColor: RiftColors.line,
    textTheme: base.textTheme
        .apply(bodyColor: RiftColors.ink, displayColor: RiftColors.ink)
        .copyWith(
          headlineSmall: f(RiftText.display),
          titleLarge: f(RiftText.title),
          titleMedium: f(RiftText.heading),
          titleSmall: f(RiftText.heading.copyWith(fontSize: 15)),
          bodyLarge: f(RiftText.body),
          bodyMedium: f(RiftText.body.copyWith(fontSize: 14.5)),
          bodySmall: f(RiftText.small),
          labelLarge: f(buttonText),
          labelMedium: f(RiftText.caption.copyWith(fontWeight: FontWeight.w600)),
          labelSmall: f(RiftText.caption),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: RiftColors.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: RiftColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: f(TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: RiftColors.ink,
        letterSpacing: -0.2,
      )),
      iconTheme: IconThemeData(color: RiftColors.inkMuted, size: 24),
      actionsIconTheme: IconThemeData(color: RiftColors.inkMuted, size: 24),
    ),
    cardTheme: CardThemeData(
      color: RiftColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RiftSize.radius),
        side: const BorderSide(color: RiftColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RiftColors.ember,
        foregroundColor: RiftColors.emberDeep,
        disabledBackgroundColor: RiftColors.raised,
        disabledForegroundColor: RiftColors.inkDisabled,
        minimumSize: const Size(64, RiftSize.button),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: f(buttonText),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RiftColors.ink,
        disabledForegroundColor: RiftColors.inkDisabled,
        minimumSize: const Size(64, RiftSize.button),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: RiftColors.lineStrong),
        textStyle: f(buttonText),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: RiftColors.ember,
        minimumSize: const Size(48, 44),
        textStyle: f(buttonText),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: RiftColors.inkMuted,
        minimumSize: const Size(44, 44),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: RiftColors.raised,
      selectedColor: RiftColors.lifted,
      disabledColor: RiftColors.surface,
      side: const BorderSide(color: RiftColors.line),
      labelStyle: f(TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: RiftColors.ink,
      )),
      secondaryLabelStyle: f(TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: RiftColors.ink,
      )),
      iconTheme: const IconThemeData(color: RiftColors.ember, size: 18),
      checkmarkColor: RiftColors.ember,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RiftSize.radiusSmall),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: RiftColors.inkMuted,
      textColor: RiftColors.ink,
      titleTextStyle: f(RiftText.heading),
      subtitleTextStyle: f(RiftText.small),
      contentPadding: EdgeInsets.symmetric(horizontal: RiftSize.pad),
      minVerticalPadding: 10,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: RiftColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: f(RiftText.title.copyWith(fontSize: 20)),
      contentTextStyle: f(RiftText.body.copyWith(color: RiftColors.inkMuted)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RiftSize.radius + 4),
        side: const BorderSide(color: RiftColors.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: RiftColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: RiftColors.surface,
      dragHandleColor: RiftColors.lineStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: RiftColors.lifted,
      contentTextStyle: f(RiftText.body),
      actionTextColor: RiftColors.ember,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RiftSize.radiusSmall + 2),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: RiftColors.ember,
      linearTrackColor: RiftColors.raised,
      circularTrackColor: RiftColors.raised,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: RiftColors.ember,
      inactiveTrackColor: RiftColors.raised,
      thumbColor: RiftColors.ember,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? RiftColors.emberDeep
              : RiftColors.inkFaint),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? RiftColors.ember
              : RiftColors.raised),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? RiftColors.ember
              : RiftColors.lineStrong),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? RiftColors.ember
              : RiftColors.inkFaint),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: RiftColors.raised,
        foregroundColor: RiftColors.inkMuted,
        selectedBackgroundColor: RiftColors.ember,
        selectedForegroundColor: RiftColors.emberDeep,
        side: const BorderSide(color: RiftColors.line),
        textStyle: f(TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: RiftColors.line,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: RiftColors.lifted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RiftColors.lineStrong),
      ),
      textStyle: f(RiftText.small.copyWith(color: RiftColors.ink)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: RiftColors.inkMuted,
      collapsedIconColor: RiftColors.inkFaint,
      textColor: RiftColors.ink,
      collapsedTextColor: RiftColors.ink,
    ),
  );
}
