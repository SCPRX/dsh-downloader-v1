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
        private const val PORT = 3080
    }

    private lateinit var channel: MethodChannel

    @Volatile private var server: Process? = null
    @Volatile private var starting = false

    private val envDir: File get() = File(filesDir, "dsh-env")
    private val nodeBin: File get() = File(envDir, "node")
    private val cliEntry: File get() = File(envDir, "deepseek-harness/apps/cli/src/bin.ts")
    private val workDir: File get() = File(envDir, "deepseek-harness")

    override fun onCreate(savedInstanceState: Bundle?) {
        // 必须在 super.onCreate 之前设置，让 Flutter 内容铺满整个窗口（含状态栏区域），
        // 这样星空背景能一直画到屏幕最顶端，不会留黑边
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
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
                "startServer" -> {
                    startServer()
                    result.success(true)
                }
                "startExtract" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_PATH", "path is empty", null)
                    } else {
                        extractAndStart(File(path))
                        result.success(true)
                    }
                }
                "openEngine" -> {
                    openEngine()
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

    // ---------- 下载时挂前台服务，避免切到后台/锁屏被系统杀掉 ----------

    private fun startKeepAlive() {
        try {
            val intent = Intent(this, DownloadService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (t: Throwable) {
            // 忽略，下载本身照常进行
        }
    }

    private fun stopKeepAlive() {
        try {
            stopService(Intent(this, DownloadService::class.java))
        } catch (t: Throwable) {
            // 忽略
        }
    }

    // ---------- 给 Dart 的状态回传 ----------

    private fun status(msg: String) {
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod("updateStatus", msg)
        }
    }

    private fun ready() {
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod("ready", null)
        }
    }

    private fun fail(msg: String) {
        status(msg)
        runOnUiThread {
            if (this::channel.isInitialized) channel.invokeMethod("failed", msg)
        }
    }

    // ---------- 环境检查 ----------

    private fun isEnvReady(): Boolean = nodeBin.exists() && cliEntry.exists()

    // ---------- 解压 ----------

    private fun extractAndStart(zipFile: File) {
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
                startServer()
            } catch (t: Throwable) {
                fail("解压失败: ${t.message}")
            }
        }.start()
    }

    // ---------- 启动引擎 ----------

    private fun startServer() {
        if (server?.isAlive == true) {
            Thread { awaitReady(server) }.start()
            return
        }
        if (starting) return
        starting = true

        Thread {
            try {
                if (!isEnvReady()) {
                    fail("环境还没装好，无法启动引擎")
                    return@Thread
                }
                status("正在启动引擎...")
                val cmd = "LD_LIBRARY_PATH='${envDir.absolutePath}' " +
                    "exec '${nodeBin.absolutePath}' --expose-internals apps/cli/src/bin.ts web"
                val p = ProcessBuilder("/system/bin/sh", "-c", cmd)
                    .directory(workDir)
                    .redirectErrorStream(true)
                    .start()
                server = p
                pumpLog(p)
                awaitReady(p)
            } catch (t: Throwable) {
                fail("引擎启动失败: ${t.message}")
            } finally {
                starting = false
            }
        }.start()
    }

    private fun pumpLog(p: Process) {
        Thread {
            try {
                BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                    var line = r.readLine()
                    while (line != null) {
                        val s = line.trim()
                        val low = s.lowercase()
                        if (s.isNotEmpty() && (
                                low.contains("error") || low.contains("fail") ||
                                    low.contains("listen") || low.contains("http") ||
                                    low.contains("port") || low.contains("warn")
                                )
                        ) {
                            status("底层: $s")
                        }
                        line = r.readLine()
                    }
                }
            } catch (ex: Throwable) {
                // 进程结束时 readLine 会抛，忽略
            }
        }.start()
    }

    /** 等到 3080 端口真的能连上，才算引擎就绪；不再等 node 退出。 */
    private fun awaitReady(p: Process?) {
        status("等待引擎响应...")
        val deadline = System.currentTimeMillis() + 180_000
        while (System.currentTimeMillis() < deadline) {
            if (portOpen()) {
                status("引擎已就绪")
                ready()
                return
            }
            if (p != null && !p.isAlive) {
                fail("引擎进程已退出，请重试")
                return
            }
            try {
                Thread.sleep(400)
            } catch (ex: InterruptedException) {
                return
            }
        }
        fail("引擎启动超时（180 秒）")
    }

    private fun portOpen(): Boolean = try {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", PORT), 300) }
        true
    } catch (ex: Throwable) {
        false
    }

    private fun openEngine() {
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("http://127.0.0.1:$PORT"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (t: Throwable) {
            fail("打不开浏览器: ${t.message}")
        }
    }
}

/**
 * 下载/解压期间的前台服务：挂一个通知，让系统把进程当成「正在干活」，
 * 切到后台或锁屏时不会被当缓存进程杀掉，下载和解压就能继续跑。
 */
class DownloadService : android.app.Service() {
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = "原生 DSH"
        val text = "正在准备环境，请勿清理后台…"
        val icon = android.R.drawable.stat_sys_download
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
                .build()
            startForeground(1001, n)
        } else {
            val n = android.app.Notification.Builder(this)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .build()
            startForeground(1001, n)
        }
        // 屏幕熄灭时保持 CPU 不睡，下载/解压才不会被掐（服务销毁时释放）
        try {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock = pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "dsh:download")
            wakeLock?.acquire()
        } catch (t: Throwable) {
            // 忽略
        }
        return android.app.Service.START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            wakeLock?.release()
        } catch (t: Throwable) {
            // 忽略
        }
        wakeLock = null
        super.onDestroy()
    }
}
