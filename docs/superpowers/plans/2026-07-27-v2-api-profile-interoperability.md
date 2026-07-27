# V2 API Profile Interoperability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Apilot 与任意 Android 第三方 App 能以可识别提供商、可控授权、可双向导入的 V2 协议交换 API 方案，同时完全保留 V1 行为。

**Architecture:** 保留现有两个公开 Intent action；Dart 层根据 `schemaVersion` 选择 V1 或 V2 codec。`ApiConfig` 新增稳定的提供商、协议、模型目录与来源字段，数据库升级到 v2；Android 原生层只为 V2 的 Activity Result 增加一次性 `content://` 回传，V1 继续使用 JSON extra。

**Tech Stack:** Flutter/Dart、sqflite migration、Kotlin Android Activity Result、FileProvider、Flutter unit tests、GitHub Actions。

---

### Task 1: 定义领域模型和识别规则

**Files:**
- Create: `lib/core/models/api_profile.dart`
- Create: `lib/core/services/api_profile_registry.dart`
- Modify: `lib/core/models/api_config.dart`
- Test: `test/unit/models/api_profile_test.dart`

- [ ] 先写提供商/协议识别、模型默认值和 URL 推测的失败测试。
- [ ] 定义 `deepseek`、`openai`、`anthropic`、`google`、`custom` 与 `openai_compatible`、`anthropic_messages`、`google_genai` 常量。
- [ ] 为 `ApiConfig` 添加 provider、protocol、selected model、目录模式/来源/刷新时间、导入来源和可信等级字段；没有显式值时使用兼容默认值。
- [ ] 运行 `flutter test test/unit/models/api_profile_test.dart`，确认通过。

### Task 2: 持久化 V2 语义

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `test/unit/services/database_service_test.dart`

- [ ] 先写写入并读回 V2 字段与 JSON metadata 的失败测试。
- [ ] 将数据库升级到 version 2，在 `onUpgrade` 中增加 V2 columns，旧记录使用 `custom/openai_compatible` 和旧模型列表首项回填默认模型。
- [ ] 用 JSON 而不是 `Map.toString()` 保存 metadata，并兼容已经写入的旧字符串。
- [ ] 运行数据库测试，确认全量旧字段与新字段均可读写。

### Task 3: 实现 V2 入站 codec

**Files:**
- Modify: `lib/features/third_party_import/models/third_party_import_models.dart`
- Modify: `test/unit/third_party_import/third_party_import_payload_test.dart`

- [ ] 先写 V2 DeepSeek 显式 provider、URL 推测 provider、无模型目录、未知服务商回退 custom 的失败测试。
- [ ] 支持 `schemaVersion: 2` 的 `apiProfiles`，将 provider/protocol、连接、密钥、模型目录和 origin 转换为候选配置。
- [ ] 保持 schemaVersion 1 的严格 models 校验不变；V2 不要求 `availableModels`，只校验 connection 的名称和 URL。
- [ ] 将调用来源保存为 import origin，按包签名/系统包名/调用方声明/未知计算可信等级。
- [ ] 运行第三方导入 payload 测试，确认 V1 回归与 V2 新用例均通过。

### Task 4: 实现 V2 出站授权和 codec

**Files:**
- Modify: `lib/features/third_party_import/models/third_party_import_models.dart`
- Modify: `lib/features/third_party_import/screens/third_party_api_config_pick_screen.dart`
- Modify: `lib/features/third_party_import/services/third_party_api_config_pick_channel.dart`
- Test: `test/unit/third_party_import/third_party_import_payload_test.dart`

- [ ] 先写 V2 默认不含 `apiKey`、显式 `secret.api_key` 才含 Key、`models.all` 才含候选模型、V1 输出不变的失败测试。
- [ ] 解析 `schemaVersion`、`requestedScopes` 和 `returnTransport`；V2 默认只允许 `connection` 和 `models.default`。
- [ ] 授权页显示来源可信等级、服务商/协议、模型目录信息，并在用户明确勾选后才授予可选 Key 与完整模型列表。
- [ ] V2 JSON 返回 `connection`、`provider`、`protocol`、`models`、`origin`、`grantedScopes`；V1 继续返回原 `apiConfig` 格式。
- [ ] 运行第三方 codec 测试，确认通过。

### Task 5: 提供 V2 content URI 回传

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/api_manager/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/res/xml/third_party_result_paths.xml`

- [ ] 将 `schemaVersion`、scope 和回传传输偏好透传给 Flutter。
- [ ] 对 V2 的 `content_uri` 或自动大 payload，在 cache 文件写入 UTF-8 JSON，通过 FileProvider 返回 URI、MIME type 和 `FLAG_GRANT_READ_URI_PERMISSION`。
- [ ] 对 V1 或显式 `extra` 保持 `com.apilot.extra.API_CONFIG_JSON` 回传。
- [ ] 对缓存文件以 request id 隔离、随机命名，且不在日志中记录内容或 Key。

### Task 6: 主 App 可见的 V2 信息

**Files:**
- Modify: `lib/features/api_management/providers/api_provider.dart`
- Modify: `lib/features/api_management/screens/api_detail_screen.dart`
- Modify: `lib/features/api_management/widgets/api_card.dart`

- [ ] 更新模型刷新流程：刷新成功时更新目录来源和刷新时间，并在无旧默认模型时选取第一个模型。
- [ ] 在卡片与详情中展示 provider、protocol、默认模型、模型目录来源/时间和导入来源，不展示敏感信息。
- [ ] 运行现有模型刷新测试及相关 widget/unit tests。

### Task 7: 更新双向接入文档

**Files:**
- Modify: `docs/android-third-party-import.md`
- Modify: `lib/features/third_party_import/screens/third_party_import_docs_screen.dart`
- Modify: `docs/MAINTAINER_NOTES.md`

- [ ] 记录 V1/V2 的选择规则、完整 V2 schema、scope、provider/protocol 规范、错误码、取消结果、URI 读取与安全限制。
- [ ] 加入 Kotlin 的 V2 导入与选择回传示例，处理 extra 或 `data` URI 两种结果。
- [ ] 说明 DeepSeek 等服务商如何通过 `provider.id` 保留语义，无法识别时为何回退到 custom。

### Task 8: 发布 v1.19.0

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`

- [ ] 将版本设置为 `1.19.0+24`，更新版本日志和维护说明。
- [ ] 运行 `dart run build_runner build --delete-conflicting-outputs`、`dart format`、`dart analyze lib test`、`flutter test`、`flutter build apk --debug`。
- [ ] 审查 diff，提交、推送 `main`，创建并推送 `v1.19.0` tag。
- [ ] 等待 GitHub Release workflow，确认 Release 与 Android/macOS/Windows 资产状态后记录结果。
