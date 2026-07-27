package com.example.api_manager

import android.content.Intent
import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.google.zxing.BarcodeFormat
import com.google.zxing.client.android.Intents
import com.journeyapps.barcodescanner.CaptureActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var methodChannel: MethodChannel? = null
    private var apiConfigPickChannel: MethodChannel? = null
    private var qrScannerChannel: MethodChannel? = null
    private var qrScanResult: MethodChannel.Result? = null
    private var pendingImportRequest: Map<String, Any?>? = null
    private var pendingPickRequest: Map<String, Any?>? = null
    private var initialIntentConsumed = false
    private var initialPickIntentConsumed = false

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

        apiConfigPickChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            API_CONFIG_PICK_CHANNEL_NAME
        )
        apiConfigPickChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPickRequest" -> {
                    val request = pendingPickRequest ?: readInitialPickRequest()
                    pendingPickRequest = null
                    result.success(request)
                }
                "completePick" -> completePick(
                    call.argument<String>("payload"),
                    result
                )
                "cancelPick" -> cancelPick(result)
                else -> result.notImplemented()
            }
        }

        qrScannerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QR_SCANNER_CHANNEL_NAME
        )
        qrScannerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanQrCode" -> startQrScan(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val pickRequest = buildPickRequest(intent)
        if (pickRequest != null) {
            val channel = apiConfigPickChannel
            if (channel == null) {
                pendingPickRequest = pickRequest
            } else {
                channel.invokeMethod("onPickRequest", pickRequest)
            }
            return
        }

        val request = buildImportRequest(intent) ?: return
        val channel = methodChannel
        if (channel == null) {
            pendingImportRequest = request
        } else {
            channel.invokeMethod("onImportRequest", request)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != QR_SCAN_REQUEST_CODE) return

        val pendingResult = qrScanResult ?: return
        qrScanResult = null
        if (resultCode == Activity.RESULT_OK) {
            pendingResult.success(data?.getStringExtra(Intents.Scan.RESULT))
        } else {
            pendingResult.success(null)
        }
    }

    private fun readInitialImportRequest(): Map<String, Any?>? {
        if (initialIntentConsumed) return null
        initialIntentConsumed = true
        return buildImportRequest(intent)
    }

    private fun readInitialPickRequest(): Map<String, Any?>? {
        if (initialPickIntentConsumed) return null
        initialPickIntentConsumed = true
        return buildPickRequest(intent)
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

    private fun buildPickRequest(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != ACTION_PICK_API_CONFIG) return null

        return baseRequest(intent) + mapOf(
            "modelMode" to intent.getStringExtra(EXTRA_MODEL_MODE)
        )
    }

    private fun completePick(payload: String?, result: MethodChannel.Result) {
        if (intent?.action != ACTION_PICK_API_CONFIG) {
            result.error("no_pick_request", "当前没有待回传的 API 方案请求", null)
            return
        }
        if (payload.isNullOrBlank()) {
            result.error("invalid_pick_payload", "回传的 API 方案为空", null)
            return
        }

        val response = Intent().apply {
            putExtra(EXTRA_API_CONFIG_JSON, payload)
            putExtra(EXTRA_MODEL_MODE, intent.getStringExtra(EXTRA_MODEL_MODE))
        }
        setResult(Activity.RESULT_OK, response)
        result.success(null)
        finish()
    }

    private fun cancelPick(result: MethodChannel.Result) {
        if (intent?.action != ACTION_PICK_API_CONFIG) {
            result.error("no_pick_request", "当前没有待取消的 API 方案请求", null)
            return
        }

        setResult(Activity.RESULT_CANCELED)
        result.success(null)
        finish()
    }

    private fun startQrScan(result: MethodChannel.Result) {
        if (qrScanResult != null) {
            result.error("scan_in_progress", "扫码器已打开", null)
            return
        }

        qrScanResult = result
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()

        GmsBarcodeScanning.getClient(this, options)
            .startScan()
            .addOnSuccessListener { barcode ->
                val pendingResult = qrScanResult ?: return@addOnSuccessListener
                qrScanResult = null
                pendingResult.success(barcode.rawValue)
            }
            .addOnCanceledListener {
                val pendingResult = qrScanResult ?: return@addOnCanceledListener
                qrScanResult = null
                pendingResult.success(null)
            }
            .addOnFailureListener { exception ->
                startZxingQrScan(exception)
            }
    }

    private fun startZxingQrScan(originalError: Exception) {
        if (qrScanResult == null) return
        try {
            startActivityForResult(
                Intent(this, CaptureActivity::class.java).apply {
                    putExtra(Intents.Scan.FORMATS, BarcodeFormat.QR_CODE.toString())
                    putExtra(Intents.Scan.PROMPT_MESSAGE, "扫描同步二维码")
                },
                QR_SCAN_REQUEST_CODE
            )
        } catch (fallbackError: Exception) {
            val pendingResult = qrScanResult ?: return
            qrScanResult = null
            pendingResult.error(
                "qr_scan_failed",
                fallbackError.message ?: originalError.message,
                null
            )
        }
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
        private const val API_CONFIG_PICK_CHANNEL_NAME = "com.apilot/third_party_api_config_pick"
        private const val QR_SCANNER_CHANNEL_NAME = "com.apilot/qr_scanner"
        private const val QR_SCAN_REQUEST_CODE = 20842
        private const val ACTION_IMPORT_API_CONFIGS = "com.apilot.intent.action.IMPORT_API_CONFIGS"
        private const val ACTION_PICK_API_CONFIG = "com.apilot.intent.action.PICK_API_CONFIG"
        private const val EXTRA_API_CONFIGS_JSON = "com.apilot.extra.API_CONFIGS_JSON"
        private const val EXTRA_API_CONFIG_JSON = "com.apilot.extra.API_CONFIG_JSON"
        private const val EXTRA_SOURCE_NAME = "com.apilot.extra.SOURCE_NAME"
        private const val EXTRA_REQUEST_ID = "com.apilot.extra.REQUEST_ID"
        private const val EXTRA_MODEL_MODE = "com.apilot.extra.MODEL_MODE"
    }
}
