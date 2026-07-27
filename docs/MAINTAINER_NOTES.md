# Apilot 维护交接说明

更新时间：2026-07-27

## 当前版本

- 应用版本：`1.19.0+24`
- GitHub Release 标签建议：`v1.19.0`
- 项目/软件名称统一为：`Apilot`

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
- Android 优先使用 Google Play 服务的 Code Scanner；服务不可用时自动回退到内置 ZXing 扫码页，其余平台保留手动输入 IP。
- 二维码格式由 `SyncScreen._showQRCode()` 生成：`ip|deviceId|deviceName`。
- 扫码失败或桌面平台不可用时显示手动 IP 输入兜底。

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

## Windows 安装器

- Inno Setup 脚本：`windows/installer/Apilot.iss`
- CI 在 `windows-latest` 上安装 Inno Setup 并产出 `.exe`。
- 同时保留 portable zip，方便无需安装的场景。
- CI 里的 Inno Setup 不一定带中文语言文件；脚本只使用 `compiler:Default.isl`，不要直接引用 `Languages\ChineseSimplified.isl`。

## 后续建议

- 如需“纯蓝牙传配置”，建议单独设计分片协议、ACK/重传、加密和冲突合并，不要直接写大 JSON 到单个 characteristic。
- 同步合并策略目前以 ID 去重，后续可加入“同 URL+Key+模型”的业务级合并。
- Release 说明建议只截取当前版本段落，避免整份 `CHANGELOG.md` 造成发布页重复冗长。
