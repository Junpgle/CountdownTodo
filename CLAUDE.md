# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

CountDownTodo (Uni-Sync 4.x) — a cross-platform Flutter productivity suite: todos, countdowns, pomodoro timer, course schedules, screen time tracking, team collaboration, and a Windows desktop "dynamic island" floating window. Targets Android, Windows, and Web.

Backend is a Cloudflare Workers API with D1 database. There's also a separate C++ desktop overlay component in a different repo (`CountDownTodoLite`).

## Build / test / lint

```bash
flutter pub get              # Install dependencies
flutter run                  # Run on connected device (Android/Windows/Web)
flutter run -d windows       # Run on Windows desktop
flutter run -d chrome        # Run on web
flutter test                 # Run all tests
flutter analyze              # Static analysis / lint

# Backend
cd math-quiz-backend
npm install
npx wrangler deploy          # Deploy to Cloudflare
```

## Architecture

### Layer stack

```
screens/          ← UI pages (27+ files)
  └── widgets/    ← Reusable UI components
services/         ← Business logic, external adapters, sync engines
storage_service   ← Local persistence (SharedPreferences + SQLite) + delta sync
models.dart       ← All domain models in a single file (~2500+ lines)
main.dart         ← App entry, routing, theme, splash sequence, island dispatch
```

`storage_service.dart` is the central hub — screens and services depend on it for persistence, sync, and user session state. `api_service.dart` is the single HTTP client with SSL bypass and token management.

### Local database (SQLite)

`DatabaseHelper` (`lib/services/database_helper.dart`) manages a per-user SQLite database via `sqflite`. Database file pattern: `{env_prefix}uni_sync_{username}.db` (e.g., `v4_uni_sync_alice.db` for prod, `test_v5_uni_sync_alice.db` for test). The database has gone through 19 schema versions with incremental `onUpgrade` migrations.

### Delta Sync engine (LWW)

The sync engine uses Last-Write-Wins conflict resolution:
- Every syncable model has `version` (int), `updatedAt` (UTC ms), and a UUID `id`
- Models must call `markAsChanged()` on mutation, which increments `version` and updates `updatedAt`
- `StorageService.syncData()` uploads only dirty data (`updatedAt > lastSyncTime`), then pulls server changes
- Sync covers: todos, countdowns, todo_groups, time_logs, pomodoro tags/records, screen time
- The backend (`math-quiz-backend/src/index.js`) implements the same LWW logic server-side with HMAC token auth

### Time convention

All timestamps are UTC milliseconds (`int`). Display formatting uses `intl` / `DateFormat` with local timezone conversion. **Never** store or transmit local datetime strings.

### Environment detection

`EnvironmentService` auto-detects test vs production by checking if the package name ends with `.debug`. Test environments use a different database prefix (`test_v5_`), different server URL (Aliyun 8084), and database isolation.

### Server switching

`ApiService` supports two backends: Cloudflare (`mathquiz.junpgle.me`) and Aliyun (`101.200.13.100:8082` test / 8084 prod). `EnvironmentService.lockBaseUrl()` locks the server for test builds; production users can choose via settings.

### Windows island (dynamic island)

The island runs in a **separate Flutter engine** via `desktop_multi_window`. Communication between main and island processes uses file-based IPC (`island_action.json` on disk) because MethodChannel is unreliable across engines. The entry point is `island_entry.islandMain()` — `main.dart` detects `multi_window` CLI args and dispatches to it. `IslandStateStack` manages UI states as a stack with protected states that external payloads can't override. `IslandManager` (singleton) handles window lifecycle.

Key files: `lib/windows_island/island_entry.dart`, `island_manager.dart`, `island_ui.dart`, `island_state_stack.dart`, `island_channel.dart`

### Course import

Multi-school parser system in `lib/course_import/parsers/`. Each parser handles a specific school's format (HFUT JSON API, XMU/ZFSoft HTML, Xidian ICS). `CourseService` is the unified entry point — parsers are format-specific only, storage is handled by CourseService.

### LLM integration

`LLMService` calls Zhipu AI (GLM models) to parse natural language into structured todo JSON. Supports both text and image input. Prompt engineering injects `{now}` baseline time for relative date resolution. Used by `todo_parser_service.dart` and `external_share_handler.dart`.

### Pomodoro system

`PomodoroService` manages the full pomodoro lifecycle: tags, records, run state, settings. Uses Streams (`onRunStateChanged`) for reactive UI updates. Run state is persisted to survive process kills. Tags use tombstone deletion (`isDeleted` flag) to prevent sync resurrection. Cross-device sync via `PomodoroSyncService` (WebSocket).

### Key data models (in `models.dart`)

- `TodoItem` — full todo with recurrence, groups, folders, team metadata
- `CountdownItem` — countdown events
- `TimeLogItem` — time tracking entries
- `PomodoroRecord` / `PomodoroTag` / `PomodoroRunState` — pomodoro domain (defined in `pomodoro_service.dart`)
- `CourseItem` — unified course schedule entry
- `TimelineEvent` — personal timeline / footprint events

### Platform channels

- `com.math_quiz_app/screen_time` — Android UsageStats access for screen time
- Windows screen time via `TaiService` (TAI API for process activity)
- `MethodChannel` for native Android widgets, notifications, permissions
