package com.apilot.exampleclient

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class MainActivity : ComponentActivity() {
    private lateinit var apiKeyInput: EditText
    private lateinit var resultView: TextView

    private val pickApiProfile = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode != Activity.RESULT_OK) {
            showResult("用户取消了 Apilot 授权")
            return@registerForActivityResult
        }
        val data = result.data
        val payload = data?.getStringExtra(EXTRA_API_CONFIG_JSON)
            ?: data?.data?.let { uri ->
                contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            }
        if (payload.isNullOrBlank()) {
            showResult("Apilot 未返回可读取的 API Profile")
            return@registerForActivityResult
        }
        showProfileSummary(payload)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (20 * resources.displayMetrics.density).toInt()
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        content.addView(TextView(this).apply {
            text = "Apilot V2 API Profile 示例"
            textSize = 22f
        })
        content.addView(TextView(this).apply {
            text = "密钥只用于演示导入；示例不会显示或记录密钥。"
            textSize = 14f
        })
        apiKeyInput = EditText(this).apply {
            hint = "可选：DeepSeek API Key"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        content.addView(apiKeyInput, matchWidth())
        content.addView(Button(this).apply {
            text = "导入 DeepSeek V2 到 Apilot"
            setOnClickListener { importProfileToApilot() }
        }, matchWidth())
        content.addView(Button(this).apply {
            text = "从 Apilot 选择已保存方案"
            setOnClickListener { chooseSavedProfile() }
        }, matchWidth())
        resultView = TextView(this).apply {
            text = "等待操作"
            textSize = 14f
            setPadding(0, padding, 0, 0)
        }
        content.addView(resultView, matchWidth())
        setContentView(ScrollView(this).apply { addView(content) })
    }

    private fun importProfileToApilot() {
        val profile = JSONObject().apply {
            put("connection", JSONObject().apply {
                put("name", "DeepSeek Example")
                put("baseUrl", "https://api.deepseek.com/v1")
                put("environment", "development")
            })
            put("provider", JSONObject().put("id", "deepseek"))
            put("protocol", JSONObject().put("id", "openai_compatible"))
            put("models", JSONObject().apply {
                put("selectedModel", "deepseek-chat")
                put("catalogMode", "saved")
                put("source", "manual")
            })
            val apiKey = apiKeyInput.text.toString().trim()
            if (apiKey.isNotEmpty()) {
                put("secrets", JSONObject().put("apiKey", apiKey))
            }
            put("origin", JSONObject().put("appName", APP_NAME))
        }
        val payload = JSONObject().apply {
            put("schemaVersion", 2)
            put("source", JSONObject().apply {
                put("appName", APP_NAME)
                put("packageName", packageName)
            })
            put("apiProfiles", JSONArray().put(profile))
        }.toString()
        try {
            startActivity(Intent(ACTION_IMPORT_API_CONFIGS).apply {
                setPackage(APILOT_PACKAGE)
                type = IMPORT_MIME_TYPE
                putExtra(EXTRA_API_CONFIGS_JSON, payload)
                putExtra(EXTRA_SOURCE_NAME, APP_NAME)
                putExtra(EXTRA_REQUEST_ID, UUID.randomUUID().toString())
            })
            showResult("已打开 Apilot，等待用户确认导入")
        } catch (_: ActivityNotFoundException) {
            showResult("未找到 Apilot，请安装包名为 $APILOT_PACKAGE 的应用")
        }
    }

    private fun chooseSavedProfile() {
        try {
            pickApiProfile.launch(Intent(ACTION_PICK_API_CONFIG).apply {
                setPackage(APILOT_PACKAGE)
                putExtra(EXTRA_SOURCE_NAME, APP_NAME)
                putExtra(EXTRA_REQUEST_ID, UUID.randomUUID().toString())
                putExtra(EXTRA_SCHEMA_VERSION, 2)
                putStringArrayListExtra(
                    EXTRA_REQUESTED_SCOPES,
                    arrayListOf("connection", "models.default", "models.all", "secret.api_key"),
                )
                putExtra(EXTRA_RETURN_TRANSPORT, "auto")
            })
        } catch (_: ActivityNotFoundException) {
            showResult("未找到 Apilot，请安装包名为 $APILOT_PACKAGE 的应用")
        }
    }

    private fun showProfileSummary(payload: String) {
        try {
            val result = JSONObject(payload)
            val profile = result.getJSONObject("apiProfile")
            val connection = profile.optJSONObject("connection")
            val provider = profile.optJSONObject("provider")
            val protocol = profile.optJSONObject("protocol")
            val models = profile.optJSONObject("models")
            val scopes = result.optJSONArray("grantedScopes")
                ?.let { values -> (0 until values.length()).joinToString { values.getString(it) } }
                ?: ""
            val hasKey = profile.optJSONObject("secrets")?.has("apiKey") == true
            showResult(
                "已收到 API Profile\n" +
                    "服务商: ${provider?.optString("id")}\n" +
                    "协议: ${protocol?.optString("id")}\n" +
                    "地址: ${connection?.optString("baseUrl")}\n" +
                    "默认模型: ${models?.optString("selectedModel")}\n" +
                    "授权范围: $scopes\n" +
                    "已授权密钥: $hasKey",
            )
        } catch (_: Exception) {
            showResult("Apilot 返回了无法解析的 JSON")
        }
    }

    private fun showResult(value: String) {
        resultView.text = value
    }

    private fun matchWidth() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )

    private companion object {
        const val APILOT_PACKAGE = "com.example.api_manager"
        const val APP_NAME = "Apilot API Profile Example"
        const val ACTION_IMPORT_API_CONFIGS = "com.apilot.intent.action.IMPORT_API_CONFIGS"
        const val ACTION_PICK_API_CONFIG = "com.apilot.intent.action.PICK_API_CONFIG"
        const val IMPORT_MIME_TYPE = "application/vnd.apilot.api-configs+json"
        const val EXTRA_API_CONFIGS_JSON = "com.apilot.extra.API_CONFIGS_JSON"
        const val EXTRA_API_CONFIG_JSON = "com.apilot.extra.API_CONFIG_JSON"
        const val EXTRA_SOURCE_NAME = "com.apilot.extra.SOURCE_NAME"
        const val EXTRA_REQUEST_ID = "com.apilot.extra.REQUEST_ID"
        const val EXTRA_SCHEMA_VERSION = "com.apilot.extra.SCHEMA_VERSION"
        const val EXTRA_REQUESTED_SCOPES = "com.apilot.extra.REQUESTED_SCOPES"
        const val EXTRA_RETURN_TRANSPORT = "com.apilot.extra.RETURN_TRANSPORT"
    }
}
