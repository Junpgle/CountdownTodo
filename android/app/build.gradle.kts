import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 1. 加载签名配置文件 (key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.math_quiz.junpgle.com.math_quiz_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // 使用 create("release") 解决 "SigningConfig with name 'release' not found" 错误
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.math_quiz.junpgle.com.math_quiz_app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // 调试模式引用正式签名
            signingConfig = signingConfigs.getByName("release")

            // 调试模式下关闭混淆和资源压缩以加快构建并解决冲突
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            // 确保 release 使用正确的签名配置
            signingConfig = signingConfigs.getByName("release")

            // 如果需要开启资源压缩 (isShrinkResources)，则必须开启代码混淆 (isMinifyEnabled)
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // 按 CPU 架构拆分 APK 以减小体积
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true  // 同时生成包含所有架构的通用 APK
        }
    }
}

kotlin {
    compilerOptions {
        // 修复：将复杂的枚举引用改为简单的字符串 "17"，避免 Unresolved reference: dsl 错误
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("io.github.d4viddf:hyperisland_kit:0.4.3")
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")

    // 加载 libs 目录下的本地依赖
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar", "*.aar"))))
}

android {
    buildFeatures {
        buildConfig = true
    }
}