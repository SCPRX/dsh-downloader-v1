package com.dsh.dshapp

import android.content.Intent
import android.speech.tts.TextToSpeech
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.util.zip.ZipFile
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {

    companion object {
        init {
            System.loadLibrary("luchui")
        }

        private const val CHANNEL = "com.dsh.dshapp/status"
        private const val BASE_PORT = 3090
        private const val MAX_TRIES = 20

        @Volatile var channel: MethodChannel? = null
        @Volatile var webServer: Process? = null
        @Volatile var sdkProc: Process? = null
        @Volatile var sdkReaderRunning = false
        @Volatile var starting = false
        @Volatile var engineReady = false
        @Volatile var engineUrl = ""
        @Volatile var activePort = BASE_PORT
        val lastLog = ArrayDeque<String>()
        val pendingRpc = ArrayList<String>()
        private val mainHandler = Handler(Looper.getMainLooper())
    }

    private fun remember(line: String) {
        if (line.isBlank()) return
        synchronized(lastLog) {
            lastLog.addLast(line)
            while (lastLog.size > 8) lastLog.removeFirst()
        }
    }

    private fun lastLogText(): String = synchronized(lastLog) { lastLog.joinToString(" ｜ ") }

    private val envDir: File get() = File(filesDir, "dsh-env")
    private val prootBin: File get() = File(envDir, "proot")
    private val loaderBin: File get() = File(envDir, "loader")
    private val rootfsDir: File get() = File(envDir, "rootfs")
    private val guestNode: File get() = File(rootfsDir, "opt/node/bin/node")
    private val guestHarness: File
        get() = File(rootfsDir, "opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js")
    private val workDir: File get() = envDir

    private var pendingPick: MethodChannel.Result? = null
    private var tts: TextToSpeech? = null
    private var speech: SpeechRecognizer? = null
    private var pendingVoice: MethodChannel.Result? = null
    private var pendingVoiceAction = false

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)

        if (android.os.Build.VERSION.SDK_INT >= 28) {
            val attrs = window.attributes
            attrs.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = attrs
        }

        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(0xFF03060A.toInt()))
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkEnv" -> result.success(isEnvReady())
                "envZipPath" -> result.success(File(cacheDir, "env_data.zip").absolutePath)
                "filesDirPath" -> result.success(filesDir.absolutePath)
                "startExtract" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_PATH", "path is empty", null)
                    } else {
                        extractEnv(File(path))
                        result.success(true)
                    }
                }
                "readEngineLog" -> result.success(readEngineLog())
                "hasBundledEnv" -> result.success(hasBundledEnv())
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        if (tts == null) {
                            tts = TextToSpeech(applicationContext) { status ->
                                if (status == TextToSpeech.SUCCESS) {
                                    tts?.language = java.util.Locale.CHINA
                                }
                            }
                        }
                        tts?.stop()
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "luchui")
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("TTS_FAIL", t.message, null)
                    }
                }
                "stopSpeak" -> {
                    try {
                        tts?.stop()
                        result.success(true)
                    } catch (t: Throwable) {
                        result.success(false)
                    }
                }
                "appInstallTime" -> {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(info.lastUpdateTime)
                    } catch (t: Throwable) {
                        result.success(0L)
                    }
                }
                "engineInfo" -> {
                    try {
                        val pkg = File(envDir, "rootfs/opt/dsh/node_modules/@deepseek-ai/dsh/package.json")
                        var version = "unknown"
                        if (pkg.exists()) {
                            val txt = pkg.readText()
                            val m = Regex("\"version\"\\s*:\\s*\"([^\"]+)\"").find(txt)
                            if (m != null) version = m.groupValues[1]
                        }
                        result.success(version)
                    } catch (t: Throwable) {
                        result.success("unknown")
                    }
                }
                "notifyDone" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        val nm = getSystemService(NotificationManager::class.java)
                        if (Build.VERSION.SDK_INT >= 26) {
                            nm.createNotificationChannel(
                                NotificationChannel("done", "回答完成", NotificationManager.IMPORTANCE_DEFAULT)
                            )
                        }
                        val builder = if (Build.VERSION.SDK_INT >= 26)
                            Notification.Builder(this, "done")
                        else
                            @Suppress("DEPRECATION") Notification.Builder(this)
                        val intent = Intent(this, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        val pi = android.app.PendingIntent.getActivity(
                            this, 1, intent,
                            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                                (if (Build.VERSION.SDK_INT >= 23) android.app.PendingIntent.FLAG_IMMUTABLE else 0)
                        )
                        builder.setSmallIcon(android.R.drawable.stat_notify_chat)
                            .setContentTitle("落锤")
                            .setContentText(if (text.length > 80) text.substring(0, 80) else text)
                            .setContentIntent(pi)
                            .setAutoCancel(true)
                        nm.notify(7, builder.build())
                        result.success(true)
                    } catch (t: Throwable) {
                        result.success(false)
                    }
                }
                "startVoice" -> {
                    try {
                        pendingVoice = result
                        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.RECORD_AUDIO), 5151
                            )
                        } else {
                            beginVoice()
                        }
                    } catch (t: Throwable) {
                        result.error("VOICE_FAIL", t.message, null)
                    }
                }
                "appVersion" -> {
                    try {
                        val pm = packageManager
                        val info = if (android.os.Build.VERSION.SDK_INT >= 33)
                            pm.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        else
                            pm.getPackageInfo(packageName, 0)
                        result.success(info.versionName ?: "")
                    } catch (t: Throwable) {
                        result.success("")
                    }
                }
                "openBatterySettings" -> {
                    try {
                        var done = false
                        val pkg = packageName
                        try {
                            val i = Intent("android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS")
                            i.data = android.net.Uri.parse("package:$pkg")
                            startActivity(i)
                            done = true
                        } catch (_: Throwable) {
                        }
                        if (!done) {
                            try {
                                startActivity(
                                    Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                )
                                done = true
                            } catch (_: Throwable) {
                            }
                        }
                        if (!done) {
                            startActivity(
                                Intent(
                                    android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    android.net.Uri.parse("package:$pkg")
                                )
                            )
                        }
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("BATTERY_SETTINGS_FAIL", t.message, null)
                    }
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        val i = Intent(Intent.ACTION_SEND)
                        i.type = "text/plain"
                        i.putExtra(Intent.EXTRA_TEXT, text)
                        startActivity(Intent.createChooser(i, "分享对话"))
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("SHARE_FAIL", t.message, null)
                    }
                }
                "resetEnv" -> {
                    try {
                        killSdk()
                        killWeb()
                        webServer?.destroy()
                        if (envDir.exists()) envDir.deleteRecursively()
                        logEngine("[reset] env removed")
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("RESET_FAIL", t.message, null)
                    }
                }
                "pickImage" -> {
                    pendingPick = result
                    try {
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT)
                        i.addCategory(Intent.CATEGORY_OPENABLE)
                        i.type = "image/*"
                        startActivityForResult(i, 4242)
                    } catch (t: Throwable) {
                        pendingPick = null
                        result.error("PICK_FAIL", t.message, null)
                    }
                }
                "runShell" -> {
                    val cmd = call.argument<String>("cmd") ?: ""
                    Thread {
                        val out = runShell(cmd)
                        mainHandler.post { result.success(out) }
                    }.start()
                }
                "installPayload" -> {
                    installPayloadAsync()
                    result.success(true)
                }
                "installBundledEnv" -> {
                    installBundledEnv()
                    result.success(true)
                }
                "startSdk" -> {
                    val apiKey = call.argument<String>("apiKey") ?: ""
                    startSdk(apiKey)
                    result.success(true)
                }
                "rpcSend" -> {
                    val line = call.argument<String>("line") ?: ""
                    rpcSend(line)
                    result.success(true)
                }
                "startWeb" -> {
                    val key = call.argument<String>("apiKey") ?: ""
                    startWeb(key)
                    result.success(true)
                }
                "engineAlive" -> result.success(sdkProc?.isAlive == true && sdkReaderRunning)
                "setEngineReady" -> {
                    engineReady = call.argument<Boolean>("ready") ?: true
                    result.success(true)
                }
                "engineReady" -> result.success(engineReady)
                "killEngine" -> {
                    killSdk()
                    engineReady = false
                    result.success(true)
                }
                "openEngine" -> {
                    val url = call.argument<String>("url") ?: "http://127.0.0.1:$activePort"
                    openEngine(url)
                    result.success(true)
                }
                "keepAlive" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val text = call.argument<String>("text")
                    if (text != null) DownloadService.currentText = text
                    if (on) startKeepAlive() else stopKeepAlive()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun beginVoice() {
        try {
            speech?.destroy()
            speech = SpeechRecognizer.createSpeechRecognizer(this)
            speech?.setRecognitionListener(object : android.speech.RecognitionListener {
                override fun onReadyForSpeech(params: android.os.Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    val r = pendingVoice
                    pendingVoice = null
                    r?.success("")
                }

                override fun onResults(results: android.os.Bundle?) {
                    val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val r = pendingVoice
                    pendingVoice = null
                    r?.success(list?.firstOrNull() ?: "")
                }

                override fun onPartialResults(partialResults: android.os.Bundle?) {}
                override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            speech?.startListening(intent)
            logEngine("[voice] listening")
        } catch (t: Throwable) {
            val r = pendingVoice
            pendingVoice = null
            r?.success("")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 5151) {
            if (grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                beginVoice()
            } else {
                val r = pendingVoice
                pendingVoice = null
                r?.success("")
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == 4242) {
            val r = pendingPick
            pendingPick = null
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    val mime = contentResolver.getType(uri) ?: "image/jpeg"
                    val ext = when {
                        mime.contains("png") -> "png"
                        mime.contains("webp") -> "webp"
                        else -> "jpg"
                    }
                    val f = File(cacheDir, "picked_" + System.currentTimeMillis() + "." + ext)
                    contentResolver.openInputStream(uri).use { input ->
                        if (input != null) {
                            f.outputStream().use { o -> input.copyTo(o) }
                        }
                    }
                    r?.success(f.absolutePath)
                } catch (t: Throwable) {
                    r?.error("PICK_FAIL", t.message, null)
                }
            } else {
                r?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (channel === MainActivity.channel) {
            channel = null
        }
        super.onDestroy()
    }

    private fun engineLogFile(): File = File(filesDir, "engine.log")

    @Synchronized
    private fun logEngine(line: String) {
        try {
            val f = engineLogFile()
            if (f.length() > 2 * 1024 * 1024) f.delete()
            f.appendText(line + "\n")
        } catch (_: Throwable) {
        }
    }

    private fun readEngineLog(): String {
        return try {
            val f = engineLogFile()
            if (!f.exists()) return "(还没有日志)"
            val text = f.readText()
            if (text.length <= 12000) text else text.substring(text.length - 12000)
        } catch (t: Throwable) {
            "读取日志失败: ${t.message}"
        }
    }

    private fun status(msg: String) {
        val ch = channel ?: return
        mainHandler.post {
            try {
                ch.invokeMethod("updateStatus", msg)
            } catch (_: Throwable) {
            }
        }
    }

    private fun fail(msg: String) {
        status(msg)
        val ch = channel ?: return
        mainHandler.post {
            try {
                ch.invokeMethod("failed", msg)
            } catch (_: Throwable) {
            }
        }
    }

    private fun notifyEvent(method: String, arg: Any?) {
        val ch = channel ?: return
        mainHandler.post {
            try {
                ch.invokeMethod(method, arg)
            } catch (_: Throwable) {
            }
        }
    }

    private fun findFreePort(): Int {
        for (i in 0 until MAX_TRIES) {
            val port = BASE_PORT + i
            if (isPortFree(port)) return port
        }
        return 0
    }

    private fun isPortFree(port: Int): Boolean = try {
        java.net.ServerSocket().use { server ->
            server.reuseAddress = true
            server.bind(java.net.InetSocketAddress("127.0.0.1", port))
        }
        true
    } catch (_: Throwable) {
        false
    }

    private fun portFromUrl(url: String): Int? = try {
        val p = Uri.parse(url).port
        if (p > 0) p else null
    } catch (_: Throwable) {
        null
    }

    private fun isEnvReady(): Boolean =
        prootBin.exists() && loaderBin.exists() && guestNode.exists() && guestHarness.exists()

    private external fun nativeDeriveKey(sigHash: ByteArray): ByteArray

    private external fun nativeDeriveIv(sigHash: ByteArray): ByteArray

    private val payloadUrl: String =
        "https://github.com/SCPRX/dsh-downloader-v1/releases/download/runtime/payload.enc"

    private fun appSignatureHash(): ByteArray {
        return try {
            val pm = packageManager
            val sigs = if (android.os.Build.VERSION.SDK_INT >= 28) {
                val info = pm.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                )
                info.signingInfo?.apkContentsSigners
                    ?: info.signingInfo?.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.GET_SIGNATURES
                ).signatures
            }
            val md = java.security.MessageDigest.getInstance("SHA-256")
            md.digest(sigs?.firstOrNull()?.toByteArray() ?: ByteArray(0))
        } catch (t: Throwable) {
            ByteArray(0)
        }
    }

    private fun installPayloadAsync() {
        Thread {
            val encFile = File(cacheDir, "payload.enc")
            val zipFile = File(cacheDir, "payload.zip")
            try {
                status("正在下载运行环境…")
                val conn = java.net.URL(payloadUrl).openConnection() as java.net.HttpURLConnection
                conn.instanceFollowRedirects = true
                conn.connectTimeout = 30000
                conn.readTimeout = 600000
                conn.setRequestProperty("User-Agent", "luchui")
                val total = conn.contentLengthLong
                var read = 0L
                var lastTick = 0L
                conn.inputStream.use { input ->
                    encFile.outputStream().use { output ->
                        val buf = ByteArray(256 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            read += n
                            if (read - lastTick > 2L * 1024 * 1024) {
                                lastTick = read
                                val mb = read / 1024 / 1024
                                val pct = if (total > 0) (read * 100 / total) else -1
                                status(
                                    if (pct >= 0) "正在下载运行环境 " + pct + "%"
                                    else "正在下载运行环境 " + mb + "MB"
                                )
                            }
                        }
                    }
                }
                status("正在解密运行环境…")
                val sigHash = appSignatureHash()
                val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    SecretKeySpec(nativeDeriveKey(sigHash), "AES"),
                    IvParameterSpec(nativeDeriveIv(sigHash))
                )
                encFile.inputStream().use { input ->
                    zipFile.outputStream().use { output ->
                        val buf = ByteArray(1024 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            val out = cipher.update(buf, 0, n)
                            if (out != null) output.write(out)
                        }
                        val tail = cipher.doFinal()
                        if (tail != null) output.write(tail)
                    }
                }
                encFile.delete()
                status("正在解包运行环境…")
                val patchDir = File(cacheDir, "patches")
                patchDir.mkdirs()
                val runtimeZip = File(cacheDir, "runtime.zip")
                ZipFile(zipFile).use { zf ->
                    for (e in zf.entries()) {
                        val name = e.name
                        if (name == "runtime.zip") {
                            zf.getInputStream(e).use { i ->
                                runtimeZip.outputStream().use { o ->
                                    i.copyTo(o, 256 * 1024)
                                }
                            }
                        } else if (name.startsWith("patches/") && !e.isDirectory) {
                            val dest = File(patchDir, name.removePrefix("patches/"))
                            zf.getInputStream(e).use { i ->
                                dest.outputStream().use { o ->
                                    i.copyTo(o, 256 * 1024)
                                }
                            }
                        }
                    }
                }
                zipFile.delete()
                extractEnv(runtimeZip)
            } catch (t: Throwable) {
                logEngine("[payload] fail: " + t.message)
                try { encFile.delete() } catch (_: Throwable) {}
                try { zipFile.delete() } catch (_: Throwable) {}
                notifyEvent("failed", "运行环境下载失败: " + t.message)
            }
        }.start()
    }

    private fun applyPatchesFromDir(dir: File) {
        val pats = listOf(
            "dsh-session-persistence-jsonl__index.js" to
                "rootfs/opt/dsh/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js",
            "dsh-attachment-local__index.js" to
                "rootfs/opt/dsh/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js"
        )
        for ((name, destRel) in pats) {
            try {
                val src = File(dir, name)
                if (!src.exists()) continue
                val dest = File(envDir, destRel)
                if (!dest.parentFile.exists()) continue
                src.copyTo(dest, overwrite = true)
                logEngine("[patch] " + destRel)
            } catch (t: Throwable) {
                logEngine("[patch] skip " + destRel + ": " + t.message)
            }
        }
    }

    private fun applyPatchesFromAssets() {
        val pats = listOf(
            "patches/dsh-session-persistence-jsonl__index.js" to
                "rootfs/opt/dsh/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js",
            "patches/dsh-attachment-local__index.js" to
                "rootfs/opt/dsh/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js"
        )
        for ((asset, destRel) in pats) {
            try {
                val dest = File(envDir, destRel)
                if (!dest.exists()) continue
                assets.open(asset).use { input ->
                    dest.outputStream().use { output ->
                        input.copyTo(output, 256 * 1024)
                    }
                }
                logEngine("[patch] " + destRel)
            } catch (t: Throwable) {
                logEngine("[patch] skip " + destRel + ": " + t.message)
            }
        }
    }

    private fun runShell(cmd: String): String {
        if (!isEnvReady()) return "环境还没装好"
        return try {
            val safe = cmd.replace("'", "'\\''")
            val full = "cd '${workDir.absolutePath}' && " +
                "export LD_LIBRARY_PATH='${envDir.absolutePath}/lib' && " +
                "export PROOT_LOADER='${envDir.absolutePath}/loader' && " +
                "export PROOT_LOADER_32='${envDir.absolutePath}/loader32' && " +
                "export PROOT_NO_SECCOMP=1 && " +
                "mkdir -p '${filesDir.absolutePath}/proot-tmp' && " +
                "export PROOT_TMP_DIR='${filesDir.absolutePath}/proot-tmp' && " +
                "exec '${prootBin.absolutePath}' -0 -r '${rootfsDir.absolutePath}' " +
                "-b /dev -b /proc -b /sys -b /system -L -w /root " +
                "/usr/bin/env HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin " +
                "/bin/bash -lc '$safe'"
            val p = ProcessBuilder("/system/bin/sh", "-c", full)
                .directory(workDir)
                .redirectErrorStream(true)
                .start()
            val sb = StringBuilder()
            val reader = BufferedReader(InputStreamReader(p.inputStream))
            var line = reader.readLine()
            while (line != null) {
                sb.append(line).append("\n")
                if (sb.length > 20000) {
                    sb.append("…(输出过长已截断)\n")
                    break
                }
                line = reader.readLine()
            }
            try {
                reader.close()
            } catch (_: Throwable) {
            }
            var waited = 0
            while (p.isAlive && waited < 90) {
                Thread.sleep(200)
                waited += 1
            }
            if (p.isAlive) {
                p.destroy()
                sb.append("\n(超时，已终止)")
            }
            sb.toString()
        } catch (t: Throwable) {
            "执行失败: " + t.message
        }
    }

    private fun hasBundledEnv(): Boolean = try {
        assets.open("runtime.zip").use { true }
    } catch (_: Throwable) {
        false
    }

    private fun installBundledEnv() {
        Thread {
            try {
                val zip = File(cacheDir, "env_data.zip")
                status("正在安装内置环境…")
                assets.open("runtime.zip").use { input ->
                    FileOutputStream(zip).use { out ->
                        val buf = ByteArray(256 * 1024)
                        var n = input.read(buf)
                        var total = 0L
                        while (n > 0) {
                            out.write(buf, 0, n)
                            total += n
                            n = input.read(buf)
                        }
                        logEngine("[bundle] copied " + total + " bytes")
                    }
                }
                extractEnv(zip)
            } catch (t: Throwable) {
                fail("内置环境安装失败: " + t.message)
            }
        }.start()
    }

    private fun extractEnv(zipFile: File) {
        Thread {
            try {
                if (!zipFile.exists()) {
                    fail("找不到下载好的环境包")
                    return@Thread
                }
                val need = zipFile.length() * 2 + 200L * 1024 * 1024
                val usable = StatFs(filesDir.absolutePath).availableBytes
                if (usable < need) {
                    fail("存储空间不足：解压大约还需要 ${need / 1024 / 1024} MB")
                    return@Thread
                }

                if (envDir.exists()) envDir.deleteRecursively()
                envDir.mkdirs()

                status("正在解压环境(耗时较长)...")
                var count = 0
                val buf = ByteArray(512 * 1024)
                val root = envDir.canonicalPath
                val linkCandidates = ArrayList<Pair<String, String>>()
                val linkLike = Regex("^[.]{0,2}/?[A-Za-z0-9@._+/-]+$")
                ZipInputStream(FileInputStream(zipFile)).use { z ->
                    while (true) {
                        val e = z.nextEntry ?: break
                        val f = File(envDir, e.name)
                        if (!f.canonicalPath.startsWith(root + File.separator)) {
                            status("跳过非法路径: ${e.name}")
                            continue
                        }
                        if (e.isDirectory) {
                            f.mkdirs()
                        } else {
                            f.parentFile?.mkdirs()
                            FileOutputStream(f).use { o ->
                                var n = z.read(buf)
                                while (n > 0) {
                                    o.write(buf, 0, n)
                                    n = z.read(buf)
                                }
                            }
                            f.setExecutable(true, false)
                            if (e.size in 1L..300L) {
                                try {
                                    val content = f.readText().trim()
                                    if (content.isNotEmpty() &&
                                        content.length <= 300 &&
                                        !content.contains('\n') &&
                                        linkLike.matches(content)
                                    ) {
                                        linkCandidates.add(f.absolutePath to content)
                                    }
                                } catch (_: Throwable) {
                                }
                            }
                            count++
                            if (count % 500 == 0) status("正在解压环境… 已解压 $count 个文件")
                        }
                    }
                }

                var execs = 0
                val execList = File(envDir, "meta/exec.list")
                if (execList.exists()) {
                    execList.forEachLine { rel ->
                        if (rel.isNotBlank()) {
                            try {
                                File(envDir, rel).setExecutable(true, false)
                                execs++
                            } catch (_: Throwable) {
                            }
                        }
                    }
                }
                status("解压完成，恢复 $execs 个可执行权限，正在恢复链接…")

                var links = 0
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    val linkList = File(envDir, "meta/links.txt")
                    if (linkList.exists()) {
                        linkList.forEachLine { line ->
                            val tab = line.indexOf('\t')
                            if (tab > 0) {
                                val rel = line.substring(0, tab)
                                val target = line.substring(tab + 1)
                                try {
                                    val f = File(envDir, rel)
                                    if (f.exists()) f.delete()
                                    f.parentFile?.mkdirs()
                                    java.nio.file.Files.createSymbolicLink(
                                        f.toPath(),
                                        java.nio.file.Paths.get(target)
                                    )
                                    links++
                                } catch (_: Throwable) {
                                }
                            }
                        }
                    }
                    for ((path, target) in linkCandidates) {
                        try {
                            val f = File(path)
                            if (f.exists()) continue
                            val t = File(f.parentFile, target)
                            if (!t.exists()) continue
                            java.nio.file.Files.createSymbolicLink(
                                f.toPath(),
                                java.nio.file.Paths.get(target)
                            )
                            links++
                        } catch (_: Throwable) {
                        }
                    }
                }
                prootBin.setExecutable(true, false)
                loaderBin.setExecutable(true, false)
                File(envDir, "loader32").setExecutable(true, false)

                if (!isEnvReady()) {
                    fail("解压完成但找不到 proot / node / 引擎入口")
                    return@Thread
                }
                status("解压完成，共 $count 个文件，恢复 $links 个链接")
                logEngine("[env] extract done, $count files, $links links")
                applyPatchesFromDir(File(cacheDir, "patches"))
                zipFile.delete()
                notifyEvent("envReady", null)
            } catch (t: Throwable) {
                logEngine("[err] extract fail: " + t.message)
                try {
                    zipFile.delete()
                } catch (_: Throwable) {
                }
                fail("解压失败: ${t.message}（坏包已删除，请重试）")
            }
        }.start()
    }    private fun patchOneFile(f: File, pairs: List<Pair<String, String>>) {
        try {
            if (!f.exists()) {
                logEngine("[patch] missing: " + f.absolutePath)
                return
            }
            var s = f.readText()
            var changed = false
            for (p in pairs) {
                if (s.contains(p.first)) {
                    s = s.replace(p.first, p.second)
                    changed = true
                }
            }
            if (changed) {
                f.writeText(s)
                logEngine("[patch] ok: " + f.name)
            } else {
                logEngine("[patch] skip(no match): " + f.name)
            }
        } catch (t: Throwable) {
            logEngine("[patch] fail " + f.name + ": " + t.message)
        }
    }

    private fun patchHarnessLinks() {
        val dyn = "await (await import(\"node:fs/promises\"))."
        patchOneFile(
            File(
                rootfsDir,
                "opt/dsh/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js"
            ),
            listOf(
                "await link(tmp, finalPath);" to (dyn + "rename(tmp, finalPath);"),
                "await internals.fs.link(staged, currentPath);" to (dyn + "rename(staged, currentPath);")
            )
        )
        patchOneFile(
            File(
                rootfsDir,
                "opt/dsh/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js"
            ),
            listOf(
                "await link(source, target);" to (dyn + "copyFile(source, target, 1);"),
                "await link(staged.path, target);" to (dyn + "copyFile(staged.path, target, 1);")
            )
        )
    }

    private fun startSdk(apiKey: String) {
        if (!isEnvReady()) {
            fail("环境还没装好")
            return
        }
        killWeb()
        killSdk()
        patchHarnessLinks()

        Thread {
            try {
                status("正在启动引擎...")
                val cmd = "cd '${workDir.absolutePath}' && " +
                    "export LD_LIBRARY_PATH='${envDir.absolutePath}/lib' && " +
                    "export PROOT_LOADER='${envDir.absolutePath}/loader' && " +
                    "export PROOT_LOADER_32='${envDir.absolutePath}/loader32' && " +
                    "export PROOT_NO_SECCOMP=1 && " +
                    "mkdir -p '${filesDir.absolutePath}/proot-tmp' && " +
                    "export PROOT_TMP_DIR='${filesDir.absolutePath}/proot-tmp' && " +
                    "exec '${prootBin.absolutePath}' -0 -r '${rootfsDir.absolutePath}' " +
                    "-b /dev -b /dev/urandom:/dev/random -b /proc -b /proc/self/fd:/dev/fd -b /sys -b /system -b /apex -b /storage/emulated/0:/sdcard -L -w /root " +
                    "/usr/bin/env HOME=/root DSH_HOME=/root/.dsh " +
                    "DEEPSEEK_API_KEY='$apiKey' " +
                    "/opt/node/bin/node --expose-internals " +
                    "/opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js --profile sdk"
                logEngine("[cmd] " + cmd)
                val p = ProcessBuilder("/system/bin/sh", "-c", cmd)
                    .directory(workDir)
                    .redirectErrorStream(false)
                    .start()
                sdkProc = p
                logEngine("[start] process launched")

                synchronized(pendingRpc) {
                    for (l in pendingRpc) {
                        try {
                            p.outputStream.write((l + "\n").toByteArray(Charsets.UTF_8))
                        } catch (_: Throwable) {
                        }
                    }
                    pendingRpc.clear()
                }
                try {
                    p.outputStream.flush()
                } catch (_: Throwable) {
                }

                Thread {
                    try {
                        BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                            sdkReaderRunning = true
                            var line = r.readLine()
                            while (line != null) {
                                remember(line)
                                logEngine("[out] " + line)
                                notifyEvent("rpcLine", line)
                                line = r.readLine()
                            }
                        }
                    } catch (_: Throwable) {
                    } finally {
                        sdkReaderRunning = false
                    }
                }.start()

                Thread {
                    try {
                        BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                            var line = r.readLine()
                            while (line != null) {
                                val s = line.trim()
                                remember(s)
                                logEngine("[err] " + s)
                                if (s.isNotEmpty()) status("底层: $s")
                                line = r.readLine()
                            }
                        }
                    } catch (_: Throwable) {
                    }
                }.start()

                Thread {
                    var waited = 0
                    while (sdkProc === p && p.isAlive && waited < 900) {
                        Thread.sleep(30000)
                        waited += 30
                        if (sdkProc === p && p.isAlive) {
                            logEngine("[wait] alive ${waited}s, no rpc yet")
                        }
                    }
                }.start()

                val code = p.waitFor()
                logEngine("[exit] code=" + code)
                if (sdkProc === p) {
                    fail("引擎退出(code=$code)：${lastLogText()}")
                }
            } catch (t: Throwable) {
                logEngine("[err] start fail: " + t.message)
                fail("引擎启动失败: ${t.message}")
            }
        }.start()
    }

    private fun rpcSend(line: String) {
        Thread {
            try {
                val p = sdkProc
                if (p == null) {
                    synchronized(pendingRpc) { pendingRpc.add(line) }
                    return@Thread
                }
                val out = p.outputStream
                out.write((line + "\n").toByteArray(Charsets.UTF_8))
                out.flush()
            } catch (_: Throwable) {
            }
        }.start()
    }

    private fun killSdk() {
        try {
            sdkProc?.destroy()
        } catch (_: Throwable) {
        }
        sdkProc = null
        sdkReaderRunning = false
        engineReady = false
        synchronized(pendingRpc) { pendingRpc.clear() }
    }

    private fun startWeb(apiKey: String) {
        if (!isEnvReady()) {
            fail("环境还没装好")
            return
        }
        killSdk()
        patchHarnessLinks()
        if (webServer?.isAlive == true) {
            Thread { awaitReady(webServer) }.start()
            return
        }
        if (starting) return
        starting = true

        Thread {
            try {
                status("正在启动网页版引擎...")
                val port = findFreePort()
                activePort = port
                val cmd = "cd '${workDir.absolutePath}' && " +
                    "export LD_LIBRARY_PATH='${envDir.absolutePath}/lib' && " +
                    "export PROOT_LOADER='${envDir.absolutePath}/loader' && " +
                    "export PROOT_LOADER_32='${envDir.absolutePath}/loader32' && " +
                    "export PROOT_NO_SECCOMP=1 && " +
                    "mkdir -p '${filesDir.absolutePath}/proot-tmp' && " +
                    "export PROOT_TMP_DIR='${filesDir.absolutePath}/proot-tmp' && " +
                    "exec '${prootBin.absolutePath}' -0 -r '${rootfsDir.absolutePath}' " +
                    "-b /dev -b /dev/urandom:/dev/random -b /proc -b /proc/self/fd:/dev/fd -b /sys -b /system -b /apex -b /storage/emulated/0:/sdcard -L -w /root " +
                    "/usr/bin/env HOME=/root DSH_HOME=/root/.dsh " +
                    "DEEPSEEK_API_KEY='$apiKey' " +
                    "/opt/node/bin/node --expose-internals " +
                    "/opt/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js web --no-open --port $port"
                logEngine("[webcmd] " + cmd)
                val p = ProcessBuilder("/system/bin/sh", "-c", cmd)
                    .directory(workDir)
                    .redirectErrorStream(true)
                    .start()
                webServer = p
                pumpLog(p)
                awaitReady(p)
            } catch (t: Throwable) {
                fail("网页版启动失败: ${t.message}")
            } finally {
                starting = false
            }
        }.start()
    }

    private fun killWeb() {
        try {
            webServer?.destroy()
        } catch (_: Throwable) {
        }
        webServer = null
    }

    private fun pumpLog(p: Process) {
        Thread {
            try {
                BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                    var line = r.readLine()
                    while (line != null) {
                        val s = line.trim()
                        remember(s)
                        logEngine("[web] " + s)
                        val m = Regex("https?://(?:127\\.0\\.0\\.1|localhost|0\\.0\\.0\\.0):\\d+[^\\s\"'<>]*").find(s)
                        if (m != null) {
                            engineUrl = m.value
                                .replace("0.0.0.0", "127.0.0.1")
                                .replace("localhost", "127.0.0.1")
                            portFromUrl(engineUrl)?.let { activePort = it }
                        }
                        line = r.readLine()
                    }
                }
            } catch (_: Throwable) {
            }
        }.start()
    }

    private fun awaitReady(p: Process?) {
        status("等待引擎响应...")
        val deadline = System.currentTimeMillis() + 180_000
        while (System.currentTimeMillis() < deadline) {
            if (activePort == 0 && engineUrl.isNotEmpty()) {
                portFromUrl(engineUrl)?.let { activePort = it }
            }
            if (activePort != 0 && portOpen(activePort)) {
                val readyAt = System.currentTimeMillis()
                while (engineUrl.isEmpty() &&
                    System.currentTimeMillis() - readyAt < 3000
                ) {
                    Thread.sleep(100)
                }
                status("引擎已就绪")
                notifyEvent(
                    "webReady",
                    if (engineUrl.isNotEmpty()) engineUrl
                    else "http://127.0.0.1:$activePort/?token="
                )
                return
            }
            if (p != null && !p.isAlive) {
                fail("引擎已退出：${lastLogText()}")
                return
            }
            try {
                Thread.sleep(200)
            } catch (_: InterruptedException) {
                return
            }
        }
        fail("引擎启动超时（180 秒）")
    }

    private fun portOpen(port: Int = activePort): Boolean = try {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 300) }
        true
    } catch (_: Throwable) {
        false
    }

    private fun openEngine(url: String) {
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (t: Throwable) {
            fail("打不开浏览器: ${t.message}")
        }
    }

    private fun startKeepAlive() {
        try {
            val intent = Intent(this, DownloadService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Throwable) {
        }
    }

    private fun stopKeepAlive() {
        try {
            stopService(Intent(this, DownloadService::class.java))
        } catch (_: Throwable) {
        }
    }
}

class DownloadService : android.app.Service() {
    companion object {
        @Volatile var currentText: String = "正在准备环境，请勿清理后台…"
    }

    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = "落锤"
        val text = currentText
        val icon = android.R.drawable.stat_sys_download
        val pi = android.app.PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(android.app.NotificationManager::class.java)
            nm?.createNotificationChannel(
                android.app.NotificationChannel(
                    "dsh_download",
                    "运行状态",
                    android.app.NotificationManager.IMPORTANCE_LOW
                )
            )
            val n = android.app.Notification.Builder(this, "dsh_download")
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .build()
            startForeground(1001, n)
        } else {
            val n = android.app.Notification.Builder(this)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .build()
            startForeground(1001, n)
        }
        try {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock = pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "dsh:download")
            wakeLock?.acquire()
        } catch (_: Throwable) {
        }
        return android.app.Service.START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            wakeLock?.release()
        } catch (_: Throwable) {
        }
        wakeLock = null
        super.onDestroy()
    }
}
