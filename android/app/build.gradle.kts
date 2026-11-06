import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ua.mhrd.mhrd"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ua.mhrd.mhrd"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 7+: під цю версію зібрано модуль сеансу (native/session/build-android.sh).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Модуль сеансу й тунель зібрано лише під 64 біти — 32-бітний пристрій APK не встановить
        // (а не встановить і впаде без них).
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Модуль сеансу libmhrd_session.so — виконуваний файл: Android запускає його лише з розпакованої
    // теки бібліотек застосунку, тож бібліотеки не лишаємо стиснутими в APK.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // libdartjni (пакет jni) Flutter додає й під 32 біти — прибираємо, щоб не було теки armeabi-v7a.
            excludes += listOf("lib/armeabi-v7a/**", "lib/armeabi/**", "lib/x86/**")
        }
    }

    // Підпис релізу: android/key.properties (не в git) — storeFile, storePassword, keyAlias, keyPassword.
    // Ключ сам лежить поза репозиторієм. Без файла (збирання для перевірки) — ключ налагодження.
    val keyProperties = Properties()
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) keyFile.inputStream().use { keyProperties.load(it) }
    signingConfigs {
        if (keyFile.exists()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Тема AppCompat (styles.xml) — без неї вікно відбитка (local_auth) на Android 8 і старших падає.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
