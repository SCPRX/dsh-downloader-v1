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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dsh.dshapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 28
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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
                val conn = java.net.URI(u).toURL().openConnection()
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
