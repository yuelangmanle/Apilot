# Apilot 后端测试脚手架

本项目现在把验证拆成四层，优先使用后端输出，不依赖截图；只有要确认视觉布局时才需要截图：

## 1. Dart/Flutter 单测

```bash
APILOT_SKIP_ANDROID_BUILD=1 tool/run_quality_gate.sh
```

质量门禁会格式检查本轮涉及文件、运行 `flutter analyze`、全量 `flutter test`；默认还会构建 debug APK。
仓库历史文件可能不符合当前 formatter，因此不要用全目录 `dart format lib test tool` 作为门禁。
云端协议、SSE、附件、HTML 工具、视觉投影配对和余额历史均有可重复的本地测试；联网测试不需要真实 API Key。

## 2. Android 构建与安装

```bash
flutter build apk --debug
adb install -r -d build/app/outputs/flutter-apk/app-debug.apk
```

版本号由 `pubspec.yaml` 的 `version` 统一驱动 Android `versionName/versionCode`。

## 3. 真机后端诊断

连接设备后运行：

```bash
tool/apilot_device_diagnostics.sh
```

脚本返回 `summary.json`，并保存前台页面、包版本、PSS 内存、Graphics/native heap、`gfxinfo` 和最近 `logcat`。可指定设备和输出目录：

```bash
ANDROID_SERIAL=设备序列号 tool/apilot_device_diagnostics.sh build/device_diagnostics/before
```

抓取一次干净崩溃窗口时，先清日志再复现：

```bash
adb logcat -c
# 在手机上复现一次
 tool/apilot_device_diagnostics.sh build/device_diagnostics/after
```

这样能直接比较 `before/summary.json` 与 `after/summary.json`，无需先看截图或打开 IDE 终端。

## 4. 网关 API 冒烟测试

网关启动后，一条命令验证端口转发、健康状态、详细诊断和模型列表：

```bash
tool/apilot_gateway_smoke.sh
```

脚本会自动选择第一台 `adb` 设备（真机或模拟器），执行 `adb forward`，请求：

- `GET /v1/health`
- `GET /v1/diagnostics`
- `GET /v1/models`

响应正文、错误信息和 `summary.json` 会写入 `build/gateway_smoke/<时间>/`，便于后端直接比对，
不需要操作 UI 或查看截图。可指定设备和目录：

```bash
ANDROID_SERIAL=设备序列号 tool/apilot_gateway_smoke.sh build/gateway_smoke/after
```

聊天接口默认不调用，避免无意消耗云端额度或占用本地模型；需要时显式打开：

```bash
APILOT_GATEWAY_SMOKE_CHAT=1 \\
APILOT_GATEWAY_MODEL='模型 ID' \\
tool/apilot_gateway_smoke.sh
```

如果使用的是模拟器，`adb devices` 看到 `emulator-5554` 等设备后，脚本与真机使用方式完全相同。
模拟器适合验证导航、权限、下载状态和网关协议；不能替代真机的 GPU、内存压力、发热和本地推理速度验证。
