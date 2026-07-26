# Apilot Android 第三方导入接入文档

Apilot 支持第三方 Android App 唤起导入流程，将 API 配置交给用户确认后保存到 Apilot。该接口开放给任意第三方 App，但不支持静默导入。

## 能力范围

- 支持导入单个或多个 API 配置。
- 支持带 apiKey 的完整配置。
- 支持不带 apiKey 的配置，用户可在 Apilot 内补全。
- Apilot 始终生成新的内部配置 ID。
- Apilot 不覆盖用户已有配置。
- 用户必须先确认来源说明页，再确认配置预览页。

## 接口常量

| 项 | 值 |
| --- | --- |
| Action | com.apilot.intent.action.IMPORT_API_CONFIGS |
| MIME type | application/vnd.apilot.api-configs+json |
| JSON extra | com.apilot.extra.API_CONFIGS_JSON |
| Source name extra | com.apilot.extra.SOURCE_NAME |
| Request ID extra | com.apilot.extra.REQUEST_ID |
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

## 常见错误

| 错误 | 处理方式 |
| --- | --- |
| Apilot 没有响应 Intent | 确认 action、MIME type 和 package name 是否正确。 |
| 无法读取配置文件 | 确认 content:// 可读，并设置了 FLAG_GRANT_READ_URI_PERMISSION。 |
| 导入格式版本不支持 | 确认 schemaVersion 为 1。 |
| 配置被标记为无效 | 检查 name、baseUrl、models 是否存在且格式正确。 |
| API Key 没有导入 | 确认 payload 中 apiKey 字段非空。 |
| 出现重复配置提示 | 这是正常提示，Apilot 会作为新配置保存。 |

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
