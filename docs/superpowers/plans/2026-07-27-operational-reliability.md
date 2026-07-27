# Operational Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 扫码直接、可诊断地调用本机相机，同时把质量门禁、第三方接入示例和局域网同步去重落到可验证的工程实现中。

**Architecture:** 扫码层由 `MainActivity` 统一请求 Android 相机权限，在授权后直接启动 ZXing `CaptureActivity`，不再依赖 Google Play 服务扫码器的间接 UI。同步层将“相同服务地址、密钥、默认模型”的配置视为业务同一项，但第三方 Intent 导入仍保持追加策略。CI 将验证与发布拆开；示例 App 只演示公开 Intent 合约，不持久化 API Key。

**Tech Stack:** Flutter/Dart、Kotlin、AndroidX Core、ZXing Android Embedded、sqflite、GitHub Actions、Android Gradle。

---

### Task 1: 直接相机扫码和权限状态

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/api_manager/MainActivity.kt`
- Modify: `lib/features/sync/screens/qr_scanner_screen.dart`
- Modify: `android/app/build.gradle.kts`
- Test: `test/unit/sync/qr_scanner_status_test.dart`

- [ ] 先定义 Dart 端对 `camera_permission_denied`、`camera_permission_permanently_denied`、`qr_scan_failed` 的展示文案，运行测试确认当前失败。
- [ ] 删除 GMS Code Scanner 的首选调用；通过 `ContextCompat.checkSelfPermission`、`ActivityCompat.requestPermissions` 和 `onRequestPermissionsResult` 管理 `CAMERA` 权限。
- [ ] 在获得授权后直接以 `startActivityForResult(Intent(this, CaptureActivity::class.java), QR_SCAN_REQUEST_CODE)` 打开 ZXing，并在取消、权限拒绝、Activity 启动失败时清除待回传结果。
- [ ] Dart 端将永久拒绝映射为“打开系统设置”操作，将普通拒绝映射为“再次请求权限”，其余失败保留手动输入入口。
- [ ] 运行扫码状态测试、`dart analyze lib test` 和 `flutter build apk --release`。

### Task 2: 同步业务级去重

**Files:**
- Modify: `lib/features/sync/services/sync_service.dart`
- Modify: `lib/core/services/database_service.dart`
- Test: `test/unit/services/sync_service_test.dart`

- [ ] 先写测试：相同 `baseUrl`、相同 API Key、相同默认模型的不同 ID 配置在同步接收时只保存一份；同 URL 但 Key 或模型不同必须保留。
- [ ] 在 `DatabaseService` 增加仅供同步使用的查询，按规范化 URL、Key 与 `selectedModel` 查找等价配置；不将 API Key 写入日志或新索引。
- [ ] 令 `SyncService._handleSyncRequest` 和双向同步流程只写入未知业务身份的配置，并在响应/状态中返回实际新增数。
- [ ] 保持第三方 Intent 导入的“永远追加”行为不变，运行同步、导入和数据库全量测试。

### Task 3: 让分组管理实际驱动 API 归属

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/features/api_management/providers/api_provider.dart`
- Modify: `lib/features/api_management/screens/api_form_screen.dart`
- Modify: `lib/features/api_management/screens/group_manage_screen.dart`
- Test: `test/unit/services/database_service_group_test.dart`
- Test: `test/unit/providers/api_provider_group_test.dart`

- [ ] 先写失败测试：没有 API 的已管理分组仍出现在表单/筛选候选中；重命名分组会同步其 API 归属；删除分组只清空归属而不删除 API。
- [ ] 保持 `api_configs.api_group` 保存分组名称以兼容历史数据；在同一数据库事务中将改名传播到关联 API，并在删除前将关联 API 的 `api_group` 置空。
- [ ] `ApiProvider` 同时加载 `groups` 表和 API 中遗留的分组名；表单仅允许选择已管理分组或“未分组”，列表筛选显示没有 API 的已管理分组。
- [ ] 分组管理页在写入后刷新 `ApiProvider`，删除确认文案明确 API 方案会保留且变为未分组；运行数据库、Provider 和全量 widget/unit 测试。

### Task 4: 完整备份、恢复和文件位置选择

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/core/services/import_export_service.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/unit/services/database_service_backup_restore_test.dart`

- [ ] 先写失败测试：完整备份恢复会保留分组和 API 归属；“清空后恢复”会移除旧记录并返回实际恢复计数。
- [ ] 让数据库在一个事务中恢复 groups 和 API configs；合并恢复按备份 ID 写入，清空后恢复同时删除旧请求历史、API 和分组后写入快照。
- [ ] 导出时读取完整分组表；使用 `file_picker` 让用户决定 `.json` 备份文件的保存位置，恢复时用系统文件选择器读取任意 `.json` 文件，不再依赖 Documents 下的固定文件名。
- [ ] 恢复前展示快照时间、配置数、分组数和合并/清空恢复选择；完成后刷新 API Provider，运行备份测试、全量测试和 Android/macOS/Windows 构建。

### Task 5: 自动化质量门禁和示例调用方

**Files:**
- Modify: `.github/workflows/build.yml`
- Create: `examples/android-api-profile-client/settings.gradle.kts`
- Create: `examples/android-api-profile-client/build.gradle.kts`
- Create: `examples/android-api-profile-client/app/build.gradle.kts`
- Create: `examples/android-api-profile-client/app/src/main/AndroidManifest.xml`
- Create: `examples/android-api-profile-client/app/src/main/kotlin/com/apilot/exampleclient/MainActivity.kt`
- Create: `examples/android-api-profile-client/README.md`
- Modify: `docs/android-third-party-import.md`

- [ ] 新增 `verify` job，在 pull request 和 `main` push 时执行 `dart analyze lib test`、`flutter test`；Release 三端构建继续仅由 `v*` 标签触发，且先依赖验证 job。
- [ ] 建立最小 Android 示例 App：一个“导入到 Apilot”按钮发出 V2 `IMPORT_API_CONFIGS`，一个“从 Apilot 选择”按钮使用 Activity Result API 发出 `PICK_API_CONFIG`。
- [ ] 示例必须同时处理 `EXTRA_API_CONFIG_JSON` 和 `Intent.data` 的 `content://` JSON；日志中只显示服务商、协议、默认模型和 scope，不显示 API Key。
- [ ] 在 README 与正式接入文档中给出运行方式、包名替换说明和验证步骤；构建示例项目与主项目分析/测试。

### Task 6: 发布记录和维护文档

**Files:**
- Modify: `docs/superpowers/plans/2026-07-27-v2-api-profile-interoperability.md`
- Modify: `docs/MAINTAINER_NOTES.md`
- Modify: `CHANGELOG.md`

- [ ] 将已经完成的 V2 互操作计划任务标记为完成，并记录 `v1.19.0` 的提交、标签、Release 和四个平台资产验证结果。
- [ ] 记录直接相机扫码的运行机制、真机验收步骤和“纯蓝牙配置传输须使用分片、ACK、加密、冲突合并”的边界。
- [ ] 添加下一版本的未发布条目，说明相机链路、分组关联、完整备份恢复、同步去重、CI 与示例接入改动。
- [ ] 运行 `git diff --check`、完整分析、完整测试和三端可构建性检查后提交。
