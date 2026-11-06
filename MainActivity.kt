package com.dsh.dshapp

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.*
import java.util.zip.ZipInputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dsh.dshapp/status"
    private lateinit var channel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 🚨 1. 原生层强制全屏，隐藏系统状态栏
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "startExtract") {
                val path = call.argument<String>("path")
                if (path != null) { extractAndStart(File(path)); result.success(true) } else { result.error("ERROR", "Path is null", null) }
            }
        }
    }

    private fun extractAndStart(zipFile: File) {
        fun sendStatus(msg: String) { runOnUiThread { if (::channel.isInitialized) channel.invokeMethod("updateStatus", msg) } }
        Executors.newSingleThreadExecutor().execute {
            try {
                val d = File(filesDir, "dsh-env")
                if (!d.exists()) d.mkdirs()
                sendStatus("正在解压环境(耗时较长)...")
                val z = ZipInputStream(FileInputStream(zipFile))
                var e = z.nextEntry
                val b = ByteArray(8192)
                while (e != null) {
                    val f = File(d, e.name)
                    if (e.isDirectory) f.mkdirs() else {
                        f.parentFile?.mkdirs()
                        val o = FileOutputStream(f)
                        var l: Int
                        while (z.read(b).also { l = it } > 0) o.write(b, 0, l)
                        o.close(); f.setExecutable(true)
                    }
                    e = z.nextEntry
                }
                z.close(); zipFile.delete()
                sendStatus("准备执行 Node...")
                val n = File(d, "node")
                if (n.exists()) {
                    n.setExecutable(true)
                    val p = ProcessBuilder("/system/bin/sh", "-c", "LD_LIBRARY_PATH=${d.absolutePath} ${n.absolutePath} --expose-internals apps/cli/src/bin.ts web")
                    p.directory(File(d, "deepseek-harness"))
                    p.redirectErrorStream(true)
                    val process = p.start()
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    var line: String?
                    while (reader.readLine().also { line = it } != null) { sendStatus("底层: $line") }
                } else { sendStatus("找不到 node 文件") }
                runOnUiThread { if (::channel.isInitialized) channel.invokeMethod("ready", null) }
            } catch (e: Exception) { sendStatus("崩溃异常: ${e.message}") }
        }
    }
}
