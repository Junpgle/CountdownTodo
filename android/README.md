# android/ — Android 原生对接层

## 📌 目录职责

包含 Android 平台的原生配置与代码实现。除了标准的 Flutter 壳程序外，本项目在此处实现了多项关键原生特性。

---

## 🚀 关键原生特性

1. **HyperOS 灵动岛集成**:
   - 位于 `app/src/main/kotlin/.../MainActivity.kt`
   - 通过 `Notification.Builder` 对接小米 HyperOS 的实况窗（Dynamic Island）协议。
   - 支持番茄钟倒计时在系统状态栏的实时显示。

2. **桌面小组件 (Widgets)**:
   - 实现了 Android 原生小组件，同步展示今日待办与课程。

3. **权限管理**:
   - 配置了 UsageStats 权限，用于屏幕时间统计。
   - 配置了通知权限与通知渠道设置。

4. **自动化脚本**:
   - 包含 `verify_fix.ps1` 等辅助修复 native 编译问题的脚本。

---

## 🛠️ 编译说明

- 使用 Gradle 进行构建。
- **Kotlin 版本**: 配合 Flutter 插件推荐版本。
- **签名配置**: 需在 `key.properties` 中指定。

---

*最后更新：2026-04-24*
