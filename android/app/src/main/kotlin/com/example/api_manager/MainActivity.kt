package com.example.api_manager

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var methodChannel: MethodChannel? = null
    private var pendingImportRequest: Map<String, Any?>? = null
    private var initialIntentConsumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialImportRequest" -> {
                    val request = pendingImportRequest ?: readInitialImportRequest()
                    pendingImportRequest = null
                    result.success(request)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val request = buildImportRequest(intent) ?: return
        val channel = methodChannel
        if (channel == null) {
            pendingImportRequest = request
        } else {
            channel.invokeMethod("onImportRequest", request)
        }
    }

    private fun readInitialImportRequest(): Map<String, Any?>? {
        if (initialIntentConsumed) return null
        initialIntentConsumed = true
        return buildImportRequest(intent)
    }

    private fun buildImportRequest(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null

        if (isImportDocsDeepLink(intent)) {
            return baseRequest(intent) + mapOf(
                "openDocs" to true,
                "payload" to null,
                "error" to null
            )
        }

        if (intent.action != ACTION_IMPORT_API_CONFIGS) return null

        val payloadResult = readPayload(intent)
        return baseRequest(intent) + mapOf(
            "openDocs" to false,
            "payload" to payloadResult.payload,
            "error" to payloadResult.error,
            "mimeType" to intent.type,
            "dataUri" to intent.dataString
        )
    }

    private fun baseRequest(intent: Intent): Map<String, Any?> {
        val sourcePackage = extractReferrerPackage(intent)
        val sourceInfo = sourcePackage?.let { getSourceInfo(it) }

        return mapOf(
            "sourceName" to intent.getStringExtra(EXTRA_SOURCE_NAME),
            "requestId" to intent.getStringExtra(EXTRA_REQUEST_ID),
            "sourcePackage" to sourcePackage,
            "sourceAppName" to sourceInfo?.first,
            "signatureSha256" to sourceInfo?.second,
            "receivedAtMillis" to System.currentTimeMillis()
        )
    }

    private fun readPayload(intent: Intent): PayloadResult {
        val extraPayload = intent.getStringExtra(EXTRA_API_CONFIGS_JSON)
        if (!extraPayload.isNullOrBlank()) {
            return PayloadResult(payload = extraPayload, error = null)
        }

        val uri = intent.data
        if (uri == null) {
            return PayloadResult(payload = null, error = "无法读取导入请求：缺少 JSON 或 content URI")
        }

        return try {
            contentResolver.openInputStream(uri).use { stream ->
                if (stream == null) {
                    PayloadResult(payload = null, error = "无法读取第三方提供的配置文件")
                } else {
                    PayloadResult(payload = stream.bufferedReader().use { it.readText() }, error = null)
                }
            }
        } catch (e: Exception) {
            PayloadResult(payload = null, error = "无法读取第三方提供的配置文件：" + e.message)
        }
    }

    private fun isImportDocsDeepLink(intent: Intent): Boolean {
        val data = intent.data ?: return false
        return intent.action == Intent.ACTION_VIEW &&
            data.scheme == "apilot" &&
            data.host == "import"
    }

    private fun extractReferrerPackage(intent: Intent): String? {
        val directReferrer = referrer
        if (directReferrer?.scheme == "android-app") {
            return directReferrer.host
        }

        val referrerName = intent.getStringExtra(Intent.EXTRA_REFERRER_NAME) ?: return null
        val referrerUri = runCatching { Uri.parse(referrerName) }.getOrNull()
        return if (referrerUri?.scheme == "android-app") referrerUri.host else null
    }

    private fun getSourceInfo(packageName: String): Pair<String?, String?> {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            val label = packageManager.getApplicationLabel(appInfo).toString()
            label to getSignatureDigest(packageName)
        } catch (e: Exception) {
            null to null
        }
    }

    @Suppress("DEPRECATION")
    private fun getSignatureDigest(packageName: String): String? {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }

        val signatureBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
        } else {
            packageInfo.signatures?.firstOrNull()?.toByteArray()
        } ?: return null

        val digest = MessageDigest.getInstance("SHA-256").digest(signatureBytes)
        return digest.joinToString(":") { "%02X".format(it.toInt() and 0xFF) }
    }

    private data class PayloadResult(
        val payload: String?,
        val error: String?,
    )

    companion object {
        private const val CHANNEL_NAME = "com.apilot/third_party_import"
        private const val ACTION_IMPORT_API_CONFIGS = "com.apilot.intent.action.IMPORT_API_CONFIGS"
        private const val EXTRA_API_CONFIGS_JSON = "com.apilot.extra.API_CONFIGS_JSON"
        private const val EXTRA_SOURCE_NAME = "com.apilot.extra.SOURCE_NAME"
        private const val EXTRA_REQUEST_ID = "com.apilot.extra.REQUEST_ID"
    }
}
