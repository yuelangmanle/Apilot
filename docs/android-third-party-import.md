# Apilot Android 第三方 API 方案接入文档

Apilot 支持两种公开的 Android Intent 能力：第三方 App 向 Apilot 导入 API 配置，以及第三方 App 请求用户授权一条 Apilot 已保存的 API 方案。两种能力都开放给任意第三方 App，但都必须由用户确认，不能静默导入或静默读取密钥。

## 能力范围

- 支持导入单个或多个 API 配置。
- 支持带 apiKey 的完整配置。
- 支持不带 apiKey 的配置，用户可在 Apilot 内补全。
- Apilot 始终生成新的内部配置 ID。
- Apilot 不覆盖用户已有配置。
- 用户必须先确认来源说明页，再确认配置预览页。
- 第三方 App 可以请求用户选择一条 Apilot 已保存的方案，并通过 Activity Result 接收结果。
- 已保存方案支持返回完整模型列表，或只返回第一个默认模型。

## 接口常量

| 项 | 值 |
| --- | --- |
| Action | com.apilot.intent.action.IMPORT_API_CONFIGS |
| MIME type | application/vnd.apilot.api-configs+json |
| JSON extra | com.apilot.extra.API_CONFIGS_JSON |
| Source name extra | com.apilot.extra.SOURCE_NAME |
| Request ID extra | com.apilot.extra.REQUEST_ID |
| 选择已保存方案 Action | com.apilot.intent.action.PICK_API_CONFIG |
| 模型模式 extra | com.apilot.extra.MODEL_MODE |
| 回传结果 JSON extra | com.apilot.extra.API_CONFIG_JSON |
| Deep link | apilot://import |

当前 Android 包名：

~~~text
com.example.api_manager
~~~

第三方 App 应显式设置 Apilot 包名，避免系统选择器打开错误目标。后续如果 Apilot 发布包名变更，本文件和 App 内文档会同步更新。

## 推荐方式：Intent + content URI

包含 API Key 或多条配置时，请优先使用 content:// URI。调用方通过自己的 FileProvider 或 ContentProvider 提供一次性可读 JSON 文件，并授予 Apilot 读取权限。

~~~kotlin
val intent = Intent("com.apilot.intent.action.IMPORT_API_CONFIGS").apply {
    setPackage("com.example.api_manager")
    setDataAndType(uri, "application/vnd.apilot.api-configs+json")
    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
    putExtra("com.apilot.extra.REQUEST_ID", requestId)
}

startActivity(intent)
~~~

调用方需要保证：

- uri 可通过 ContentResolver.openInputStream(uri) 读取。
- 授权包含 Intent.FLAG_GRANT_READ_URI_PERMISSION。
- JSON 内容使用 UTF-8。
- 不在 URI、query string、日志或剪贴板里暴露 API Key。

## 备用方式：Intent + JSON extra

小体积、不含大量配置时，可以直接把 JSON 字符串放进 extra：

~~~kotlin
val intent = Intent("com.apilot.intent.action.IMPORT_API_CONFIGS").apply {
    setPackage("com.example.api_manager")
    type = "application/vnd.apilot.api-configs+json"
    putExtra("com.apilot.extra.API_CONFIGS_JSON", payloadJson)
    putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
    putExtra("com.apilot.extra.REQUEST_ID", requestId)
}

startActivity(intent)
~~~

Android Intent extra 存在体积限制。配置较多、模型列表较长或包含密钥时，请改用 content:// URI。

## 请求已保存的 API 方案

第三方 App 可以用 `ActivityResultContracts.StartActivityForResult` 唤起 Apilot。Apilot 会展示调用来源、模型回传方式、API Key 安全提示和本地方案选择页；用户选择并确认后，结果通过 `com.apilot.extra.API_CONFIG_JSON` 返回。

~~~kotlin
private val pickApiConfig = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode != Activity.RESULT_OK) return@registerForActivityResult

    val payloadJson = result.data?.getStringExtra(
        "com.apilot.extra.API_CONFIG_JSON"
    ) ?: return@registerForActivityResult
    val payload = JSONObject(payloadJson)
    val apiConfig = payload.getJSONObject("apiConfig")

    val defaultModel = payload.optString("selectedModel", "")
    // defaultModel 可直接填入调用方的模型选择控件。
    // MODEL_MODE=all 时，apiConfig 还包含 models 备选列表。
}

fun chooseSavedApiConfig() {
    pickApiConfig.launch(
        Intent("com.apilot.intent.action.PICK_API_CONFIG").apply {
            setPackage("com.example.api_manager")
            putExtra("com.apilot.extra.SOURCE_NAME", "Example Client")
            putExtra("com.apilot.extra.REQUEST_ID", requestId)
            putExtra("com.apilot.extra.MODEL_MODE", "all")
        }
    )
}
~~~

### 模型回传模式

| `com.apilot.extra.MODEL_MODE` | 结果 | 使用场景 |
| --- | --- | --- |
| `all`（默认） | `selectedModel` 为已保存列表的第一个模型；`apiConfig.models` 返回完整备选列表。 | 调用方直接导入整套模型方案。 |
| `default_only` | 只返回 `selectedModel`，`apiConfig` 不包含 `models`。 | 调用方自行联网获取最新模型列表。 |

如果用户所选方案没有保存模型，两种模式都会回传 `selectedModel: null`；调用方应提示用户输入模型，或自行在线获取。

### 回传结果 schema

