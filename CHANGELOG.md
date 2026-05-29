# 更新日志

## v1.12.1 (2026-05-29)

### 重大修复
- **修复macOS不能联网** - Release.entitlements缺少`network.client`权限，沙盒模式下禁止了所有出站网络请求
- **修复macOS摄像头权限** - entitlements添加`device.camera`，Info.plist修正`NSCameraUsageDescription`位置
- **修复QR扫描崩溃** - 增加错误处理和重试机制，摄像头不可用时显示友好提示

---

## v1.12.0 (2026-05-29)

### 修复
- 版本号从1.6.0更新到1.12.0
- 局域网同步改用多播+广播双模式
- macOS DMG改为拖拽安装

### 新增
- QR码扫描功能
- 设备Ping检测

---

## v1.0.0 - v1.11.0

- 初始版本及基础功能迭代
