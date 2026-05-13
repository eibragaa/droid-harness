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

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DroidHarness/Main"
        private const val CHANNEL = "dev.droidharness/bridge"
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        )
        methodChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getHardwareProfile" -> result.success(hardwareProfile())
                    "getModelsDir" -> result.success(modelsDir().absolutePath)
                    "getStorageInfo" -> result.success(storageInfo())
                    "startBridgeService" -> {
                        startBridgeForegroundService(); result.success(true)
                    }
                    "stopBridgeService" -> {
                        stopBridgeForegroundService(); result.success(true)
                    }
                    "getInitialIntent" -> {
                        val d = extractIntentData(intent)
                        result.success(d ?: mapOf("type" to "none"))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "MethodChannel error: ${call.method}", e)
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

    // ── Hardware Detection (Android API) ──────────────────────────

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
        val arch = System.getProperty("os.arch") ?: ""

        // Profile matching (same logic as model-profile.sh)
        val profile = when {
            totalRamMb < 7000 || cores <= 4 -> "weak"
            totalRamMb < 11000 -> "balanced"
            else -> "strong"
        }

        val modelId = when (profile) {
            "weak" -> "gemma-3-1b-q4_k_m"
            "balanced" -> "qwen3-1.7b-q4_k_m"
            else -> "qwen2.5-coder-1.5b-q4_k_m"
        }

        return mapOf(
            "profile" to profile,
            "totalRamMb" to totalRamMb,
            "availRamMb" to availRamMb,
            "cores" to cores,
            "cpuName" to cpuName,
            "gpu" to gpu,
            "arch" to arch,
            "recommendedModelId" to modelId,
            "androidApi" to Build.VERSION.SDK_INT,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }

    private fun modelsDir(): File {
        val dir = File(filesDir, "models")
        dir.mkdirs()
        return dir
    }

    private fun storageInfo(): Map<String, Any> {
        val dir = modelsDir()
        val stat = StatFs(dir.path)
        val free = stat.availableBlocksLong * stat.blockSizeLong
        val total = stat.blockCountLong * stat.blockSizeLong
        return mapOf(
            "modelsDir" to dir.absolutePath,
            "freeBytes" to free,
            "totalBytes" to total,
            "freeMb" to free / (1024 * 1024),
        )
    }

    private fun readCpuInfo(): String {
        try {
            BufferedReader(FileReader("/proc/cpuinfo")).use { reader ->
                var line = reader.readLine()
                while (line != null) {
                    if (line.startsWith("Hardware") || line.startsWith("model name")) {
                        val parts = line.split(":").map { it.trim() }
                        if (parts.size >= 2) return parts[1]
                    }
                    line = reader.readLine()
                }
            }
        } catch (_: Exception) {}
        return Build.MODEL
    }

    private fun hasVulkan(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(
                arrayOf("sh", "-c", "command -v vulkaninfo 2>/dev/null && vulkaninfo --summary 2>/dev/null || echo no")
            )
            val output = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()
            output.isNotEmpty() && output != "no"
        } catch (_: Exception) {
            false
        }
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
                    val uri = intent.getParcelableExtra<android.net.Uri>(
                        Intent.EXTRA_STREAM
                    )?.toString() ?: return null
                    mapOf("type" to "SHARED_FILE", "mimeType" to (intent.type ?: "image/*"), "uri" to (copyToCache(uri) ?: uri))
                } else if (intent.type?.startsWith("text/") == true) {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                        ?: intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: return null
                    mapOf("type" to "SHARED_TEXT", "text" to text)
                } else null
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data?.toString() ?: return null
                mapOf("type" to "DEEP_LINK", "uri" to uri, "host" to (intent.data?.host ?: ""), "path" to (intent.data?.path ?: ""))
            }
            else -> null
        }
    }

    private fun copyToCache(uriString: String): String? {
        return try {
            val sourceUri = android.net.Uri.parse(uriString)
            val input = contentResolver.openInputStream(sourceUri) ?: return null
            val cacheDir = File(cacheDir, "shared").also { it.mkdirs() }
            val out = File(cacheDir, "shared_${System.currentTimeMillis()}.tmp")
            out.outputStream().use { o -> input.copyTo(o) }; input.close()
            FileProvider.getUriForFile(this, "$packageName.fileprovider", out).toString()
        } catch (e: Exception) { Log.e(TAG, "cache error", e); null }
    }

    private fun startBridgeForegroundService() {
        val i = Intent(this, BridgeForegroundService::class.java).apply {
            action = BridgeForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
        else startService(i)
    }

    private fun stopBridgeForegroundService() {
        startService(Intent(this, BridgeForegroundService::class.java).apply {
            action = BridgeForegroundService.ACTION_STOP
        })
    }
}