~~~json
{
  "schemaVersion": 1,
  "modelMode": "all",
  "selectedModel": "gpt-4.1",
  "apiConfig": {
    "name": "OpenAI Production",
    "baseUrl": "https://api.openai.com/v1",
    "apiKey": "sk-...",
    "environment": "production",
    "group": "AI",
    "tags": ["openai", "prod"],
    "models": ["gpt-4.1", "gpt-4.1-mini"]
  }
}
~~~

回传结果不会包含 Apilot 内部 `id`、创建/更新时间或 metadata。`apiKey` 仅在用户明确选择方案并确认授权后才会返回。调用方不得把回传的密钥写入日志、URL、deep link 或未加密的共享存储。

## 只打开文档入口

如果只想打开 Apilot 的第三方导入接入说明，可以使用：

~~~kotlin
startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("apilot://import")))
~~~

不要通过 deep link URL 传输 API Key。

## Payload schema

首版 schemaVersion 固定为 1。

~~~json
{
  "schemaVersion": 1,
  "source": {
    "appName": "Example Client",
    "packageName": "com.example.client"
  },
  "options": {
    "containsSecrets": true
  },
  "apiConfigs": [
    {
      "name": "OpenAI Production",
      "baseUrl": "https://api.openai.com/v1",
      "apiKey": "sk-...",
      "models": ["gpt-4.1", "gpt-4.1-mini"],
      "environment": "production",
      "group": "AI",
      "tags": ["openai", "prod"],
      "metadata": {
        "source": "example-client"
      }
    }
  ]
}
~~~

### 顶层字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| schemaVersion | number | 是 | 首版固定为 1。 |
| source.appName | string | 否 | 调用方展示名，仅用于说明页。 |
| source.packageName | string | 否 | 调用方声明包名，不作为信任依据。 |
| options.containsSecrets | boolean | 否 | 调用方声明是否包含密钥；Apilot 仍会扫描 apiKey。 |
| apiConfigs | array | 是 | 待导入配置列表，至少一项。 |

### 配置字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| name | string | 是 | API 配置名称。 |
| baseUrl | string | 是 | 必须以 http:// 或 https:// 开头。 |
| models | string[] | 是 | 至少包含一个模型。 |
| apiKey | string | 否 | 可为空或缺省。 |
| environment | string | 否 | 缺省为 development。 |
| group | string | 否 | 配置分组。 |
| tags | string[] | 否 | 标签列表。 |
| metadata | object | 否 | 第三方扩展信息。 |

Apilot 会忽略第三方传入的 id、createdAt、updatedAt，并在导入时生成新的内部值。

导入到 Apilot 的 `models` 必须由调用方提供，且至少包含一个模型。Apilot 不会在导入时自动联网刷新模型；用户可在配置详情页使用“刷新模型列表”。

## 用户确认流程

1. Apilot 打开来源说明页。
2. 用户查看来源 App、包名、配置数量、是否包含 API Key。
3. 用户点击“继续查看”。
4. Apilot 打开导入确认页。
5. 用户查看配置名称、Base URL、模型数量、是否含 Key、无效项和重复提示。
6. 用户点击“确认导入”。
7. Apilot 保存有效配置，并展示导入结果。

## 冲突策略

第三方导入永远保留两份：

- 不覆盖旧配置。
- 不使用第三方传入的 ID。
- 导入名称追加“（导入 yyyy-MM-dd HH:mm）”后缀。
- 检测到相似配置时只提示，不阻止导入。

## 密钥安全建议

- 不要把 API Key 放进 URL、deep link、query string 或日志。
- 包含 API Key 时优先使用 content:// URI。
- options.containsSecrets 只是提示字段，Apilot 会自行检测非空 apiKey。
- Apilot 页面只显示“含 Key / 无 Key”，不会展示完整 API Key。
- 请求已保存方案时，只有用户在 Apilot 内选定配置并确认授权，调用方才能收到 API Key。

## 常见错误

| 错误 | 处理方式 |
| --- | --- |
| Apilot 没有响应 Intent | 确认 action、MIME type 和 package name 是否正确。 |
| 无法读取配置文件 | 确认 content:// 可读，并设置了 FLAG_GRANT_READ_URI_PERMISSION。 |
| 导入格式版本不支持 | 确认 schemaVersion 为 1。 |
| 配置被标记为无效 | 检查 name、baseUrl、models 是否存在且格式正确。 |
| API Key 没有导入 | 确认 payload 中 apiKey 字段非空。 |
| 出现重复配置提示 | 这是正常提示，Apilot 会作为新配置保存。 |
| 未收到已保存方案结果 | 检查是否使用 Activity Result API，以及用户是否取消了授权。 |
| `selectedModel` 为空 | 所选方案没有保存模型；调用方应允许手动输入或在线刷新。 |

## adb 调试示例

JSON extra 可以用 adb 快速验证：

~~~bash
adb shell am start \
  -a com.apilot.intent.action.IMPORT_API_CONFIGS \
  -t application/vnd.apilot.api-configs+json \
  -n com.example.api_manager/.MainActivity \
  --es com.apilot.extra.SOURCE_NAME "ADB Test" \
  --es com.apilot.extra.API_CONFIGS_JSON '{"schemaVersion":1,"apiConfigs":[{"name":"ADB Demo","baseUrl":"https://api.example.com/v1","models":["demo-model"],"environment":"development"}]}'
~~~

复杂 payload 请使用测试 App 或 content:// URI 验证。
