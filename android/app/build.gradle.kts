plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.atsedeteguhan.atsede_teguhan_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.atsedeteguhan.atsede_teguhan_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Audit M3: release signing from environment / Gradle properties.
    // Set these (never commit a keystore or its passwords):
    //   KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
    // as Gradle properties (android/key.properties or ~/.gradle/gradle.properties)
    // or environment variables. Without them the build falls back to the
    // debug key so local `flutter run --release` still works — but a
    // debug-signed release MUST NOT be distributed or put on Play Store.
    val keystorePath = providers.gradleProperty("KEYSTORE_PATH")
        .orElse(providers.environmentVariable("KEYSTORE_PATH")).orNull
    val keystorePassword = providers.gradleProperty("KEYSTORE_PASSWORD")
        .orElse(providers.environmentVariable("KEYSTORE_PASSWORD")).orNull
    val keyAlias = providers.gradleProperty("KEY_ALIAS")
        .orElse(providers.environmentVariable("KEY_ALIAS")).orNull
    val keyPassword = providers.gradleProperty("KEY_PASSWORD")
        .orElse(providers.environmentVariable("KEY_PASSWORD")).orNull

    signingConfigs {
        create("release") {
            if (keystorePath != null && keystorePassword != null &&
                keyAlias != null && keyPassword != null) {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
            // If any value is missing this config stays empty and the
            // release block below falls back to the debug config.
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePath != null && keystorePassword != null &&
                keyAlias != null && keyPassword != null) {
                signingConfigs.getByName("release")
            } else {
                // WARNING: debug-signed release — local testing only.
                signingConfigs.getByName("debug")
            }
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
