import java.util.Properties
import java.io.FileInputStream

val dotenv = Properties()
// .env 파일은 mobile/ 폴더에 있음 (android/의 상위 폴더)
val dotenvFile = rootProject.file("../.env")
if (dotenvFile.exists()) {
    dotenvFile.inputStream().use { dotenv.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.reviewmaps.mobile"
    // flutter_local_notifications 23, permission_handler 13 요구사항
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 패키지에 필요한 core library desugaring 활성화
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.reviewmaps.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Google Play 대상 API 수준 요구사항: Android 16(API 36) 이상 타겟팅 필수
        // Flutter SDK 기본값에 의존하지 않도록 명시적으로 고정
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders.putAll(
            mapOf(
                "NAVER_MAP_CLIENT_ID" to (dotenv["NAVER_MAP_CLIENT_ID"] ?: ""),
                "NAVER_MAP_CLIENT_SECRET" to (dotenv["NAVER_MAP_CLIENT_SECRET"] ?: ""),
                "NAVER_APP_KEY" to (dotenv["NAVER_APP_KEY"] ?: ""),
                "NAVER_APP_SECRET" to (dotenv["NAVER_APP_SECRET"] ?: ""),
                "KAKAO_NATIVE_APP_KEY" to (dotenv["KAKAO_NATIVE_APP_KEY"] ?: ""),
            )
        )
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            signingConfig = signingConfigs.getByName("release")

            // ProGuard 규칙 적용
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    // Core library desugaring (flutter_local_notifications 필요)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Unity Ads SDK
    implementation("com.unity3d.ads:unity-ads:4.21.0")
    // Unity Ads Mediation Adapter
    implementation("com.google.ads.mediation:unity:4.21.0.0")
}
