# Countdown Todo

Countdown Todo is a Flutter productivity app combining todos, recurring habits,
countdowns, courses, focus sessions, plan blocks, collaboration, statistics,
calendar integration and AI-assisted actions.

Current Flutter package version: **5.4.22**. Documentation was reconciled with
the working tree on **2026-07-20**.

## Supported surfaces

- Android: notifications, home-screen widgets, HyperOS/HyperIsland integration,
  usage statistics and Xiaomi band communication.
- Windows: desktop client and a separate dynamic-island/floating-window host.
- macOS: menu bar, WidgetKit widgets, launch-at-login, deep links and a native
  island/status display.
- Web: Flutter web client using the Zero Trust API proxy.
- iOS: Flutter host project exists; feature parity should be verified before a
  release claim.
- Companion projects: React web app in `webpage/web/` and Xiaomi band app in
  `CountDownTodo-band/`.

## Architecture at a glance

- UI and feature code: `lib/screens/`, `lib/widgets/`, and
  `lib/windows_island/`.
- Shared models: `lib/models.dart`.
- Persistence and sync: `lib/storage_service.dart`, `lib/services/`, and local
  SQLite schema v32.
- Active backend: external `CDT-server/debug/` development tree on Alibaba
  Cloud. Native clients connect directly; web uses
  `https://api-cdt.junpgle.me/`.
- Compatibility backend: Cloudflare Worker in `math-quiz-backend/`.
- AI interoperability: local MCP server in `mcp-server/`, exposing personal
  todos to compatible AI hosts while preserving the existing sync oplog.

See [documentation index](docs/README.md),
[project architecture](docs/PROJECT_ARCHITECTURE.md), and
[contribution guide](CONTRIBUTING.md).

## Local development

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

Use only development backend configuration and never commit credentials,
keystores, certificates, private accounts, or production deployment files.

## MCP integration

The local stdio server in [`mcp-server/`](mcp-server/) lets compatible AI hosts
query and manage personal todos. See the MCP server README for installation,
database-path setup, read-only mode and client configuration.
