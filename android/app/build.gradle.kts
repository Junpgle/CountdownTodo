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
        // 【关键修改】将 flutter.minSdkVersion 改为 26，以满足 hyperisland_kit 0.4.3 的最低要求
        minSdk = 26
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
    implementation("io.github.d4viddf:hyperisland_kit:0.4.3")
    implementation("dev.rikka.shizuku:api:13.1.5") // 添加 Shizuku 依赖
    implementation("dev.rikka.shizuku:provider:13.1.5")
}