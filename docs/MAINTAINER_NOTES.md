# Apilot 维护交接说明

更新时间：2026-07-27

## 当前版本

- 应用版本：`1.20.0+25`
- GitHub Release 标签建议：`v1.20.0`
- 项目/软件名称统一为：`Apilot`

## 发布验证记录

- `v1.19.0` 对应提交 `67596b1`，已在 GitHub 作为正式 Release 发布。
- 已核验该 Release 含 `Apilot-v1.19.0.apk`、`Apilot-v1.19.0.dmg`、`Apilot-v1.19.0-windows-setup.exe` 和 `Apilot-v1.19.0-windows-portable.zip` 四类资产。
- `v1.20.0` 对应提交 `3f047b0`，GitHub Actions 的验证、Android、macOS、Windows 和 Release job 均已通过。
- 已核验该 Release 含 `Apilot-v1.20.0.apk`、`Apilot-v1.20.0.dmg`、`Apilot-v1.20.0-windows-setup.exe` 和 `Apilot-v1.20.0-windows-portable.zip` 四类资产。

## Android 签名策略

- 固定使用 `android/app/release-key.jks`。
- 本地 `android/key.properties` 指向：
  - `storeFile=release-key.jks`
  - `keyAlias=apilot`
- GitHub Actions 通过 Secrets 重建同一个 `release-key.jks`：
  - `KEYSTORE_BASE64`
  - `KEY_STORE_PASSWORD`
  - `KEY_PASSWORD`
  - `KEY_ALIAS`
- 不要重新生成 keystore；否则旧版 APK 无法覆盖升级。

## 局域网同步架构

- 核心文件：`lib/features/sync/services/sync_service.dart`
- 发现通道：UDP `45678`，同时使用多播 `224.0.0.1` 和广播 `255.255.255.255`。
- 配置传输：HTTP `45679`。
  - `GET /ping` 返回设备信息。
  - `GET /configs` 拉取本机配置。
  - `POST /sync` 接收对方配置。
- 设备 ID 存在 `SharedPreferences` 的 `apilot_sync_device_id`，保持稳定。
- 发现列表按 `device.id` 或 `ipAddress` 去重。
- 自身过滤同时检查本机设备ID、本机IP、UDP来源IP。
- 接收配置按 ID 更新；不同 ID 时再以规范化 Base URL、API Key、默认模型做业务级去重，只统计实际新增配置。第三方 Intent 导入不使用此规则，仍始终追加。

## 蓝牙同步设计

- 核心文件：`lib/features/sync/services/bluetooth_sync_service.dart`
- 依赖：`bluetooth_low_energy`。
- 蓝牙当前承担“近场发现/配对辅助”：
  - 本机作为 BLE Peripheral 广播 Apilot 服务。
  - 对方作为 BLE Central 扫描并读取设备信息。
  - 读到 IP 后回写到局域网同步设备列表。
- 配置数据仍通过 HTTP 局域网同步传输，原因是 API Key 配置体可能超过 BLE 小包传输的稳定范围。
- macOS 需要 `NSBluetoothAlwaysUsageDescription`、`NSBluetoothPeripheralUsageDescription` 和沙盒蓝牙 entitlement。
- Windows BLE 广播不支持设备名，代码使用 service data 兜底。
- `bluetooth_low_energy_darwin` 6.2.1 的 podspec 会把 `PrivacyInfo.xcprivacy` 当源码加入 Sources；`macos/Podfile` 的 `post_install` 会把它移到 Resources，避免 Xcode 26 构建失败。

## 扫码同步

- 核心文件：`lib/features/sync/screens/qr_scanner_screen.dart`
- Android 由 `MainActivity` 统一请求 `CAMERA` 权限，获准后直接启动内置 ZXing `CaptureActivity`，不依赖 Google Play 服务。
- 二维码格式由 `SyncScreen._showQRCode()` 生成：`ip|deviceId|deviceName`。
- 普通权限拒绝可重新请求；永久拒绝引导到系统设置；扫码失败或桌面平台不可用时显示手动 IP 输入兜底。真机验收应覆盖首次授权、拒绝后重试、永久拒绝后在设置页恢复权限、取消扫码和有效二维码连接。

