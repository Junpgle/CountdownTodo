import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep Android's versionCode deterministic and aligned with pubspec.yaml.
// For example: 5.6.18 -> 5618 and 5.7.0 -> 5700.
fun versionCodeFromVersionName(versionName: String): Int {
    val parts = versionName.substringBefore("+").substringBefore("-").split(".")
    val major = parts.getOrNull(0)?.toIntOrNull()
    val minor = parts.getOrNull(1)?.toIntOrNull()
    val patch = parts.getOrNull(2)?.toIntOrNull()

    require(major != null && minor != null && patch != null) {
        "Invalid versionName '$versionName'; expected major.minor.patch"
    }
    require(major in 0..999 && minor in 0..9 && patch in 0..99) {
        "Version '$versionName' cannot be encoded as major*1000 + minor*100 + patch"
    }

    val versionCode = major * 1000 + minor * 100 + patch
    require(versionCode > 0) { "versionCode must be greater than 0" }
    return versionCode
}

// 1. 加载签名配置文件 (key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.math_quiz.junpgle.com.math_quiz_app"
    compileSdk = 37
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
        versionCode = versionCodeFromVersionName(flutter.versionName)
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // 🚀 测试版包名增加 .debug 后缀，实现生产/测试环境共存
            applicationIdSuffix = ".debug"

            // 调试模式引用正式签名 (仅当配置了正式签名时)
            if (keystoreProperties.containsKey("storeFile")) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }

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

    // 按 CPU 架构拆分 APK 以减小体积（仅 Release 启用，Debug 跳过以加快构建）
    splits {
        abi {
            val isReleaseBuild = gradle.startParameter.taskNames.any {
                it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
            }
            isEnable = isReleaseBuild
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true  // 同时生成包含所有架构的通用 APK
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.work:work-runtime-ktx:2.10.5")
    implementation("com.google.android.material:material:1.12.0")
    implementation("com.google.android.play:age-signals:0.0.4")
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
