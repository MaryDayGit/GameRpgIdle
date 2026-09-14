plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase подключается, только если ключи проекта лежат на месте.
//
// `google-services.json` — секрет: он не в репозитории и не у того, кто
// склонировал его первый раз. Плагин Google этого не прощает и роняет сборку
// с сообщением про отсутствующий файл — то есть без ключей игра перестала бы
// СОБИРАТЬСЯ, а не просто молчать в аналитику. Правило игры обратное:
// аналитики может не быть, игра должна быть (`docs/11-ANALYTICS.md` §2).
//
// Проверка по файлу, а не по флагу сборки, потому что флаг придётся не
// забыть, а файл либо лежит, либо нет.
val googleServices = file("google-services.json")
if (googleServices.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json не найден — сборка без аналитики " +
            "(docs/11-ANALYTICS.md §2)",
    )
}

android {
    namespace = "com.riftgame.rift_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Требование flutter_local_notifications: планировщик уведомлений
        // использует java.time, которого нет на старых Android.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.riftgame.rift_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
