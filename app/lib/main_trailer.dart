import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rift/core/model/lang.dart';

import 'data/content.dart';
import 'data/save_store.dart';
import 'trailer/trailer_app.dart';

/// Вход для съёмки трейлера. Не игра, и в сборку игры не попадает.
///
/// Отдельная точка входа, а не режим внутри игры: экран, включаемый из
/// настроек, надо поддерживать, переводить и объяснять игроку. Здесь нечего
/// объяснять — это инструмент, живущий столько же, сколько ролик.
///
/// ```bash
/// cd app && flutter run --release -t lib/main_trailer.dart -d android
/// ```
///
/// `--release` обязателен. В отладочной сборке Flutter дёргается, и на записи
/// это выглядит как лаги игры, а не как лаги отладки.
///
/// Язык ролика — английский: рынок, на который он снимается, англоязычный.
/// Переключается одной строкой, подписи сценария двуязычные, игра переводится
/// целиком — русский дубль снимается без правки кадров.
const _lang = Lang.en;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Кадр вертикальный и без системного мусора: строка состояния и кнопки
  // навигации в трейлере не нужны и портят вертикальный кадр.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  Lang.current = _lang;
  final content = await ContentBundle.load(lang: _lang);
  content.pack.apply();

  // Свой каталог сейва. Заставу показывает настоящий `GameController`, а он
  // умеет автосохранение, — без этой строки трейлер записал бы демо-профиль
  // поверх боевого сейва на том же телефоне.
  final docs = await getApplicationDocumentsDirectory();
  final store = SaveStore(Directory('${docs.path}/trailer'));

  runApp(TrailerApp(content: content, store: store, lang: _lang));
}
