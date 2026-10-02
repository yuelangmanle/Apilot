# Apilot Android API Profile 互操作文档

Apilot 面向任意第三方 Android App 开放 API 方案互操作。所有导入和授权都必须经过用户确认，不能静默写入配置或读取密钥。

当前 Android 包名：`com.example.api_manager`

> 版本兼容：V1 导入在所有版本可用；V2（`schemaVersion: 2`）需要 **Apilot ≥ 1.20.0**。
> 本文档对应 Apilot v1.24.0 的行为，最后更新于 2026-09-29。

## 协议版本

| 版本 | 状态 | 用途 |
| --- | --- | --- |
| V1 (`schemaVersion: 1`) | 兼容保留 | 原始 `apiConfigs` 导入和 `MODEL_MODE` 回传。V1 选择方案后会回传 API Key。 |
| V2 (`schemaVersion: 2`) | 推荐 | 语义化 API Profile、提供商/协议分离、最小授权、无模型目录导入和 URI 回传。 |

不要用 V2 替换 V1 action；两版共用下列 Intent action，按 schemaVersion 分流。

## 接口常量

| 项 | 值 |
| --- | --- |
| 导入 Action | `com.apilot.intent.action.IMPORT_API_CONFIGS` |
| 选择 Action | `com.apilot.intent.action.PICK_API_CONFIG` |
| 导入 MIME | `application/vnd.apilot.api-configs+json` |
| V2 结果 MIME | `application/vnd.apilot.api-profile+json` |
| 导入 JSON extra | `com.apilot.extra.API_CONFIGS_JSON` |
| 回传 JSON extra | `com.apilot.extra.API_CONFIG_JSON` |
| 来源名 extra | `com.apilot.extra.SOURCE_NAME` |
| 请求 ID extra | `com.apilot.extra.REQUEST_ID` |
| V1 模型模式 | `com.apilot.extra.MODEL_MODE` |
| V2 schema | `com.apilot.extra.SCHEMA_VERSION` |
| V2 scopes | `com.apilot.extra.REQUESTED_SCOPES` (`ArrayList<String>`) |
| V2 回传方式 | `com.apilot.extra.RETURN_TRANSPORT` |
| 声明签名 SHA-256 | `com.apilot.extra.SOURCE_SIGNATURE_SHA256` |
| 文档 deep link | `apilot://import` |
| 网关授权 Action | `com.apilot.intent.action.GRANT_GATEWAY` |
| 网关授权回传 extra | `com.apilot.extra.GATEWAY_GRANT_JSON` |
| 网关模式 extra | `com.apilot.extra.REQUESTED_SCOPE` (`loopback` \| `lan`) |

调用方应使用 `setPackage("com.example.api_manager")`。深链接仅用于打开说明，绝不能传递 API Key。

仓库提供了可直接构建的 [Android V2 调用示例](../examples/android-api-profile-client)，覆盖导入、Activity Result、JSON extra、`content://` URI 和不记录 Key 的处理方式。

## V2 概念与规范

V2 将连接与服务商语义分开：

| 字段 | 值 |
| --- | --- |
| `provider.id` | `deepseek`、`openai`、`anthropic`、`google`、`custom` |
| `protocol.id` | `openai_compatible`、`anthropic_messages`、`google_genai` |
| 默认模型 | `models.selectedModel`，可为 null |
| 完整目录 | `models.availableModels`，可省略 |
| 目录状态 | `models.catalogMode`: `saved`、`remote`、`none` |
| 目录来源 | `models.source`: `manual`、`refreshed`、`third_party`、`unknown` |

`provider.id` 优先于 URL 推测。未指定时，Apilot 可从官方域名推测 DeepSeek/OpenAI/Anthropic/Google；无法识别统一保存为 `custom + openai_compatible`。因此，DeepSeek 方案在 V2 中会保持为 `provider.id: deepseek`，不会被降级成普通通用配置。

自 Apilot 1.23.0 起，`protocol.id: anthropic_messages` 的方案在请求层获得完整支持（`x-api-key` 鉴权与 `/messages` 端点），导入的 Claude 方案可以直接测试使用；`google_genai` 建议暂以 `openai_compatible` + Gemini OpenAI 兼容端点导入。

## V2 导入到 Apilot

调用方提交小 payload 时可用 JSON extra；含密钥、多配置或大模型目录时推荐一次性 `content://` URI，并添加 `FLAG_GRANT_READ_URI_PERMISSION`。

```kotlin
val intent = Intent("com.apilot.intent.action.IMPORT_API_CONFIGS").apply {
    setPackage("com.example.api_manager")
    setDataAndType(uri, "application/vnd.apilot.api-configs+json")
    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
    putExtra("com.apilot.extra.REQUEST_ID", requestId)
    putExtra("com.apilot.extra.SOURCE_SIGNATURE_SHA256", signingCertSha256)
}
startActivity(intent)
```

