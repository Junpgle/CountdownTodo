# Repository Guidelines

## Project Structure

* Main Flutter app: `CountDownTodo`.
* Dart code lives in `lib/`, organized by screens, widgets, services, models, utilities, course import logic, and Windows island features.
* Platform code lives in `android/`, `windows/`, `macos/`, and `web/`.
* Assets are declared in `pubspec.yaml` and stored in `assets/`, `splash/`, and `wallpaper/`.
* Flutter tests belong in `test/`.
* Cloudflare Worker backend: `math-quiz-backend/`.
* Alibaba Cloud backend: `aliyun_debug/`, `aliyun_release/`.
* Xiaomi band companion app: `CountDownTodo-band/`.

## Backend & Network Rules

* The project has two backend systems: Cloudflare Worker and Alibaba Cloud.
* New backend features should target Alibaba Cloud.
* Only modify Alibaba Cloud backend files under `aliyun_debug/`.
* Do not modify `aliyun_release/` unless explicitly requested.
* Preserve compatibility with existing Cloudflare-backed behavior unless the task explicitly says to remove or migrate it.
* Windows and Android clients access the Alibaba Cloud server directly over HTTP.
* Web accesses the API through Cloudflare Zero Trust: `https://api-cdt.junpgle.me/`.
* Pomodoro multi-device awareness and collaborative real-time sync depend on WebSocket.
* Preserve platform-specific API paths and WebSocket behavior when changing networking code.

## Platform-Specific Rules

* Windows island / floating-window logic is Windows-only.
* `[FloatWindow] Island window not found` is a Windows island log.
* Android must not execute, import, or initialize Windows island / floating-window logic.
* Fix platform-specific issues with explicit platform guards instead of making Windows-only code cross-platform.
* Keep Kotlin, Swift, C++, and platform resource changes isolated to the platform involved in the task.

## Build, Test, and Development Commands

Run Flutter commands from the repository root:

* `flutter pub get`
* `flutter analyze`
* `flutter test`
* `flutter run -d windows`
* `flutter run -d <device>`
* `.\scripts\run.ps1 -- -d windows`
* `.\scripts\build.ps1 -Android`
* `.\scripts\build.ps1 -Windows`
* `.\scripts\build.ps1 -All`

For `math-quiz-backend/`:

* `npm install`
* `npm run dev`
* `npm test`

For `CountDownTodo-band/`:

* `npm run start`
* `npm run build`
* `npm run lint`

## Coding Style

* Follow `package:flutter_lints/flutter.yaml`.
* Format Dart with `dart format lib test`.
* Dart files use `snake_case.dart`.
* Classes and enums use `PascalCase`.
* Methods, fields, and variables use `lowerCamelCase`.
* Prefer adding code under existing feature folders instead of creating broad new top-level folders.
* Keep generated files, build output, and temporary diagnostics out of commits unless required for release.

## Testing Rules

* Use `flutter_test` for Flutter tests.
* Test files must be named `*_test.dart` and placed under `test/`.
* Mirror `lib/` structure in `test/` where practical.
* Add focused tests for parser, storage, sync, networking, and service behavior.
* Add widget tests for visible UI flows.
* Backend changes should pass the relevant backend test command.
* If tests cannot be run, clearly state which tests were skipped and why.

## Commit & PR Rules

* Release commits use Chinese version-prefixed summaries, for example:

    * `v4.3.x 【新增】...`
    * `v4.3.x 【优化】...`
    * `v4.3.x 【修复】...`
* Pull requests should include:

    * Summary of changes.
    * Test commands run.
    * Linked issues, if any.
    * Screenshots or recordings for UI changes.
    * Notes for version bumps, assets, permissions, backend changes, and platform-specific risks.

## Security Rules

* Do not commit new secrets, signing keys, credentials, keystores, certificates, or private deployment config.
* Treat existing keystores, certificates, and test account documents as sensitive.
* Do not expose private server details beyond existing configured endpoints.
* Do not change release deployment files or production backend files unless explicitly requested.
