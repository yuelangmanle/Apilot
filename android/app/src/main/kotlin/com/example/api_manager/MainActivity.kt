package com.example.api_manager

import android.content.Intent
import android.app.Activity
import android.os.Bundle
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.client.android.Intents
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.io.File
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent)
        buildGatewayGrantRequest(intent)?.let { pendingGatewayGrant = it }
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        if (text.isBlank()) return
        pendingShareText = text
        // Flutter 已就绪时直接推送；否则等待 getInitialShareText 拉取。
        // 推送即清除，避免解锁重建 AppShell 时把旧分享再弹一次。
        shareChannel?.invokeMethod("onShareReceived", text)?.let {
            pendingShareText = null
        }
        try {
            intent.removeExtra(Intent.EXTRA_TEXT)
        } catch (_: Exception) {
        }
    }

    // 进入后台/任务切换器时遮蔽内容，防止最近任务缩略图泄露配置与 Key。
    override fun onPause() {
        super.onPause()
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onStop() {
        super.onStop()
        // onStop 兜底：部分机型的最近任务截图发生在 onPause 与 onStop 之间。
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onResume() {
        super.onResume()
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
    }

    private var methodChannel: MethodChannel? = null
    private var apiConfigPickChannel: MethodChannel? = null
    private var qrScannerChannel: MethodChannel? = null
    private var qrScanResult: MethodChannel.Result? = null
    private var pendingImportRequest: Map<String, Any?>? = null
    private var pendingShareText: String? = null
    private var shareChannel: MethodChannel? = null
    private var pendingPickRequest: Map<String, Any?>? = null
    private var initialIntentConsumed = false
    private var initialPickIntentConsumed = false

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            launchZxingQrScan()
        } else {
            reportQrPermissionDenied()
        }
    }
    private val qrScanLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        val pendingResult = qrScanResult ?: return@registerForActivityResult
        qrScanResult = null
        if (activityResult.resultCode == Activity.RESULT_OK) {
            pendingResult.success(activityResult.data?.getStringExtra(Intents.Scan.RESULT))
        } else {
            pendingResult.success(null)
        }
    }

    private var gatewayGrantChannel: MethodChannel? = null
    private var pendingGatewayGrant: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL_NAME
        )
        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShareText" -> {
                    val text = pendingShareText
                    pendingShareText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }

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
                    call.argument<Int>("schemaVersion") ?: 1,
                    call.argument<String>("returnTransport"),
                    result
                )
                "finishPick" -> finishPick(result)
                "cancelPick" -> cancelPick(result)
                else -> result.notImplemented()
            }
        }

        gatewayGrantChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GATEWAY_GRANT_CHANNEL_NAME
        )
        gatewayGrantChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialGrantRequest" -> {
                    val request = pendingGatewayGrant ?: readInitialGatewayGrantRequest()
                    pendingGatewayGrant = null
                    result.success(request)
                }
                "completeGrant" -> completeGatewayGrant(
                    call.argument<String>("payload"),
                    result
                )
                "cancelGrant" -> cancelGatewayGrant(result)
                else -> result.notImplemented()
            }
        }

        // 网关前台服务通道：Flutter 启动/停止网关时同步开关常驻通知与唤醒锁。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GATEWAY_FOREGROUND_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val port = call.argument<Int>("port") ?: 8787
                        val intent = Intent(this, GatewayForegroundService::class.java)
                            .putExtra("port", port)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, GatewayForegroundService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("GATEWAY_SERVICE", e.message, null)
            }
        }

        // 网关悬浮窗通道：显示/隐藏状态胶囊 + 申请"显示在其他应用上层"权限。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GATEWAY_OVERLAY_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canShow" -> result.success(GatewayOverlay.canShow(this))
                    "show" -> {
                        if (!GatewayOverlay.canShow(this)) {
                            result.success(false)
                        } else {
                            GatewayOverlay.show(
                                this,
                                call.argument<Int>("port") ?: 8787,
                                call.argument<Int>("requests") ?: 0
                            )
                            result.success(true)
                        }
                    }
                    "update" -> {
                        GatewayOverlay.update(
                            call.argument<Int>("port") ?: 8787,
                            call.argument<Int>("requests") ?: 0
                        )
                        result.success(true)
                    }
                    "hide" -> {
                        GatewayOverlay.hide()
                        result.success(true)
                    }
                    "isVisible" -> result.success(GatewayOverlay.visible)
                    "requestPermission" -> {
                        startActivity(GatewayOverlay.overlayPermissionIntent(this))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("GATEWAY_OVERLAY", e.message, null)
            }
        }

        // MANAGE_EXTERNAL_STORAGE 是 Android 11+ 的特殊访问权限，不能靠
        // 普通应用详情页或运行时弹窗授予；必须打开「所有文件访问」页面。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "openAllFilesAccessSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            try {
                                startActivity(intent)
                            } catch (_: Exception) {
                                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                            }
                        } else {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            })
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("STORAGE_PERMISSION", e.message, null)
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
        handleShareIntent(intent)

        setIntent(intent)

        val grantRequest = buildGatewayGrantRequest(intent)
        if (grantRequest != null) {
            val channel = gatewayGrantChannel
            if (channel == null) {
                pendingGatewayGrant = grantRequest
            } else {
                channel.invokeMethod("onGrantRequest", grantRequest)
            }
        }

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

    private fun reportQrPermissionDenied() {
        val pendingResult = qrScanResult ?: return
        qrScanResult = null
        val permanentlyDenied = !shouldShowRequestPermissionRationale(
            Manifest.permission.CAMERA,
        )
        pendingResult.error(
            if (permanentlyDenied) {
                "camera_permission_permanently_denied"
            } else {
                "camera_permission_denied"
            },
            "相机权限未授予",
            null,
        )
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
            "modelMode" to intent.getStringExtra(EXTRA_MODEL_MODE),
            "schemaVersion" to intent.getIntExtra(EXTRA_SCHEMA_VERSION, 1),
            "requestedScopes" to intent.getStringArrayListExtra(EXTRA_REQUESTED_SCOPES),
            "returnTransport" to intent.getStringExtra(EXTRA_RETURN_TRANSPORT),
            "declaredSignatureSha256" to intent.getStringExtra(EXTRA_SOURCE_SIGNATURE_SHA256)
        )
    }

    private fun completePick(
        payload: String?,
        schemaVersion: Int,
        returnTransport: String?,
        result: MethodChannel.Result,
    ) {
        if (intent?.action != ACTION_PICK_API_CONFIG) {
            result.error("no_pick_request", "当前没有待回传的 API 方案请求", null)
            return
        }
        if (payload.isNullOrBlank()) {
            result.error("invalid_pick_payload", "回传的 API 方案为空", null)
            return
        }

        val useContentUri = schemaVersion >= 2 &&
            (returnTransport == RETURN_TRANSPORT_CONTENT_URI ||
                (returnTransport != RETURN_TRANSPORT_EXTRA && payload.toByteArray(Charsets.UTF_8).size > EXTRA_PAYLOAD_THRESHOLD_BYTES))
        val response = if (useContentUri) {
            createContentUriResponse(payload)
        } else {
            Intent().apply {
                putExtra(EXTRA_API_CONFIG_JSON, payload)
            }
        }
        response.apply {
            putExtra(EXTRA_MODEL_MODE, intent.getStringExtra(EXTRA_MODEL_MODE))
            putExtra(EXTRA_SCHEMA_VERSION, schemaVersion)
        }
        setResult(Activity.RESULT_OK, response)
        result.success(null)
    }

    private fun finishPick(result: MethodChannel.Result) {
        if (intent?.action != ACTION_PICK_API_CONFIG) {
            result.error("no_pick_request", "当前没有待回传的 API 方案请求", null)
            return
        }
        result.success(null)
        finish()
    }

    private fun createContentUriResponse(payload: String): Intent {
        val resultDirectory = File(cacheDir, "third_party_results").apply { mkdirs() }
        resultDirectory.listFiles()?.forEach { file ->
            if (file.lastModified() < System.currentTimeMillis() - RESULT_FILE_MAX_AGE_MS) file.delete()
        }
        val resultFile = File(resultDirectory, "api-profile-${UUID.randomUUID()}.json")
        resultFile.writeText(payload, Charsets.UTF_8)
        Handler(Looper.getMainLooper()).postDelayed(
            { resultFile.delete() },
            RESULT_FILE_LIFETIME_MS
        )
        val uri = FileProvider.getUriForFile(this, "$packageName.third_party_results", resultFile)
        return Intent().apply {
            setDataAndType(uri, API_PROFILE_MIME_TYPE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = android.content.ClipData.newRawUri("Apilot API profile", uri)
        }
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
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            launchZxingQrScan()
            return
        }

        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    private fun launchZxingQrScan() {
        if (qrScanResult == null) return
        try {
            qrScanLauncher.launch(
                Intent(this, ApilotQrCaptureActivity::class.java).apply {
                    putExtra(Intents.Scan.FORMATS, BarcodeFormat.QR_CODE.toString())
                    putExtra(Intents.Scan.PROMPT_MESSAGE, "扫描同步二维码")
                },
            )
        } catch (fallbackError: Exception) {
            val pendingResult = qrScanResult ?: return
            qrScanResult = null
            pendingResult.error(
                "qr_scan_failed",
                fallbackError.message ?: "无法启动扫码器",
                null
            )
        }
    }

    private fun baseRequest(intent: Intent): Map<String, Any?> {
        val callingSourcePackage = if (intent.action == ACTION_PICK_API_CONFIG) {
            callingPackage
        } else {
            null
        }
        val referrerSourcePackage = extractReferrerPackage(intent)
        val sourcePackage = callingSourcePackage ?: referrerSourcePackage
        val sourceInfo = sourcePackage?.let { getSourceInfo(it) }
        val sourceIdentity = when {
            callingSourcePackage != null -> SOURCE_IDENTITY_CALLING_PACKAGE
            referrerSourcePackage != null -> SOURCE_IDENTITY_REFERRER
            else -> null
        }

        return mapOf(
            "sourceName" to intent.getStringExtra(EXTRA_SOURCE_NAME),
            "requestId" to intent.getStringExtra(EXTRA_REQUEST_ID),
            "sourcePackage" to sourcePackage,
            "sourceAppName" to sourceInfo?.first,
            "signatureSha256" to sourceInfo?.second,
            "sourceIdentity" to sourceIdentity,
            "declaredSignatureSha256" to intent.getStringExtra(EXTRA_SOURCE_SIGNATURE_SHA256),
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

    /// 解析"一键授予本地网关能力"请求。
    private fun buildGatewayGrantRequest(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != ACTION_GRANT_GATEWAY) return null
        val callerPackage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            callingActivity?.packageName
        } else {
            @Suppress("DEPRECATION")
            callingActivity?.packageName
        }
        return mapOf(
            "requestId" to intent.getStringExtra(EXTRA_REQUEST_ID),
            "sourceName" to intent.getStringExtra(EXTRA_SOURCE_NAME),
            "requestedScope" to (intent.getStringExtra(EXTRA_REQUESTED_SCOPE) ?: "loopback"),
            "callerPackage" to callerPackage,
            "declaredSignatureSha256" to intent.getStringExtra(EXTRA_SOURCE_SIGNATURE_SHA256),
        )
    }

    private fun readInitialGatewayGrantRequest(): Map<String, Any?>? {
        val request = buildGatewayGrantRequest(intent)
        return request
    }

    /// 把网关授权结果回传给调用方并结束本页。
    private fun completeGatewayGrant(payload: String?, result: MethodChannel.Result) {
        if (payload == null) {
            result.error("INVALID_PAYLOAD", "payload 不能为空", null)
            return
        }
        val data = Intent().apply {
            putExtra(EXTRA_GATEWAY_GRANT_JSON, payload)
        }
        setResult(Activity.RESULT_OK, data)
        result.success(true)
        finish()
    }

    private fun cancelGatewayGrant(result: MethodChannel.Result) {
        setResult(Activity.RESULT_CANCELED)
        result.success(true)
        finish()
    }

    private data class PayloadResult(
        val payload: String?,
        val error: String?,
    )

    companion object {
        private const val CHANNEL_NAME = "com.apilot/third_party_import"
        private const val API_CONFIG_PICK_CHANNEL_NAME = "com.apilot/third_party_api_config_pick"
        private const val GATEWAY_GRANT_CHANNEL_NAME = "com.apilot/third_party_gateway_grant"
        private const val GATEWAY_FOREGROUND_CHANNEL = "com.apilot/gateway_foreground"
        private const val GATEWAY_OVERLAY_CHANNEL = "com.apilot/gateway_overlay"
        private const val STORAGE_PERMISSION_CHANNEL = "com.apilot/storage_permission"
        private const val ACTION_GRANT_GATEWAY = "com.apilot.intent.action.GRANT_GATEWAY"
        private const val EXTRA_GATEWAY_GRANT_JSON = "com.apilot.extra.GATEWAY_GRANT_JSON"
        private const val EXTRA_REQUESTED_SCOPE = "com.apilot.extra.REQUESTED_SCOPE"
        private const val QR_SCANNER_CHANNEL_NAME = "com.apilot/qr_scanner"
        private const val ACTION_IMPORT_API_CONFIGS = "com.apilot.intent.action.IMPORT_API_CONFIGS"
        private const val ACTION_PICK_API_CONFIG = "com.apilot.intent.action.PICK_API_CONFIG"
        private const val EXTRA_API_CONFIGS_JSON = "com.apilot.extra.API_CONFIGS_JSON"
        private const val EXTRA_API_CONFIG_JSON = "com.apilot.extra.API_CONFIG_JSON"
        private const val EXTRA_SOURCE_NAME = "com.apilot.extra.SOURCE_NAME"
        private const val EXTRA_REQUEST_ID = "com.apilot.extra.REQUEST_ID"
        private const val EXTRA_MODEL_MODE = "com.apilot.extra.MODEL_MODE"
        private const val EXTRA_SCHEMA_VERSION = "com.apilot.extra.SCHEMA_VERSION"
        private const val EXTRA_REQUESTED_SCOPES = "com.apilot.extra.REQUESTED_SCOPES"
        private const val EXTRA_RETURN_TRANSPORT = "com.apilot.extra.RETURN_TRANSPORT"
        private const val EXTRA_SOURCE_SIGNATURE_SHA256 = "com.apilot.extra.SOURCE_SIGNATURE_SHA256"
        private const val RETURN_TRANSPORT_EXTRA = "extra"
        private const val RETURN_TRANSPORT_CONTENT_URI = "content_uri"
        private const val API_PROFILE_MIME_TYPE = "application/vnd.apilot.api-profile+json"
        private const val EXTRA_PAYLOAD_THRESHOLD_BYTES = 64 * 1024
        private const val SHARE_CHANNEL_NAME = "com.apilot/share"
        private const val RESULT_FILE_MAX_AGE_MS = 10 * 60 * 1000L
        private const val RESULT_FILE_LIFETIME_MS = 60 * 1000L
        private const val SOURCE_IDENTITY_CALLING_PACKAGE = "calling_package"
        private const val SOURCE_IDENTITY_REFERRER = "referrer"
    }
}
