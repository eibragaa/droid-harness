package dev.droidharness.droid_harness_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.FileReader
import java.io.InputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DroidHarness/Main"
        private const val CHANNEL = "dev.droidharness/bridge"
        private const val LLM_PORT = 8080

        // URL do pre-built llama.cpp para Android ARM64
        // Release: https://github.com/ggml-org/llama.cpp/releases/tag/b9128
        const val ENGINE_URL = "https://github.com/ggml-org/llama.cpp/releases/download/b9128/llama-b9128-bin-android-arm64.tar.gz"

        // Paths onde procurar o binario
        val BINARY_PATHS = listOf(
            "llama-server",     // engine dir (relativo)
            "/data/data/com.termux/files/home/llama.cpp/build/bin/llama-server",
            "/data/data/com.termux/files/home/droid-harness/llama-portable/build/bin/llama-server",
            "/data/data/com.termux/files/usr/bin/llama-server",
        )
    }

    private var methodChannel: MethodChannel? = null
    private var llmProcess: Process? = null
    private var engineDir: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getHardwareProfile" -> result.success(hardwareProfile())
                    "getModelsDir" -> result.success(modelsDir().absolutePath)
                    "getEngineDir" -> result.success(engineDir()?.absolutePath ?: "")
                    "getStorageInfo" -> result.success(storageInfo())
                    "findBinary" -> {
                        val name = call.argument<String>("name") ?: ""
                        result.success(findBinary(name))
                    }
                    "startLlm" -> {
                        val modelPath = call.argument<String>("modelPath") ?: ""
                        result.success(startLlm(modelPath))
                    }
                    "stopLlm" -> {
                        result.success(stopLlm())
                    }
                    "llmStatus" -> {
                        result.success(llmStatus())
                    }
                    "downloadEngine" -> {
                        val url = call.argument<String>("url") ?: ENGINE_URL
                        downloadEngineAsync(url, result)
                    }
                    "startBridgeService" -> { startBridgeForegroundService(); result.success(true) }
                    "stopBridgeService" -> { stopBridgeForegroundService(); result.success(true) }
                    "getInitialIntent" -> {
                        val d = extractIntentData(intent)
                        result.success(d ?: mapOf("type" to "none"))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "MC error: ${call.method}", e)
                result.error("ERROR", e.message, null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        try { startBridgeForegroundService() } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    // ── Engine (llama.cpp pre-built) ─────────────────────────────

    private fun engineDir(): File {
        if (engineDir == null) {
            engineDir = File(filesDir, "engine").also { it.mkdirs() }
        }
        return engineDir!!
    }

    private fun findLocalBinary(name: String): String {
        val dir = engineDir()
        val f = File(dir, name)
        if (f.exists() && f.canExecute()) return f.absolutePath
        return ""
    }

    private fun downloadEngineAsync(url: String, result: MethodChannel.Result) {
        Thread {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 60000
                conn.instanceFollowRedirects = true
                conn.connect()

                val totalLen = conn.contentLengthLong
                val input: InputStream = conn.inputStream
                val dir = engineDir()
                val tgzFile = File(dir, "llama.tar.gz")

                // Download com progresso
                val out = FileOutputStream(tgzFile)
                val buf = ByteArray(8192)
                var read: Int
                var written = 0L
                while (input.read(buf).also { read = it } != -1) {
                    out.write(buf, 0, read)
                    written += read
                    if (totalLen > 0 && written % (8192 * 64) == 0L) {
                        val pct = (written * 100 / totalLen).toInt()
                        Log.d(TAG, "Engine download: $pct% ($written/$totalLen)")
                    }
                }
                out.close()
                input.close()

                // Extrai tarball
                Log.d(TAG, "Extracting engine to ${dir.absolutePath}")
                val proc = Runtime.getRuntime().exec(arrayOf("tar", "-xzf", tgzFile.absolutePath, "-C", dir.absolutePath))
                val exit = proc.waitFor()
                tgzFile.delete()

                if (exit != 0) {
                    val err = proc.errorStream.bufferedReader().readText().trim()
                    result.error("EXTRACT_FAILED", err, null)
                    return@Thread
                }

                // Torna executavel
                val binary = File(dir, "llama-server")
                if (binary.exists()) {
                    binary.setExecutable(true)
                    Log.d(TAG, "Engine installed: ${binary.absolutePath}")
                    runOnUiThread { result.success(binary.absolutePath) }
                } else {
                    result.error("BINARY_NOT_FOUND", "llama-server not found in extracted files", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Engine download failed", e)
                result.error("DOWNLOAD_FAILED", e.message, null)
            }
        }.apply { isDaemon = true }.start()
    }

    // ── LLM Server lifecycle ─────────────────────────────────────

    private fun findBinary(name: String): String {
        // Primeiro procura no engine dir (pre-built)
        val local = findLocalBinary(name)
        if (local.isNotEmpty()) return local

        // Depois nos paths conhecidos (Termux)
        for (path in BINARY_PATHS.drop(1)) { // skip first (relative)
            val f = File(path.replace("llama-server", name))
            if (f.exists() && f.canExecute()) return f.absolutePath
        }
        return ""
    }

    private fun startLlm(modelPath: String): Map<String, Any> {
        stopLlm()
        val binary = findBinary("llama-server")
        if (binary.isEmpty()) {
            return mapOf("ok" to (false as Any), "error" to ("llama-server not found.\n\nBuild in Termux:\n  cd ~/droid-harness/llama-portable\n  bash build-termux.sh\n\nOR tap the Download Engine button." as Any))
        }
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            return mapOf("ok" to (false as Any), "error" to ("Model not found: $modelPath" as Any))
        }
        try {
            val cmd = arrayOf(binary, "-m", modelPath,
                "--host", "127.0.0.1", "--port", LLM_PORT.toString(),
                "-ngl", "99", "-c", "2048", "--mlock", "--no-mmap")
            File(filesDir, "llm").mkdirs()
            val pb = ProcessBuilder(*cmd)
            pb.directory(File(filesDir, "llm"))
            pb.redirectErrorStream(true)
            llmProcess = pb.start()
            Thread {
                try {
                    val r = BufferedReader(InputStreamReader(llmProcess!!.inputStream))
                    var l: String?
                    while (r.readLine().also { l = it } != null) Log.d(TAG, "llama: $l")
                } catch (_: Exception) {}
            }.apply { isDaemon = true }.start()
            Thread.sleep(2000)
            if (llmProcess?.isAlive == true) {
                return mapOf("ok" to (true as Any), "pid" to (getPid(llmProcess!!) as Any), "port" to (LLM_PORT as Any))
            }
            return mapOf("ok" to (false as Any), "error" to ("Process exited immediately" as Any))
        } catch (e: Exception) {
            return mapOf("ok" to (false as Any), "error" to ((e.message ?: "Unknown error") as Any))
        }
    }

    private fun getPid(p: Process): Int {
        return try {
            val str = p.toString()
            val m = Regex("pid=(\\d+)").find(str)
            if (m != null) return m.groupValues[1].toInt()
            val r = Runtime.getRuntime().exec(arrayOf("sh", "-c", "cat /proc/\$PPID/stat 2>/dev/null | cut -d' ' -f4 || echo 0"))
            r.inputStream.bufferedReader().readText().trim().toIntOrNull() ?: p.hashCode()
        } catch (_: Exception) { p.hashCode() }
    }

    private fun stopLlm(): Map<String, Any> {
        val p = llmProcess
        if (p != null && p.isAlive) { p.destroyForcibly(); llmProcess = null }
        return mapOf("ok" to (true as Any), "killed" to ((p?.isAlive == true) as Any))
    }

    private fun llmStatus(): Map<String, Any> {
        val alive = llmProcess?.isAlive == true
        return mapOf("running" to (alive as Any), "pid" to ((if (alive) getPid(llmProcess!!) else 0) as Any), "port" to (LLM_PORT as Any))
    }

    // ── Hardware Detection ───────────────────────────────────────

    private fun hardwareProfile(): Map<String, Any> {
        val memInfo = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)?.let { it.getMemoryInfo(memInfo) }
        val totalRamMb = memInfo.totalMem / (1024 * 1024)
        val cores = Runtime.getRuntime().availableProcessors()
        val profile = when { totalRamMb < 7000 || cores <= 4 -> "weak"
            totalRamMb < 11000 -> "balanced"
            else -> "strong" }
        val modelId = when (profile) { "weak" -> "gemma-3-1b-q4_k_m"
            "balanced" -> "qwen3-1.7b-q4_k_m"
            else -> "qwen2.5-coder-1.5b-q4_k_m" }
        val llmBin = findBinary("llama-server")
        val engineBin = findLocalBinary("llama-server")
        return mapOf(
            "profile" to (profile as Any), "totalRamMb" to (totalRamMb as Any),
            "cores" to (cores as Any),
            "recommendedModelId" to (modelId as Any),
            "device" to ("${Build.MANUFACTURER} ${Build.MODEL}" as Any),
            "llamaServerPath" to (llmBin as Any),
            "llamaServerInstalled" to (llmBin.isNotEmpty() as Any),
            "engineInstalled" to (engineBin.isNotEmpty() as Any),
        )
    }

    private fun modelsDir(): File = File(filesDir, "models").also { it.mkdirs() }

    private fun storageInfo(): Map<String, Any> {
        val stat = StatFs(modelsDir().path)
        val free = stat.availableBlocksLong * stat.blockSizeLong
        return mapOf("modelsDir" to (modelsDir().absolutePath as Any),
            "freeMb" to ((free / 1048576).toInt() as Any))
    }

    // ── Intent Handling ───────────────────────────────────────────

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val data = extractIntentData(intent) ?: return
        methodChannel?.invokeMethod(data["type"] as String, data)
    }

    private fun extractIntentData(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("image/") == true) {
                    val uri = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.toString() ?: return null
                    mapOf("type" to ("SHARED_FILE" as Any), "mimeType" to ((intent.type ?: "image/*") as Any), "uri" to ((copyToCache(uri) ?: uri) as Any))
                } else if (intent.type?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: return null
                    mapOf("type" to ("SHARED_TEXT" as Any), "text" to (text as Any))
                } else null
            }
            Intent.ACTION_VIEW -> { val uri = intent.data?.toString() ?: return null
                mapOf("type" to ("DEEP_LINK" as Any), "uri" to (uri as Any)) }
            else -> null
        }
    }

    private fun copyToCache(uriString: String): String? {
        return try {
            val src = android.net.Uri.parse(uriString)
            val input = contentResolver.openInputStream(src) ?: return null
            val dir = File(cacheDir, "shared").also { it.mkdirs() }
            val out = File(dir, "shared_${System.currentTimeMillis()}.tmp")
            out.outputStream().use { o -> input.copyTo(o) }; input.close()
            FileProvider.getUriForFile(this, "$packageName.fileprovider", out).toString()
        } catch (e: Exception) { Log.e(TAG, "cache", e); null }
    }

    private fun startBridgeForegroundService() {
        val i = Intent(this, BridgeForegroundService::class.java).apply { action = BridgeForegroundService.ACTION_START }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
    }

    private fun stopBridgeForegroundService() {
        startService(Intent(this, BridgeForegroundService::class.java).apply { action = BridgeForegroundService.ACTION_STOP })
    }
}
