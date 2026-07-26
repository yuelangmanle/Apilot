# Android 第三方导入接口设计

日期：2026-07-27

## 背景

Apilot 已支持 API 配置的 JSON 备份和恢复，现有 `ApiConfig` 模型可以表达 API 名称、Base URL、API Key、模型列表、环境、分组、标签和元数据。本设计新增 Android 端公开导入入口，让任意第三方 Android App 可以唤起 Apilot，并提交一组 API 配置供用户导入。

该接口面向任意第三方 App，因此设计原则是：第三方 App 可以发起导入请求，但不能静默写入 Apilot 数据库；用户必须先确认来源和风险，再确认具体导入内容。

## 目标

- 允许任意第三方 Android App 一键唤起 Apilot 导入 API 配置。
- 支持带 API Key 的完整配置导入，也支持不带 API Key 的非敏感配置导入。
- 第三方导入永远不覆盖用户现有配置，重复配置按新配置保存。
- 在 Apilot 设置页提供精简接入文档。
- 在 GitHub 仓库提供完整接入文档。
- 保持现有备份/恢复功能不受影响。

## 非目标

- 不支持第三方 App 静默导入。
- 不通过 Deep Link URL 传输 API Key。
- 不把第三方传入的 `id` 作为 Apilot 内部配置 ID 使用。
- 不在首版实现调用方白名单、签名信任库或远程权限策略。

## 推荐方案

采用三层入口：

1. 主方案：Android Intent + `content://` URI。
2. 备用方案：Android Intent + JSON extra。
3. 辅助入口：Deep Link 只打开导入说明或导入入口，不承载敏感 payload。

`content://` URI 是主推荐方式，适合多配置、包含密钥、较大 payload 和长期兼容。JSON extra 只适合小体积 payload。Deep Link 不用于传输 API Key。

## 用户流程

1. 第三方 App 发起 Android Intent。
2. Apilot 读取 Intent 中的 `content://` URI 或 JSON extra。
3. Apilot 解析并校验 payload。
4. Apilot 打开“第三方导入来源说明页”。
5. 用户确认来源可信后，点击“继续查看”。
6. Apilot 打开“导入确认页”，展示配置预览。
7. 用户点击“确认导入”。
8. Apilot 为每条配置生成新 ID，并写入数据库。
9. Apilot 展示导入结果，包括成功数量、失败数量和失败原因。

## Android Intent 接口

### Action

```text
com.apilot.intent.action.IMPORT_API_CONFIGS
```

### MIME Type

```text
application/vnd.apilot.api-configs+json
```

### Data

推荐传入一次性授权的 `content://` URI：

```kotlin
intent.setDataAndType(uri, "application/vnd.apilot.api-configs+json")
intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
```

### Extras

备用 JSON 字符串：

```text
com.apilot.extra.API_CONFIGS_JSON
```

可选来源展示名：

```text
com.apilot.extra.SOURCE_NAME
```

可选请求 ID，用于调用方日志排查：

```text
com.apilot.extra.REQUEST_ID
```

### 调用建议

第三方 App 必须显式设置 Apilot 包名，避免系统选择器误导用户。首版以 `android/app/build.gradle.kts` 中的 `applicationId` 作为公开包名；如果发布包名变更，必须同步更新 App 内文档和 GitHub 文档。

## Payload Schema

顶层 JSON 使用独立 schema，不直接等同于 Apilot 全量备份格式。

```json
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
```

### 顶层字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `schemaVersion` | number | 是 | 首版固定为 `1`。 |
| `source` | object | 否 | 调用方声明的来源信息，仅用于展示和排查，不作为信任依据。 |
| `options.containsSecrets` | boolean | 否 | 调用方声明是否包含密钥。Apilot 仍会自行扫描 `apiKey`。 |
| `apiConfigs` | array | 是 | 待导入 API 配置列表。 |

### 配置字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 是 | 配置名称。 |
| `baseUrl` | string | 是 | API Base URL。 |
| `models` | string[] | 是 | 可用模型列表，至少一个模型。 |
| `apiKey` | string | 否 | 可为空或缺失。缺失时导入为待补 Key 配置。 |
| `environment` | string | 否 | 缺省为 `development`。 |
| `group` | string | 否 | 配置分组。 |
| `tags` | string[] | 否 | 标签列表。 |
| `metadata` | object | 否 | 第三方扩展信息。 |

第三方传入的 `id`、`createdAt`、`updatedAt` 不参与写库。Apilot 导入时生成新 `id`，并使用导入时间作为创建和更新时间。

## 密钥策略

- 支持带 API Key 和不带 API Key 两种 payload。
- 如果任何配置包含非空 `apiKey`，来源说明页和确认页都必须显示“包含密钥”。
- 页面不展示完整 API Key，只显示是否包含密钥。
- 文档明确禁止通过 Deep Link URL 传输 API Key。
- 推荐第三方 App 使用 `content://` URI 传输包含密钥的 payload。

## 冲突策略

第三方导入永远保留两份，不覆盖现有配置。

