# Apilot Android API Profile Client Example

这是一个独立、可运行的原生 Android 调用方，演示 Apilot V2 的两条公开能力：

- 通过 `IMPORT_API_CONFIGS` 将一个 DeepSeek API Profile 导入 Apilot。
- 通过 `PICK_API_CONFIG` 让用户从 Apilot 选择一条已保存方案，并同时处理 JSON extra 与临时 `content://` URI 回传。

示例不会在页面、日志或持久化存储中输出 API Key。Key 只会在用户输入后作为 V2 导入 payload 的 `secrets.apiKey` 发送给 Apilot。

## 运行

1. 先安装 Apilot，当前包名为 `com.example.api_manager`。
2. 用 Android Studio 打开本目录，或在本目录执行：

```bash
./gradlew :app:assembleDebug
```

3. 安装 `app/build/outputs/apk/debug/app-debug.apk`，打开示例。

真实接入时，替换 `APILOT_PACKAGE`、来源名称、Profile 内容和所请求的 scopes；只请求业务必需的 scope。完整协议见 [正式接入文档](../../docs/android-third-party-import.md)。
