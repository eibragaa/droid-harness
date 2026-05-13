package dev.droidharness.droid_harness_mobile

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MainActivity — entrada principal do Droid Harness.
 *
 * Estende FlutterActivity com integrações estilo Google:
 * - MethodChannel para comunicar intents recebidos ao Flutter
 * - Tratamento de ACTION_SEND (imagens, texto de outros apps)
 * - Tratamento de deep links (droid-harness://)
 * - Inicialização do foreground service
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DroidHarness/Main"
        private const val CHANNEL = "dev.droidharness/bridge"
        private const val ACTION_SHARED_FILE = "dev.droidharness.SHARED_FILE"
        private const val ACTION_SHARED_TEXT = "dev.droidharness.SHARED_TEXT"
        private const val ACTION_DEEP_LINK = "dev.droidharness.DEEP_LINK"
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBridgeService" -> {
                    startBridgeForegroundService()
                    result.success(true)
                }
                "stopBridgeService" -> {
                    stopBridgeForegroundService()
                    result.success(true)
                }
                "getInitialIntent" -> {
                    val intentData = extractIntentData(intent)
                    if (intentData != null) {
                        result.success(intentData)
                    } else {
                        result.success(mapOf("type" to "none"))
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Verifica se foi aberto por um intent (compartilhamento, deep link)
        handleIntent(intent)

        // Inicia o foreground service se ainda não estiver rodando
        // (auto-start após instalação/abertura)
        try {
            startBridgeForegroundService()
        } catch (e: Exception) {
            Log.w(TAG, "Could not start foreground service", e)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    /**
     * Processa o Intent recebido e envia para o Flutter via MethodChannel.
     */
    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        val data = extractIntentData(intent) ?: return
        Log.i(TAG, "Handling intent: type=${data["type"]}")

        methodChannel?.invokeMethod(
            data["type"] as String,
            data
        )
    }

    /**
     * Extrai dados do Intent (ACTION_SEND, ACTION_VIEW, etc.)
     * Retorna null se não houver dados relevantes.
     */
    private fun extractIntentData(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null

        return when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("image/") == true) {
                    // Imagem compartilhada de outro app (Gallery, Camera, etc.)
                    val imageUri = intent.getParcelableExtra<android.net.Uri>(
                        Intent.EXTRA_STREAM
                    )?.toString() ?: return null

                    // Copia para cache local para acesso do Flutter
                    val cachedUri = copyToCache(imageUri)
                    mapOf(
                        "type" to ACTION_SHARED_FILE,
                        "mimeType" to (intent.type ?: "image/*"),
                        "uri" to (cachedUri ?: imageUri)
                    )
                } else if (intent.type?.startsWith("text/") == true) {
                    // Texto compartilhado (navegador, notas, etc.)
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                        ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
                        ?: return null
                    mapOf(
                        "type" to ACTION_SHARED_TEXT,
                        "text" to text
                    )
                } else {
                    null
                }
            }
            Intent.ACTION_VIEW -> {
                // Deep link (droid-harness://...)
                val uri = intent.data?.toString() ?: return null
                mapOf(
                    "type" to ACTION_DEEP_LINK,
                    "uri" to uri,
                    "host" to (intent.data?.host ?: ""),
                    "path" to (intent.data?.path ?: "")
                )
            }
            else -> null
        }
    }

    /**
     * Copia uma URI de conteúdo para o cache interno do app,
     * permitindo que o Flutter a acesse via caminho de arquivo.
     */
    private fun copyToCache(uriString: String): String? {
        return try {
            val sourceUri = android.net.Uri.parse(uriString)
            val inputStream = contentResolver.openInputStream(sourceUri) ?: return null

            val cacheDir = File(cacheDir, "shared")
            cacheDir.mkdirs()
            val outputFile = File(cacheDir, "shared_${System.currentTimeMillis()}.tmp")
            outputFile.outputStream().use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()

            // Retorna content URI via FileProvider para o Flutter acessar
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                outputFile
            )
            contentUri.toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache shared file", e)
            null
        }
    }

    private fun startBridgeForegroundService() {
        val serviceIntent = Intent(this, BridgeForegroundService::class.java).apply {
            action = BridgeForegroundService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopBridgeForegroundService() {
        val serviceIntent = Intent(this, BridgeForegroundService::class.java).apply {
            action = BridgeForegroundService.ACTION_STOP
        }
        startService(serviceIntent)
    }
}