- Apilot 不使用第三方传入的 `id`。
- 每条导入配置都生成新的内部 ID。
- 如果导入配置与现有配置名称、Base URL 或模型组合相似，确认页显示“将作为新配置导入”。
- 为便于用户区分，导入配置名称统一追加时间后缀：`（导入 yyyy-MM-dd HH:mm）`。冲突判断只用于提示，不用于阻止导入。

## 页面设计

### 来源说明页

标题：第三方 App 请求导入 API 配置

展示内容：

- 来源 App 名称。
- 来源包名。
- 可获取时展示签名摘要。
- 请求 ID。
- 配置数量。
- 是否包含 API Key。
- 固定导入规则：不会覆盖现有配置，重复项会作为新配置保存。
- 风险提示：仅在确认第三方 App 可信时继续。

操作：

- 取消。
- 继续查看。

### 导入确认页

展示内容：

- 配置名称。
- Base URL。
- 模型数量。
- 是否包含 API Key。
- 分组和标签。
- 重复提示：将作为新配置导入。
- 单条校验失败原因。

操作：

- 返回。
- 确认导入。

### 导入结果

展示内容：

- 成功导入数量。
- 失败数量。
- 失败项原因摘要。

首版使用 Dialog 呈现导入结果。全部成功时显示成功数量；存在失败项时显示成功数量、失败数量和失败原因摘要。

## App 内文档

设置页新增“开发者”分区，并添加入口：

```text
第三方导入接入文档
```

App 内文档保持精简，包含：

- 接口用途。
- 推荐接入方式：Intent + `content://`。
- Kotlin 最小示例。
- JSON 最小示例。
- API Key 安全提醒。
- GitHub 完整文档链接和复制按钮。

## GitHub 文档

新增完整文档：

```text
docs/android-third-party-import.md
```

文档内容包括：

- 接口版本。
- Intent action、MIME type、extra 常量。
- `content://` 接入示例。
- JSON extra 备用示例。
- Payload schema。
- 字段说明。
- 安全建议。
- 冲突策略。
- 用户确认流程。
- 常见错误和排查。

## 技术落点

### Android 层

- 在 `AndroidManifest.xml` 为 `MainActivity` 增加导入 Intent filter。
- 处理冷启动初始 Intent。
- 处理已打开时的 `onNewIntent`。
- 对 `content://` 只申请一次性读取，不持久保存 URI 权限。

### Flutter 层

- 新增第三方导入接收服务，例如 `ThirdPartyImportService`。
- 服务职责：
  - 接收 Android Intent payload。
  - 读取 `content://` 或 JSON extra。
  - 校验 schema。
  - 归一化为待导入配置。
  - 生成导入预览数据。
- 复用现有 `ApiConfig`、`ImportExportService` 和 `DatabaseService`，但外部导入解析与现有备份恢复解析分开，避免把第三方 schema 和内部备份 schema 绑定。

## 错误处理

| 场景 | 处理 |
| --- | --- |
| 无 payload | 显示“无法读取导入请求”。 |
| URI 无法读取 | 显示“无法读取第三方提供的配置文件”。 |
| MIME type 不匹配 | 显示“不支持的导入类型”。 |
| JSON 格式错误 | 显示“导入格式不是有效 JSON”。 |
| `schemaVersion` 不支持 | 显示“导入格式版本不支持”。 |
| 单条配置缺少必填字段 | 标记该条失败，其他合法项仍可继续。 |
| JSON extra 过大 | 提示调用方改用 `content://` URI。 |
| 配置包含密钥 | 继续流程，但在来源说明页和确认页高亮提示。 |

## 测试范围

### 单元测试

- 解析合法 payload。
- 支持带 API Key 的配置。
- 支持不带 API Key 的配置。
- 忽略第三方传入的 `id`。
- 缺少 `name`、`baseUrl` 或 `models` 时返回明确错误。
- 重复配置导入时生成新 ID。
- `containsSecrets` 与实际 `apiKey` 不一致时，以实际扫描结果为准。

### Android 验证

- 冷启动接收 Intent。
- 已打开 App 时接收 `onNewIntent`。
- 读取授权的 `content://` URI。
- 读取 JSON extra 小 payload。
- 拒绝无法读取或无效格式的请求。

### 回归验证

- 设置页现有备份功能正常。
- 设置页现有恢复功能正常。
- `flutter test` 通过。
- `flutter analyze` 通过。
- Android debug build 通过。

## 兼容策略

- `schemaVersion: 1` 是首版公开格式。
- 新增字段默认向后兼容。
- 删除字段或改变必填字段需要升级 schemaVersion。
- 未识别字段默认忽略；需要保留的第三方扩展字段应放入 `metadata`。

## 通过标准

- 任意第三方 App 可以按文档唤起 Apilot。
- Apilot 能展示来源说明页和导入确认页。
- 用户确认前不会写入数据库。
- 带密钥和不带密钥的导入都能完成。
- 重复配置不会覆盖旧配置。
- App 内和 GitHub 都能找到接入文档。
- 现有备份/恢复功能没有回归。
