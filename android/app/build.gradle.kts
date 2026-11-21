import java.net.URI
import java.net.URLConnection

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dsh.dshapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 构建号：优先用 CI 的构建次数（自动递增），本地构建回退到 pubspec 的值
        val ciBuildNumber = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull()
        applicationId = "com.dsh.dshapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 28
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = ciBuildNumber ?: flutter.versionCode
        versionName = if (ciBuildNumber != null) {
            // 全自动：主版本每 10000 次构建 +1（从 2 起），次版本每 100 次 +1，修订号为余数
            val b = ciBuildNumber
            val major = 2 + b / 10000
            val minor = (b / 100) % 100
            val patch = b % 100
            major.toString() + "." + minor.toString() + "." + patch.toString()
        } else {
            flutter.versionName
        }
    }

    signingConfigs {
        create("release") {
            val ksPath = System.getenv("RELEASE_KEYSTORE_PATH")
            if (ksPath != null && File(ksPath).exists()) {
                storeFile = File(ksPath)
                storePassword = System.getenv("RELEASE_STORE_PASSWORD")
                keyAlias = System.getenv("RELEASE_KEY_ALIAS")
                keyPassword = System.getenv("RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("RELEASE_KEYSTORE_PATH") != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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


// 把运行时包内置进 APK 的 assets（首次打开免下载）
val runtimeMirrors = listOf(
    "https://ghfast.top/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip",
    "https://gh-proxy.com/https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip",
    "https://github.com/SCPRX/dsh-downloader-v1/releases/download/v1/apk.zip"
)
val bundleRuntime = tasks.register("bundleRuntime") {
    val out = File(projectDir, "src/main/assets/runtime.zip")
    outputs.file(out)
    doLast {
        if (out.exists() && out.length() > 100_000_000L) {
            println("runtime already bundled: " + out.length())
            return@doLast
        }
        out.parentFile.mkdirs()
        var ok = false
        for (u in runtimeMirrors) {
            try {
                println("fetch runtime: " + u)
                val conn: URLConnection = URI(u).toURL().openConnection()
                conn.connectTimeout = 30000
                conn.readTimeout = 300000
                conn.getInputStream().use { input ->
                    out.outputStream().use { o -> input.copyTo(o, 256 * 1024) }
                }
                if (out.length() > 100_000_000L) { ok = true; break }
            } catch (e: Throwable) {
                println("fetch failed: " + e.message)
            }
        }
        if (!ok) throw GradleException("runtime download failed")
        println("runtime bundled: " + out.length())
    }
}
tasks.named("preBuild") { dependsOn(bundleRuntime) }

android {
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}
