# Contributing to Countdown Todo

Thanks for improving the project. This guide reflects the repository on
2026-07-20.

## Before changing code

1. Read `AGENTS.md` and the relevant document under `docs/`.
2. Keep unrelated working-tree changes intact.
3. Identify the platform boundary and the source of truth: Flutter client,
   native host, external Alibaba development server, Worker compatibility
   backend, React web app, or band companion.

## Development workflow

```bash
flutter pub get
flutter analyze
flutter test
dart format lib test
```

Run targeted tests while iterating, then the widest practical checks. Platform
builds require the corresponding toolchain. The release scripts in `scripts/`
include `build_macos.sh`, `sync_macos_version.sh`, `deploy_web_beta.sh`, and
`release_all.sh`.

`release_all.sh` calls the existing macOS and Web scripts, builds the three
Android APK ABIs, generates the arm64-v8a delta, and collects the macOS ZIP,
three APKs, and delta into one versioned directory for manual upload.

For the retained Worker:

```bash
cd math-quiz-backend
npm install
npm run dev
npm test
```

For the band app:

```bash
cd CountDownTodo-band
npm run start
npm run build
npm run lint
```

## Backend changes

The primary server is maintained in a separate `CDT-server` checkout. New
features belong in `debug/`. Do not edit its production `math_quiz_backend/`
tree without explicit authorization. Keep direct native access, the web Zero
Trust proxy, and WebSocket behavior compatible. Changes under this repository's
`math-quiz-backend/` affect only the legacy-compatible Worker path.

## Quality expectations

- Follow Flutter lints and use `dart format`.
- Use Material 3 `ColorScheme` values for custom UI.
- Add `flutter_test` coverage for behavior that can regress, especially sync,
  recurrence, storage, parsing, notification policy, and platform guards.
- Never commit secrets, signing material, private account data, or deployment
  configuration.
- Explain skipped tests and platform limitations in the PR.

Release commits use Chinese, version-prefixed summaries such as
`v5.5 【修复】循环待办同步问题`. A PR should include its scope, tests, issue
links, UI screenshots/recordings when relevant, and notes about version,
permissions, assets, backend, migration, and platform risk.