## 分组与备份恢复

- `groups` 表是分组管理的唯一来源；API 仍用 `api_configs.api_group` 保存名称以兼容历史数据。
- 创建、编辑分组均禁止重名（英文不区分大小写）。重命名在事务中同步更新关联 API；删除分组只把关联 API 改为未分组。
- 备份包含 API、分组和 `exportedAt`；使用系统文件选择器选择保存和恢复路径。
- 恢复提供“合并恢复”和“清空后恢复”：后者会删除历史记录、API 和分组后再写入整个快照，所有写入在同一事务中完成。
- `file_picker` 固定为 `9.2.3`：`11.0.2` 在 AGP 9 下不会编译 Kotlin 插件类。`android/build.gradle.kts` 会将该库硬编码的 `compileSdk 34` 覆写为 36，以满足 `flutter_plugin_android_lifecycle` 的 AAR 元数据要求；升级此依赖前必须重新验证 Android release 构建。

## 第三方 API Profile 互操作

- 对外规范：`docs/android-third-party-import.md`；App 内入口位于设置 - 开发者 - 第三方接入文档。
- V1 Intent 和 schema 永久兼容；新增调用方使用 V2 `apiProfiles` 协议。
- V2 的 provider/protocol 是独立字段，标准 provider 为 `deepseek`、`openai`、`anthropic`、`google`、`custom`；不能用显示名替代 ID。
- V2 默认 scope 是 `connection` + `models.default`。`models.all`、`secret.api_key` 必须在授权页由用户单独勾选，Key 不允许默认外发。只有 Activity Result 调用包身份可被系统识别且签名匹配时才标记为“已验证包签名”；普通导入来源仅作声明展示。
- Android V2 回传支持 JSON extra 与一次性 FileProvider `content://` URI；URI 在 cache `third_party_results/` 中，10 分钟后清理，禁止记录 payload/Key 日志。
- 数据库 v2 增加 provider、protocol、模型目录和导入来源字段；v3 新增 `api_interop_audits`，只记录授权事实，不保存 Key 或 payload。
- 设置 - 数据管理中可查看和清除第三方交互记录。导入和授权完成动作必须写审计记录。

## 发布流程

1. 更新 `pubspec.yaml` 的 `version`。
2. 更新 `CHANGELOG.md` 顶部版本说明。
3. 确认 Android 签名文件没有被替换。
4. 本地运行：
   - `flutter pub get`
   - `dart analyze lib test`
   - `flutter test`
   - `flutter build apk --release`
   - `flutter build macos --release`
5. 打标签并推送：
   - `git tag vX.Y.Z`
   - `git push origin main vX.Y.Z`
6. GitHub Actions 会生成：
   - `Apilot-vX.Y.Z.apk`
   - `Apilot-vX.Y.Z.dmg`
   - `Apilot-vX.Y.Z-windows-setup.exe`
   - `Apilot-vX.Y.Z-windows-portable.zip`

PR 和 `main` 推送只运行 `verify`（`dart analyze lib test` 与 `flutter test`）；只有 `v*` 标签会在验证通过后构建三端资产并创建 Release。

## Windows 安装器

- Inno Setup 脚本：`windows/installer/Apilot.iss`
- CI 在 `windows-latest` 上安装 Inno Setup 并产出 `.exe`。
- 同时保留 portable zip，方便无需安装的场景。
- CI 里的 Inno Setup 不一定带中文语言文件；脚本只使用 `compiler:Default.isl`，不要直接引用 `Languages\ChineseSimplified.isl`。

## 后续建议

- 如需“纯蓝牙传配置”，建议单独设计分片协议、ACK/重传、加密和冲突合并，不要直接写大 JSON 到单个 characteristic。
- Release 说明建议只截取当前版本段落，避免整份 `CHANGELOG.md` 造成发布页重复冗长。
