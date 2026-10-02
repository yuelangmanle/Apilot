<div align="center">

# 🚀 Apilot

**智能 API 管理工具 - 让 AI API 管理变得简单高效**

[![GitHub Release](https://img.shields.io/github/v/release/yuelangmanle/Apilot)](https://github.com/yuelangmanle/Apilot/releases)
[![License](https://img.shields.io/github/license/yuelangmanle/Apilot)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20macOS%20%7C%20Windows-green)]()

[![GitHub Stars](https://img.shields.io/github/stars/yuelangmanle/Apilot?style=social)](https://github.com/yuelangmanle/Apilot/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/yuelangmanle/Apilot?style=social)](https://github.com/yuelangmanle/Apilot/network/members)

</div>

---

## 🔒 为什么可以放心把 Key 交给 Apilot

**密钥加密存储**（AES + HMAC，主密钥在系统安全区）· **数据只留在本机**（无账号、无服务器）· **同步双方确认 + 加密通道** · **开源可审计**。详见应用内「设置 → 数据与安全」。

---

## 🆕 最近更新（v2.7）
- **本地对话全流式**：工具模式也边生成边显示；每条回答下方显示 **tok/s · 耗时 · 首字延迟**。
- **动态生成预算 + 截断续写**：写网页/长文自动给大预算，断在半截会自动接着写。
- **上下文分层管理**：70% 先做零成本折叠，85%（可调）才调模型做**增量摘要**；
  用户说过的诉求原样保留，不再"纯按字数砍"。
- **性能三档**：省电 / 均衡 / 性能（线程数、GPU 卸载、FlashAttention、KV q8_0 量化），
  实测提速可达 50% 以上。
- **模型清单 24 个**：新增 Qwen3.5 0.8B/2B/4B/9B（会思考+能看图）、
  **MiMo-V2.6-Distill-Qwen-9B**、Qwen3-VL 2B/4B、MiniCPM-V 4.5、SmolVLM2、
  Gemma 3 4B QAT、Qwen3-8B、DeepSeek-R1-0528-Qwen3-8B 等。
- **网关后台保活**：安卓前台服务 + 常驻通知，切后台/锁屏也不掉线。
- **视觉投影收纳在主模型下**：默认收起、点击展开，不再单列成"假模型"。
- 体检余额**落盘并显示更新时间**；AI 设置里可**实时切换本地模型**。

## ✨ 功能特性

### 🎯 核心功能
- **多 API 统一管理** - 一站式管理 DeepSeek、小米 MiMo、魔塔、OpenAI、Claude 等主流 AI API
- **快速切换** - 一键切换不同 API 配置，高效便捷
- **模型列表自动获取** - 自动获取各平台可用模型列表
- **请求测试** - 内置 API 测试工具，快速验证配置
- **智能粘贴识别** - 从任意长度的 JSON、环境变量、YAML、Markdown、cURL 或说明文本中自动提取 API 地址和 Key，兼容转义 JSON、箭头分隔与行尾注释；会优先匹配同段的地址与 Key，名称、模型和分组仍由用户确认

### 🌙 暗黑模式
- 支持亮色/暗色主题切换
- 小清新配色设计，护眼舒适
- 自动跟随系统主题

### 📁 数据管理
- **导入导出** - JSON 格式配置导入导出
- **本地存储** - SQLite 数据库安全存储
- **历史记录** - 完整的请求历史追踪

### 📱 局域网同步
- **设备发现** - UDP 广播自动发现同一网络设备
- **QR 码配对** - 扫码快速配对其他设备
- **数据同步** - 支持发送/接收/双向同步
- **无需云服务** - 纯局域网传输，隐私安全

### 🔵 蓝牙直接传输
- **附近设备发现** - 通过 BLE 查找已打开 Apilot 蓝牙模式的设备
- **直接配置传输** - 发送、接收和双向同步均通过 BLE GATT 完成，不依赖同一 WiFi
- **传输确认与校验** - 接收方确认后才传输；内容分片并使用 SHA-256 校验完整性

### 🔗 第三方接入（Android 互操作）
其他 Android App 可以与 Apilot 桥接，互传 API 方案：

- **导入到 Apilot** - 通过 `IMPORT_API_CONFIGS` Intent 把配置（含语义化 API Profile）交给用户确认后导入
- **从 Apilot 授权读取** - 通过 `PICK_API_CONFIG` 让用户选择一条已保存方案；默认只返回连接信息与默认模型，模型目录和 API Key 需用户逐项勾选
- **文档与示例** - 📖 [第三方接入操作手册](docs/android-third-party-import.md) · 🧪 [可构建的 Android 调用示例](examples/android-api-profile-client) · 应用内入口：设置 → 开发者 → 第三方接入文档

### 🤖 本地大模型（离线可用）
- **模型商店** - 内置 11 个主流模型（Qwen3 全家桶、Spark-X2.5 端侧智能体 1.7B/4B、Gemma 3、Llama 3.2、Qwen2.5-VL 多模态、DeepSeek-R1 蒸馏）+ 实时接入 HuggingFace / 魔搭社区：展示真实文件清单与体积，按设备内存推荐量化版本
- **AI 精选 + 固定到本机** - 让 AI 浏览社区、写中文介绍、挑出适合你手机的几个模型固定保存（重启仍在）；粘贴多个仓库链接可批量解析入库
- **下载管理** - 独立二级入口：正在下载（实时进度/暂停）、未完成可断点续传、已下载模型管理、存储清理（逐项勾选，已下载模型默认不动）
- **本地对话** - 多轮对话、生成参数（温度/Top-P/最大长度）、思考过程折叠、图片与文本附件、对话持久化与历史对话列表；多模态模型可补装视觉投影（mmproj）直接看图，纯文本模型发图会给出明确提示
- **深度思考** - 仅对支持的模型（Qwen3 / DeepSeek-R1 / QwQ 等）开放开关
- **完全离线** - 基于 llama.cpp（Android Vulkan / 桌面 Metal/CPU），Key 与对话不出本机

### 🌐 本地网关（给其他 App 用）
- **两种后端** - 转发云端配置（Key 由网关注入）或直接用本机模型离线推理（不消耗额度）
- **两种模式** - 默认仅 127.0.0.1（最安全）；可选局域网模式（需 Token）
- **一键授权** - 第三方 App 发 `GRANT_GATEWAY` Intent：Apilot 弹确认页 → 启动网关 → 回传地址/模型/Token（协议见 [互操作文档](docs/android-third-party-import.md)）

### 🧩 AI 插件（逐个开关，真实后端）
- **联网搜索** - 内置多引擎（Bing 中国站 / DuckDuckGo / 百度）自动回退，无需配置 Key
- **抓网页** - 网址转纯文本（只允许公网地址；被墙站点需自备网络环境）
- **HTML 编写与自检** - AI 写页面 → 结构自检（标签开合、括号、引号）→ 反复修正 → 存成草稿
- **待办清单** - 多步任务自己列 to-do 并推进（面板可见）
- **截屏自查** - 截取屏幕；多模态模型可直接"看"画面
- **长期记忆** - 关键事实落盘，之后对话按相关性自动带上；可在工具箱查看/删除
- **找模型 / 入库 / 下载** - AI 直接查 HuggingFace / 魔搭 / GitHub，把选中的模型写进
  「我的社区模型」并开始下载（断点续传）
- **查询 Apilot 数据** - 列出方案、用量摘要、打开页面（只读）

### 🧠 AI 助手（可选）
- **错误诊断** - 请求失败时一键分析原因与解决步骤
- **用量分析** - 基于请求历史指出失败率、成本集中度等异常
- **识别兜底** - 粘贴文本正则识别失败时，由 AI 提取地址/Key/模型
- **请求体生成** - 一句话描述生成合法 JSON 请求体
- **来源可选** - 用云端 API 配置或本地模型执行；设置页实时显示当前生效来源

### 💬 云端 API 对话
- **多轮 Playground** - 直接对着某个 API 配置聊天：流式输出、上下文、思考过程折叠、停止生成、模型切换、系统提示词，对话记录按配置保存在本机

### 🎨 UI 设计
- Material Design 3 设计语言
- 小清新配色方案
- 流畅的动画过渡
- 响应式布局适配

---

## 📥 下载安装

前往 [GitHub Releases](https://github.com/yuelangmanle/Apilot/releases) 下载最新版安装包：

| 平台 | 推荐文件 | 说明 |
|:---|:---|:---|
| Android | `Apilot-vX.Y.Z.apk` | 固定 release keystore 签名，可覆盖升级 |
| macOS | `Apilot-vX.Y.Z.dmg` | 拖入 Applications 安装 |
| Windows | `Apilot-vX.Y.Z-windows-setup.exe` | 标准安装包 |
| Windows 绿色版 | `Apilot-vX.Y.Z-windows-portable.zip` | 解压即用 |

### 从源码构建

```bash
# 1. 克隆仓库
git clone https://github.com/yuelangmanle/Apilot.git
cd Apilot/api_manager

# 2. 安装依赖
flutter pub get

# 3. 运行应用
flutter run

# 4. 构建发布版
# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

---

## 🚀 快速开始

### 1️⃣ 添加 API 配置

打开应用后，点击右下角 **"+"** 按钮：

- **手动添加** - 填写 API 地址、Key、模型名称
- **从模板创建** - 选择预设模板快速配置

### 2️⃣ 使用 API 测试

选择已配置的 API，点击 **"测试"** 按钮：
- 选择模型
- 输入提示词
- 查看响应结果

### 3️⃣ 设备同步

点击顶部 **"同步"** 按钮：
- 确保设备在同一局域网
- 扫描 QR 码配对
- 选择同步方向（发送/接收/双向）

---

## 📸 界面预览

<div align="center">

| 主界面 | API 详情 | 暗黑模式 |
|:---:|:---:|:---:|
| ![主界面](screenshots/home.png) | ![详情](screenshots/detail.png) | ![暗黑](screenshots/dark.png) |

</div>

---

## 🛠️ 开发指南

### 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / Xcode (可选)

### 项目结构

```
api_manager/
├── lib/
│   ├── core/
│   │   ├── models/          # 数据模型
│   │   ├── services/        # 核心服务
│   │   └── data/            # 模板数据
│   ├── features/
│   │   ├── api_management/  # API 管理
│   │   ├── api_testing/     # API 测试
│   │   ├── settings/        # 设置
│   │   └── sync/            # 同步功能
│   ├── shared/
│   │   └── theme/           # 主题配置
│   ├── app.dart             # 应用入口
│   └── main.dart            # 主函数
├── test/                    # 测试文件
└── pubspec.yaml             # 依赖配置
```

### 运行测试

```bash
# 运行所有测试
flutter test

# 运行单元测试
flutter test test/unit/

# 运行集成测试
flutter test test/integration/
```

### 构建发布版

```bash
# Android APK
flutter build apk --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

---

## 📦 依赖项

| 依赖 | 用途 |
|------|------|
| `provider` | 状态管理 |
| `sqflite` | 本地数据库 |
| `http` | 网络请求 |
| `qr_flutter` | QR 码生成 |
| `path_provider` | 文件路径 |
| `json_annotation` | JSON 序列化 |

---

## 🤝 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 开发规范

- 遵循 Flutter 官方代码规范
- 使用 TDD 开发模式
- 提交前运行测试确保通过
- 保持代码简洁可读

---

## 📝 更新日志

### v1.0.0 (2026-05-29)
- ✨ 完成核心 API 管理功能
- ✨ 实现暗黑模式
- ✨ 实现导入导出功能
- ✨ 实现局域网同步
- ✨ 实现 QR 码配对
- ✨ 添加 24 个单元测试
- 🎨 小清新 UI 设计

---

## 📄 许可证

本项目基于 MIT 许可证开源 - 详见 [LICENSE](LICENSE) 文件

---

## 🙏 致谢

- [Flutter](https://flutter.dev) - 跨平台 UI 框架
- [Material Design](https://m3.material.io) - 设计规范
- 所有贡献者和用户

---

## 📮 联系方式

- GitHub: [@yuelangmanle](https://github.com/yuelangmanle)
- Issues: [GitHub Issues](https://github.com/yuelangmanle/Apilot/issues)

---

<div align="center">

**如果觉得有用，请给个 ⭐ Star 支持一下！**

[![Star History Chart](https://api.star-history.com/svg?repos=yuelangmanle/Apilot&type=Date)](https://star-history.com/#yuelangmanle/Apilot&Date)

</div>
