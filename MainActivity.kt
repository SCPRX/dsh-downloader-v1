package com.dsh.dshapp

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
        private const val CHANNEL = "com.dsh.dshapp/status"
        /** 起始端口；被占用就往后找 */
        private const val BASE_PORT = 3090
        /** 最多往后找多少个端口 */
        private const val MAX_TRIES = 20
    }

    private lateinit var channel: MethodChannel

    /** 网页模式（dsh web）的进程 */
    @Volatile private var webServer: Process? = null

    /** 原生模式（dsh --profile sdk）的进程 */
    @Volatile private var sdkProc: Process? = null

    @Volatile private var starting = false
    @Volatile private var engineUrl: String = ""
    /** 实际使用的端口（自动挑的）；0 = 交给系统分配，待从日志读取 */
    @Volatile private var activePort: Int = BASE_PORT
    private val lastLog = ArrayDeque<String>()

    /** 记住最近几行引擎输出，失败时直接显示给用户 */
    private fun remember(line: String) {
        if (line.isBlank()) return
        lastLog.addLast(line)
        while (lastLog.size > 8) lastLog.removeFirst()
    }

    private fun lastLogText(): String = lastLog.joinToString(" ｜ ")

    private val envDir: File get() = File(filesDir, "dsh-env")
    private val nodeBin: File get() = File(envDir, "node")
    private val cliEntry: File get() = File(envDir, "deepseek-harness/apps/cli/src/bin.ts")
    private val workDir: File get() = File(envDir, "deepseek-harness")

    override fun onCreate(savedInstanceState: Bundle?) {
        // 必须在 super.onCreate 之前设置，让 Flutter 内容铺满整个窗口（含状态栏区域），
        // 这样星空背景能一直画到屏幕最顶端，不会留黑边
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)

        // 允许内容铺进挖孔屏区域，否则竖屏顶部、横屏摄像头那一侧会被系统留黑边
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
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
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
                "installLibs" -> {
                    val libsPath = call.argument<String>("path")
                    if (libsPath.isNullOrBlank()) {
                        result.error("BAD_PATH", "path is empty", null)
                    } else {
                        installLibs(File(libsPath))
                        result.success(true)
                    }
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
                    startWeb()
                    result.success(true)
                }
                "openEngine" -> {
                    val url = call.argument<String>("url") ?: "http://127.0.0.1:$activePort"
                    openEngine(url)
                    result.success(true)
                }
                "keepAlive" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) startKeepAlive() else stopKeepAlive()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------- 状态回传 ----------

    private fun status(msg: String) {
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod("updateStatus", msg)
        }
    }

    private fun fail(msg: String) {
        status(msg)
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod("failed", msg)
        }
    }

    private fun notifyEvent(method: String, arg: Any?) {
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod(method, arg)
        }
    }

    // ---------- 端口工具 ----------

    /** 从 BASE_PORT 开始往后找第一个能绑上的端口；都占着就返回 0（交给系统分配） */
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
            server.bind(InetSocketAddress("127.0.0.1", port))
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

    // ---------- 环境检查 ----------

    private fun isEnvReady(): Boolean = nodeBin.exists() && cliEntry.exists()

    // ---------- 解压 ----------

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
                val buf = ByteArray(64 * 1024)
                val root = envDir.canonicalPath
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
                            count++
                            if (count % 300 == 0) status("正在解压环境… 已解压 $count 个文件")
                        }
                    }
                }
                nodeBin.setExecutable(true, false)

                if (!isEnvReady()) {
                    fail("解压完成但在包里找不到 node 或 deepseek-harness")
                    return@Thread
                }
                status("解压完成，共 $count 个文件")
                zipFile.delete()
                notifyEvent("envReady", null)
            } catch (t: Throwable) {
                fail("解压失败: ${t.message}")
            }
        }.start()
    }

    // ---------- 安装 node 缺的系统库（libz/libssl/libicu 等） ----------

    private fun installLibs(zipFile: File) {
        Thread {
            try {
                if (!zipFile.exists()) {
                    fail("找不到运行库补丁包")
                    return@Thread
                }
                status("正在安装运行库...")
                val buf = ByteArray(64 * 1024)
                val root = envDir.canonicalPath
                ZipInputStream(FileInputStream(zipFile)).use { z ->
                    while (true) {
                        val e = z.nextEntry ?: break
                        val f = File(envDir, e.name)
                        if (!f.canonicalPath.startsWith(root + File.separator) &&
                            f.canonicalPath != root
                        ) {
                            continue
                        }
                        if (e.isDirectory) {
                            f.mkdirs()
                            continue
                        }
                        f.parentFile?.mkdirs()
                        FileOutputStream(f).use { o ->
                            var n = z.read(buf)
                            while (n > 0) {
                                o.write(buf, 0, n)
                                n = z.read(buf)
                            }
                        }
                    }
                }
                zipFile.delete()
                status("运行库安装完成")
                notifyEvent("libsReady", null)
            } catch (t: Throwable) {
                fail("运行库安装失败: ${t.message}")
            }
        }.start()
    }

    // ---------- 原生模式：dsh --profile sdk（stdio JSON-RPC） ----------

    private fun startSdk(apiKey: String) {
        if (!isEnvReady()) {
            fail("环境还没装好")
            return
        }
        killWeb()
        killSdk()

        Thread {
            try {
                status("正在启动引擎...")
                val cmd = "cd '${workDir.absolutePath}' && " +
                    "export LD_LIBRARY_PATH='${envDir.absolutePath}' && " +
                    "export HOME='${filesDir.absolutePath}' && " +
                    "export DSH_HOME='${filesDir.absolutePath}/.dsh' && " +
                    "export OPENSSL_CONF=/dev/null && " +
                    "export DEEPSEEK_API_KEY='$apiKey' && " +
                    "exec '${nodeBin.absolutePath}' --expose-internals apps/cli/src/bin.ts --profile sdk"
                val p = ProcessBuilder("/system/bin/sh", "-c", cmd)
                    .directory(workDir)
                    .redirectErrorStream(false)
                    .start()
                sdkProc = p

                // stdout：JSON-RPC 每一行
                Thread {
                    try {
                        BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                            var line = r.readLine()
                            while (line != null) {
                                remember(line)
                                notifyEvent("rpcLine", line)
                                line = r.readLine()
                            }
                        }
                    } catch (_: Throwable) {
                    }
                }.start()

                // stderr：引擎日志
                Thread {
                    try {
                        BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                            var line = r.readLine()
                            while (line != null) {
                                val s = line.trim()
                                remember(s)
                                if (s.isNotEmpty()) status("底层: $s")
                                line = r.readLine()
                            }
                        }
                    } catch (_: Throwable) {
                    }
                }.start()

                val code = p.waitFor()
                if (sdkProc === p) {
                    fail("引擎退出(code=$code)：${lastLogText()}")
                }
            } catch (t: Throwable) {
                fail("引擎启动失败: ${t.message}")
            }
        }.start()
    }

    private fun rpcSend(line: String) {
        Thread {
            try {
                val p = sdkProc ?: return@Thread
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
    }

    // ---------- 网页模式：dsh web（自动端口 + 不开浏览器 + 抓 token 地址） ----------

    private fun startWeb() {
        if (!isEnvReady()) {
            fail("环境还没装好")
            return
        }
        killSdk()
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
                    "export LD_LIBRARY_PATH='${envDir.absolutePath}' && " +
                    "export HOME='${filesDir.absolutePath}' && " +
                    "export DSH_HOME='${filesDir.absolutePath}/.dsh' && " +
                    "export OPENSSL_CONF=/dev/null && " +
                    "exec '${nodeBin.absolutePath}' --expose-internals apps/cli/src/bin.ts web --no-open --port $port"
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
            // 端口交给系统分配时，先从引擎日志里把端口读出来
            if (activePort == 0 && engineUrl.isNotEmpty()) {
                portFromUrl(engineUrl)?.let { activePort = it }
            }
            if (activePort != 0 && portOpen(activePort)) {
                // 端口通了，最多再等 3 秒拿带 token 的完整地址
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

    // ---------- 下载/解压时的前台服务 ----------

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

/**
 * 下载/解压期间的前台服务：挂一个通知，让系统把进程当成「正在干活」，
 * 切到后台或锁屏时不会被当缓存进程杀掉。
 */
class DownloadService : android.app.Service() {
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = "原生 DSH"
        val text = "正在准备环境，请勿清理后台…"
        val icon = android.R.drawable.stat_sys_download
        // 点通知回到 App
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
                    "下载",
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
        // 屏幕熄灭时保持 CPU 不睡（服务销毁时释放）
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