V2 payload：`apiProfiles` 中不要求模型列表；只使用默认模型，或让 Apilot 后续刷新，都可以。

```json
{
  "schemaVersion": 2,
  "source": {
    "appName": "Example Client",
    "packageName": "com.example.client",
    "signatureSha256": "AA:BB:CC"
  },
  "apiProfiles": [
    {
      "connection": {
        "name": "DeepSeek Production",
        "baseUrl": "https://api.deepseek.com/v1",
        "environment": "production",
        "tags": ["deepseek", "prod"]
      },
      "provider": { "id": "deepseek" },
      "protocol": { "id": "openai_compatible" },
      "models": {
        "selectedModel": "deepseek-chat",
        "catalogMode": "remote",
        "source": "third_party"
      },
      "secrets": { "apiKey": "sk-..." },
      "origin": { "appName": "Example Client" }
    }
  ]
}
```

Apilot 总是生成新的内部 ID、保留已有方案、名称追加导入时间。普通导入 Intent 没有可靠的系统调用方身份，来源包名和签名只作为调用方声明展示；只有 Activity Result 的“选择已保存方案”场景中，系统提供调用包且其签名与声明 SHA-256 一致时，Apilot 才显示“已验证包签名”。

## V2 从 Apilot 读取已保存方案

V2 默认只请求和返回连接与默认模型，绝不默认返回 API Key。完整模型目录和 Key 是独立 scope，Apilot 会在授权页展示复选框，由用户逐项确认。

| Scope | 含义 |
| --- | --- |
| `connection` | 名称、Base URL、环境、分组、标签 |
| `models.default` | `selectedModel` |
| `models.all` | `availableModels`；隐含 `models.default` |
| `secret.api_key` | API Key；必须用户明确勾选 |

`RETURN_TRANSPORT` 可为 `extra`、`content_uri` 或 `auto`。`auto` 是默认值：payload 大于 64 KiB 时改用临时只读 URI；`content_uri` 强制使用 URI。V1 始终使用 JSON extra。

```kotlin
private val pickApiProfile = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode != Activity.RESULT_OK) return@registerForActivityResult
    val data = result.data ?: return@registerForActivityResult
    val json = data.getStringExtra("com.apilot.extra.API_CONFIG_JSON")
        ?: data.data?.let { uri ->
            contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        }
        ?: return@registerForActivityResult

    val resultJson = JSONObject(json)
    val profile = resultJson.getJSONObject("apiProfile")
    val connection = profile.optJSONObject("connection")
    val defaultModel = profile.getJSONObject("models").optString("selectedModel")
    // 仅当 grantedScopes 包含 secret.api_key 时，secrets 中才有 apiKey。
}

fun chooseSavedProfile() {
    pickApiProfile.launch(Intent("com.apilot.intent.action.PICK_API_CONFIG").apply {
        setPackage("com.example.api_manager")
        putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
        putExtra("com.apilot.extra.REQUEST_ID", requestId)
        putExtra("com.apilot.extra.SCHEMA_VERSION", 2)
        putStringArrayListExtra(
            "com.apilot.extra.REQUESTED_SCOPES",
            arrayListOf("connection", "models.default", "models.all", "secret.api_key")
        )
        putExtra("com.apilot.extra.RETURN_TRANSPORT", "auto")
    })
}
```

V2 回传示例：

```json
{
  "schemaVersion": 2,
  "requestId": "request-42",
  "grantedScopes": ["connection", "models.default"],
  "apiProfile": {
    "connection": {
      "name": "DeepSeek Production",
      "baseUrl": "https://api.deepseek.com/v1",
      "environment": "production"
    },
    "provider": { "id": "deepseek", "displayName": "DeepSeek" },
    "protocol": { "id": "openai_compatible" },
    "models": {
      "selectedModel": "deepseek-chat",
      "catalogMode": "remote",
      "source": "refreshed"
    },
    "secrets": {},
    "origin": { "appName": "Apilot", "trustLevel": "system_package" }
  }
}
```

第三方 App 收到 V2 后应使用 `provider.id` 保存提供商身份；例如 `deepseek` 必须作为 DeepSeek 配置保存。`custom` 才表示调用方无法识别的通用服务。不要根据显示名重新猜测提供商。

## V1 兼容

V1 输入仍为 `apiConfigs`，每条必须有 `name`、`baseUrl` 和至少一个 `models`。选择请求继续使用：

```kotlin
putExtra("com.apilot.extra.MODEL_MODE", "all")
```

`all` 返回 `apiConfig.models` 与第一个 `selectedModel`；`default_only` 只返回 `selectedModel`。V1 的回传格式及其 Key 行为保持旧版本兼容，新增调用方应改用 V2。

