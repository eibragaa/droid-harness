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
import java.io.FileReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DroidHarness/Main"
        private const val CHANNEL = "dev.droidharness/bridge"
        private const val LLM_PORT = 8080

        // Em Termux: /data/data/com.termux/files/home/llama.cpp/build/bin/llama-server
        private val LLAMA_PATHS = listOf(
            "/data/data/com.termux/files/home/llama.cpp/build/bin/llama-server",
            "/data/data/com.termux/files/home/droid-harness/llama-portable/build/bin/llama-server",
            "/data/data/com.termux/files/usr/bin/llama-server",
        )
    }

    private var methodChannel: MethodChannel? = null
    private var llmProcess: Process? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getHardwareProfile" -> result.success(hardwareProfile())
                    "getModelsDir" -> result.success(modelsDir().absolutePath)
                    "getStorageInfo" -> result.success(storageInfo())
                    "runCommand" -> {
                        val cmd = call.argument<String>("command") ?: ""
                        result.success(runShell(cmd))
                    }
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

    // ── LLM Server lifecycle ─────────────────────────────────────

    private fun findBinary(name: String): String {
        // Procura o binario em paths conhecidos
        val searchPaths = LLAMA_PATHS + listOf(
            "/system/bin/$name",
            "/system/xbin/$name",
            "/data/data/com.termux/files/usr/bin/$name",
        )
        for (path in searchPaths) {
            val f = File(path)
            if (f.exists() && f.canExecute()) return f.absolutePath
        }
        // Procura recursivamente em diretorios comuns
        val dirs = listOf(
            "/data/data/com.termux/files/home",
            "/data/data/com.termux/files/usr/bin",
        )
        for (dir in dirs) {
            val d = File(dir)
            if (!d.isDirectory) continue
            d.walkTopDown().forEach { f ->
                if (f.name == name && f.canExecute()) return f.absolutePath
            }
        }
        return ""
    }

    private fun startLlm(modelPath: String): Map<String, Any> {
        // Para processo existente
        stopLlm()

        // Encontra o binario
        val binary = findBinary("llama-server")
        if (binary.isEmpty()) {
            return mapOf("ok" to false, "error" to "llama-server not found. Build it in Termux:\n  cd ~/droid-harness/llama-portable\n  bash build-termux.sh")
        }

        // Verifica se o modelo existe
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            return mapOf("ok" to false, "error" to "Model not found: $modelPath")
        }

        try {
            val cmd = arrayOf(
                binary,
                "-m", modelPath,
                "--host", "127.0.0.1",
                "--port", LLM_PORT.toString(),
                "-ngl", "99",
                "-c", "2048",
                "--mlock",
                "--no-mmap",
            )
            val pb = ProcessBuilder(*cmd)
            File(filesDir, "llm").mkdirs()
            pb.directory(File(filesDir, "llm"))
            pb.redirectErrorStream(true)
            llmProcess = pb.start()

            // Le output em background para log
            Thread {
                try {
                    val reader = BufferedReader(InputStreamReader(llmProcess!!.inputStream))
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        Log.d(TAG, "llama: $line")
                    }
                } catch (_: Exception) {}
            }.apply { isDaemon = true }.start()

            // Aguarda alguns segundos e verifica se subiu
            Thread.sleep(2000)
            if (llmProcess?.isAlive == true) {
                val pid = getPid(llmProcess!!)
                return mapOf("ok" to true, "pid" to (pid ?: 0), "port" to LLM_PORT)
            }
            return mapOf("ok" to false, "error" to "Process exited immediately")
        } catch (e: Exception) {
            return mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    private fun getPid(p: Process): Int {
        return try {
            // Tenta extrair PID do toString() ex: "Process[pid=12345, ...]"
            val str = p.toString()
            val m = Regex("pid=(\\d+)").find(str)
            if (m != null) return m.groupValues[1].toInt()
            // Fallback: ler /proc/self/stat via o proprio processo
            val r = Runtime.getRuntime().exec(arrayOf("sh", "-c", "cat /proc/\$PPID/stat 2>/dev/null | cut -d' ' -f4 || echo 0"))
            r.inputStream.bufferedReader().readText().trim().toIntOrNull() ?: p.hashCode()
        } catch (_: Exception) { p.hashCode() }
    }

    private fun stopLlm(): Map<String, Any> {
        val p = llmProcess
        if (p != null && p.isAlive) {
            p.destroyForcibly()
            llmProcess = null
            return mapOf("ok" to (true as Any), "killed" to (true as Any))
        }
        return mapOf("ok" to (true as Any), "killed" to (false as Any))
    }

    private fun llmStatus(): Map<String, Any> {
        val alive = llmProcess?.isAlive == true
        return mapOf(
            "running" to (alive as Any),
            "pid" to ((if (alive) getPid(llmProcess!!) else 0) as Any),
            "port" to (LLM_PORT as Any),
        )
    }

    private fun runShell(command: String): Map<String, Any> {
        return try {
            val proc = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            val stdout = proc.inputStream.bufferedReader().readText().trim()
            val stderr = proc.errorStream.bufferedReader().readText().trim()
            val exit = proc.waitFor()
            mapOf("exitCode" to exit, "stdout" to stdout, "stderr" to stderr)
        } catch (e: Exception) {
            mapOf("exitCode" to -1, "stdout" to "", "stderr" to (e.message ?: ""))
        }
    }

    // ── Hardware Detection ───────────────────────────────────────

    private fun hardwareProfile(): Map<String, Any> {
        val memInfo = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)?.let {
            it.getMemoryInfo(memInfo)
        }
        val totalRamMb = memInfo.totalMem / (1024 * 1024)
        val availRamMb = memInfo.availMem / (1024 * 1024)
        val cores = Runtime.getRuntime().availableProcessors()
        val cpuName = readCpuInfo()
        val gpu = if (hasVulkan()) "vulkan" else "cpu"
        val profile = when { totalRamMb < 7000 || cores <= 4 -> "weak"
            totalRamMb < 11000 -> "balanced"
            else -> "strong" }
        val modelId = when (profile) { "weak" -> "gemma-3-1b-q4_k_m"
            "balanced" -> "qwen3-1.7b-q4_k_m"
            else -> "qwen2.5-coder-1.5b-q4_k_m" }
        val llmBin = findBinary("llama-server")
        return mapOf(
            "profile" to profile, "totalRamMb" to totalRamMb, "availRamMb" to availRamMb,
            "cores" to cores, "cpuName" to cpuName, "gpu" to gpu,
            "recommendedModelId" to modelId,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "llamaServerPath" to llmBin,
            "llamaServerInstalled" to (llmBin.isNotEmpty()),
        )
    }

    private fun modelsDir(): File = File(filesDir, "models").also { it.mkdirs() }

    private fun storageInfo(): Map<String, Any> {
        val stat = StatFs(modelsDir().path)
        val free = stat.availableBlocksLong * stat.blockSizeLong
        val total = stat.blockCountLong * stat.blockSizeLong
        return mapOf("modelsDir" to modelsDir().absolutePath,
            "freeBytes" to free, "freeMb" to free / (1048576))
    }

    private fun readCpuInfo(): String {
        try {
            BufferedReader(FileReader("/proc/cpuinfo")).use { r ->
                var l = r.readLine()
                while (l != null) {
                    if (l.startsWith("Hardware") || l.startsWith("model name")) {
                        val p = l.split(":").map { it.trim() }
                        if (p.size >= 2) return p[1]
                    }
                    l = r.readLine()
                }
            }
        } catch (_: Exception) {}
        return Build.MODEL
    }

    private fun hasVulkan(): Boolean {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", "vulkaninfo --summary 2>/dev/null || echo no"))
            val o = p.inputStream.bufferedReader().readText().trim()
            p.waitFor()
            o.isNotEmpty() && o != "no"
        } catch (_: Exception) { false }
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
            Intent.ACTION_VIEW -> {
                val uri = intent.data?.toString() ?: return null
                mapOf("type" to "DEEP_LINK", "uri" to uri)
            }
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
