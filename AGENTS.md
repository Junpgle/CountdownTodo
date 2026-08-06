# Repository Guidelines

Last reviewed against the working tree: 2026-07-20.

## Project layout

- Flutter client: repository root; Dart source in `lib/`, tests in `test/`.
- Platform hosts: `android/`, `ios/`, `macos/`, `windows/`, and `web/`.
- React web companion: `webpage/web/`.
- Xiaomi band companion: `CountDownTodo-band/`.
- Legacy-compatible Cloudflare Worker: `math-quiz-backend/`.
- Alibaba Cloud server: separate checkout `CDT-server`; development code is in
  `debug/`, while `math_quiz_backend/` is production code.
- Assets: `assets/`, `splash/`, and `wallpaper/`.

## Backend and network rules

- New server features target the Alibaba Cloud server.
- Only change `CDT-server/debug/` during normal development. Do not change the
  production `CDT-server/math_quiz_backend/` tree unless explicitly requested.
- Preserve the Cloudflare Worker compatibility path unless a task explicitly
  removes or migrates it.
- Native Windows and Android clients use the Alibaba Cloud HTTP/WebSocket
  endpoints directly. Flutter web uses `https://api-cdt.junpgle.me/` through
  Cloudflare Zero Trust.
- Pomodoro device awareness and collaborative live sync depend on WebSocket;
  preserve platform-specific URL selection and WebSocket behavior.

## Platform boundaries

- Windows island/floating-window code is Windows-only. Android must not import,
  initialize, or execute it; use explicit platform guards.
- macOS has its own menu bar, WidgetKit, launch-at-login, and native island
  integrations. Keep Swift/Kotlin/C++ and platform resources isolated.

## Build and test

Run Flutter commands at the repository root:

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
dart format lib test
```

Repository scripts currently available:

```bash
./scripts/build_macos.sh
./scripts/sync_macos_version.sh
./scripts/deploy_web_beta.sh
./scripts/release_all.sh --help
```

Cloudflare Worker:

```bash
cd math-quiz-backend
npm install
npm run dev
npm test
```

Band companion:

```bash
cd CountDownTodo-band
npm run start
npm run build
npm run lint
```

## Code and UI conventions

- Follow `package:flutter_lints/flutter.yaml`; Dart filenames use
  `snake_case.dart`, types use `PascalCase`, and members use `lowerCamelCase`.
- Add code under an existing feature folder when possible.
- The app uses Material 3 dynamic colors. Custom UI must derive colors from
  `Theme.of(context).colorScheme`, not hard-code standard colors.
- Keep generated files, build output, credentials, certificates, keystores,
  and private deployment configuration out of commits.

## Testing and delivery

- Put Flutter tests in `test/` as `*_test.dart`, mirroring `lib/` where useful.
- Prioritize focused tests for parsing, storage, sync, networking, recurrence,
  notifications, and services; use widget tests for visible flows.
- State which commands ran and which were skipped.
- Release commit summaries use the current version prefix, for example
  `v5.5 【修复】...`, `v5.5 【优化】...`, or `v5.5 【新增】...`.
- PRs should summarize changes, tests, linked issues, UI evidence, and any
  version, asset, permission, backend, or platform risk.