```json
{
  "schemaVersion": 1,
  "apiConfigs": [
    {
      "name": "Legacy OpenAI",
      "baseUrl": "https://api.openai.com/v1",
      "apiKey": "sk-...",
      "models": ["gpt-4.1", "gpt-4.1-mini"],
      "environment": "production"
    }
  ]
}
```

## 本地网关互操作

Apilot 提供本地 OpenAI 兼容网关（127.0.0.1 或局域网 IP），第三方 App 可以：

1. **作为客户端调用** - 将 base_url 指向 `http://127.0.0.1:<port>/v1`，即可使用 Apilot 中保存的 API 配置（Key 由 Apilot 注入，第三方 App 不需要知道真 Key）。
2. **获取网关 Token** - 局域网模式下需携带 `X-Gateway-Token` 请求头（在 Apilot 网关页面复制）。本机回环地址（127.0.0.1）无需 Token。
3. **通过互操作通道获取网关描述符** - 使用 `PICK_API_CONFIG` 的 V2 协议时，返回结果中 `connection.baseUrl` 可指向网关地址。

### 一键授予网关能力（推荐，v2.5.0+）

第三方 App 不需要让用户手抄地址和 Token，可以直接发一个授权请求：

```kotlin
val intent = Intent("com.apilot.intent.action.GRANT_GATEWAY").apply {
    setPackage("com.example.api_manager")
    putExtra("com.apilot.extra.SOURCE_NAME", "我的应用")
    putExtra("com.apilot.extra.REQUEST_ID", "grant-1")
    // loopback = 仅本机（默认，最安全）；lan = 允许局域网设备
    putExtra("com.apilot.extra.REQUESTED_SCOPE", "loopback")
}
grantLauncher.launch(intent)   // ActivityResultLauncher<Intent>
```

用户在 Apilot 里会看到确认页：选择用**本机模型**（离线推理）还是**云端配置**（转发，Key 不下发），
并可以决定是否开放局域网访问。确认后 Apilot 启动网关并把结果回传：

```kotlin
override fun onActivityResult(resultCode: Int, data: Intent?) {
    if (resultCode != Activity.RESULT_OK) return   // 用户拒绝：RESULT_CANCELED
    val grant = JSONObject(data?.getStringExtra("com.apilot.extra.GATEWAY_GRANT_JSON") ?: return)
    val baseUrl = grant.getString("baseUrl")   // http://127.0.0.1:8787/v1
    val model   = grant.getString("model")     // 直接填进请求的 model 字段
    val token   = grant.optString("token")     // 局域网模式才有
    // 之后按 OpenAI 协议调用 baseUrl；局域网模式记得带 X-Gateway-Token: <token>
}
```

回调 JSON 字段：`baseUrl`、`model`、`scope`（`loopback` / `lan`）、`token`（可空）、
`headerName`（固定 `X-Gateway-Token`）、`apiKey`（本机模式可直接当占位 Key 用）。

注意事项：
- 网关仅在 Apilot 运行时可用。建议引导用户保持 Apilot 在前台或分屏。
- 本机回环地址（127.0.0.1）无需 Token；局域网地址需 Token。
- Apilot 侧的"本机模型"后端只支持文本对话；请求里带图片会返回 400 与明确说明。

## 取消、错误和安全

- 用户取消授权或导入时，Activity Result 返回 `RESULT_CANCELED`，调用方不得把它当作失败重试或静默回退。
- `RESULT_OK` 但缺少 extra 和 data URI 时，应视为无效结果并提示用户重新操作。
- `content://` URI 仅在当前交互内临时可读；Apilot 会在 **10 分钟后**删除缓存文件（下次授权时也会清理过期文件）。调用方应在收到结果后立刻读取，不能持久保存 URI。
- 不要把 API Key 写入 URL、deep link、日志、剪贴板或不加密共享存储。
- Apilot 侧密钥自 1.23.0 起加密落库（Fernet，主密钥在系统安全区），调用方 received 的明文 Key 请自行妥善保管。
- 若用户开启了应用锁（1.24.0+），跳转 Apilot 后会先停留在 PIN 解锁页；解锁后才会看到导入/授权界面。调用方不应把这段停留视为无响应。
- Apilot 客户端会记录不含密钥/payload 的导入和授权审计记录；用户可在设置中清除。
- 常见入站错误：`schemaVersion` 非 1/2、缺少 `apiConfigs`/`apiProfiles`、连接缺少 name/baseUrl、URI 没有读权限。
- 原生回传错误：`no_pick_request` 表示当前 Activity 不是选择请求；`invalid_pick_payload` 表示 Apilot 未能生成结果。调用方取消时是 `RESULT_CANCELED`，不是错误码。
