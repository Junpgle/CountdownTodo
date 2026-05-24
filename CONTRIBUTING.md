# 贡献指南

感谢参与 CountDownTodo / Uni-Sync 的开发。这个仓库同时包含 Flutter 主应用、多个平台壳、两套后端和手环伴侣应用；提交前请先确认改动范围，避免影响无关平台或生产环境。

## 开始之前

1. 从仓库根目录运行 Flutter 相关命令。
2. 阅读 [Readme.md](Readme.md)、[AGENTS.md](AGENTS.md) 和相关功能文档。
3. 先用 `git status` 确认当前工作区状态，避免覆盖他人的本地改动。
4. 明确本次改动属于 Flutter 主应用、平台代码、后端、文档、资源还是手环应用。

## 仓库结构

- `lib/`：Flutter 主应用代码，按 screens、widgets、services、models、utilities、course import、Windows island 等功能组织。
- `test/`：Flutter 测试，尽量镜像 `lib/` 结构。
- `android/`、`windows/`、`macos/`、`ios/`、`linux/`、`web/`：平台壳和平台专属代码。
- `assets/`、`splash/`、`wallpaper/`：资源目录，资源声明在 `pubspec.yaml`。
- `aliyun_debug/`：Alibaba Cloud 调试后端，新后端能力优先修改这里。
- `math-quiz-backend/`：Cloudflare Worker 后端，用于保留兼容行为。
- `CountDownTodo-band/`：小米手环应用。
- `docs/`：项目文档、功能说明和排查报告。

## 开发原则

- 优先沿用现有目录、命名、服务分层和 UI 组件模式。
- 改动应聚焦当前任务，不混入无关重构、格式化或生成文件。
- 新增功能优先放在已有 feature 文件夹下，不随意创建宽泛的顶层目录。
- 涉及同步、存储、网络、番茄钟、课程导入、AI action、冲突处理等共享逻辑时，要补充有针对性的测试。
- 修改 UI 时，保持现有视觉风格和交互习惯；涉及可见流程的改动应补充截图、录屏或 widget 测试。

## 后端和网络规则

- 本项目保留 Alibaba Cloud 与 Cloudflare Worker 两套后端。
- 新后端能力默认面向 Alibaba Cloud，并只修改 `aliyun_debug/`。
- 不要修改 `aliyun_release/`，除非任务明确要求发布侧变更。
- 不要破坏现有 Cloudflare 兼容行为，除非任务明确说明要迁移或删除。
- Windows 和 Android 客户端直接通过 HTTP 访问 Alibaba Cloud 服务。
- Web 通过 Cloudflare Zero Trust 访问 `https://api-cdt.junpgle.me/`。
- 番茄钟多端感知和协同实时同步依赖 WebSocket；修改网络代码时必须保留平台特定 API 路径和 WebSocket 行为。

## 平台边界

- Windows island / floating-window 逻辑是 Windows-only。
- Android 不应导入、执行或初始化 Windows island / floating-window 相关逻辑。
- `[FloatWindow] Island window not found` 是 Windows island 日志，不要按 Android 问题处理。
- 平台专属问题应通过明确的平台判断修复，不要把平台专属实现扩散到其他平台。
- Kotlin、Swift、C++、平台资源和权限变更应限制在对应平台目录内。

## 代码风格

- Dart 遵循 `package:flutter_lints/flutter.yaml`。
- Dart 文件名使用 `snake_case.dart`。
- 类和枚举使用 `PascalCase`。
- 方法、字段和变量使用 `lowerCamelCase`。
- 提交前用 `dart format lib test` 或更小范围的 `dart format <file>` 格式化 Dart 改动。
- 不要提交临时诊断、构建产物、缓存文件或无关 IDE 变更。

## 常用命令

Flutter 主应用：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run -d <device>
.\scripts\run.ps1 -- -d windows
.\scripts\build.ps1 -Android
.\scripts\build.ps1 -Windows
.\scripts\build.ps1 -All
```

Cloudflare Worker 后端：

```bash
cd math-quiz-backend
npm install
npm run dev
npm test
```

小米手环伴侣应用：

```bash
cd CountDownTodo-band
npm run start
npm run build
npm run lint
```

## 测试要求

- Flutter 测试使用 `flutter_test`。
- 测试文件命名为 `*_test.dart`，放在 `test/` 下。
- 解析器、存储、同步、网络、service 行为应添加 focused tests。
- 可见 UI 流程应添加 widget tests，或在 PR 中提供截图/录屏说明。
- 后端改动应运行对应后端测试命令。
- 如果测试无法运行，必须在 PR 中写清楚跳过的命令和原因。

## 提交和 PR

Release 提交摘要使用中文版本前缀，例如：

```text
v4.3.x 【新增】...
v4.3.x 【优化】...
v4.3.x 【修复】...
```

PR 应包含：

- 改动摘要。
- 已运行的测试命令。
- 关联 issue 或背景说明。
- UI 变更的截图或录屏。
- 版本号、资源、权限、后端、平台专属风险说明。
- 如修改同步、存储或网络逻辑，说明兼容性和回滚风险。

## 安全要求

- 不要提交新的 secrets、签名密钥、凭据、keystore、证书或私有部署配置。
- 现有 keystore、证书和测试账号文档都按敏感信息处理。
- 不要暴露私有服务器细节，除非它们已经存在于项目配置中。
- 不要修改发布部署文件或生产后端文件，除非任务明确要求。

## 提交前检查清单

- 改动范围和任务目标一致。
- 没有修改 `aliyun_release/` 或生产配置，除非任务明确要求。
- Windows-only 逻辑仍然有平台守卫。
- Web、Android、Windows 的 API 路径和 WebSocket 行为没有被意外改变。
- Dart 代码已格式化，相关 analyze/test 已运行。
- 新增资源已在 `pubspec.yaml` 声明，并确认不会提交过大的无关文件。
- PR 描述包含测试结果、风险和必要截图。
