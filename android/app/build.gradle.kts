plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.math_quiz.junpgle.com.math_quiz_app"
    compileSdk = 36 // 保持 36 以支持最新 API
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.math_quiz.junpgle.com.math_quiz_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36 // 确保目标 SDK 为 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.13.1")
    // 【关键新增】添加 Google Material 库依赖，解决 Theme.Material3 找不到的问题
    implementation("com.google.android.material:material:1.12.0")
}