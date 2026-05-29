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

## ✨ 功能特性

### 🎯 核心功能
- **多 API 统一管理** - 一站式管理 DeepSeek、小米 MiMo、魔塔、OpenAI、Claude 等主流 AI API
- **快速切换** - 一键切换不同 API 配置，高效便捷
- **模型列表自动获取** - 自动获取各平台可用模型列表
- **请求测试** - 内置 API 测试工具，快速验证配置

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

### 🎨 UI 设计
- Material Design 3 设计语言
- 小清新配色方案
- 流畅的动画过渡
- 响应式布局适配

---

## 📥 下载安装

### Android

📱 **直接安装**

前往 [GitHub Releases](https://github.com/yuelangmanle/Apilot/releases) 下载最新版 APK：

```
API管理器.apk
```

### macOS / Windows

💻 **从源码构建**

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
