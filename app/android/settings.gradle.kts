pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false

    // Аналитика. `apply false` здесь и условное применение в `app/` — плагин
    // ОБЯЗАН быть применён только когда рядом лежит `google-services.json`:
    // без файла он валит сборку целиком («File google-services.json is
    // missing»), а файла нет ни в репозитории, ни у нового разработчика.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
