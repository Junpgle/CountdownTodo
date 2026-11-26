# Repository Guidelines

Last reviewed against the working tree: 2026-11-26.

## Project layout

- Flutter client: repository root; Dart source in `lib/`, tests in `test/`.
- Self-contained feature modules: `lib/features/` (habits, private journal,
  thirty-day challenge, finance); shared theme extensions in `lib/theme/`.
- Platform hosts: `android/`, `ios/`, `macos/`, `windows/`, and `web/`.
- React web companion: `webpage/web/`.
- Xiaomi band companion: `CountDownTodo-band/`.
- Legacy-compatible Cloudflare Worker: `math-quiz-backend/`.
- Alibaba Cloud server: separate checkout `CDT-server`; `math_quiz_backend/`
  is production code and `debug/` is the test/debug environment.
- Assets: `assets/`, `splash/`, and `wallpaper/`.

## Backend and network rules

- New server features target the Alibaba Cloud production server
  (`CDT-server/math_quiz_backend/`) directly unless testing specifically in
  `CDT-server/debug/`. Keep shared changes in sync when needed.
- Preserve the Cloudflare Worker compatibility path unless a task explicitly
  removes or migrates it.
- Native Windows and Android clients use the Alibaba Cloud HTTP/WebSocket
  endpoints directly. Flutter web uses `https://api-cdt.junpgle.me/` through
  Cloudflare Zero Trust.
- Pomodoro device awareness and collaborative live sync depend on WebSocket;
  preserve platform-specific URL selection and WebSocket behavior.

## Platform boundaries

- Windows island/floating-window code is Windows-only. Android, macOS, iOS,
  Linux, and Web must not import, initialize, or execute it; keep `lib/windows_island/`
  and `package:win32` isolated behind the 7 `*_io.dart` conditional export targets
  and pass `--dart-define=countdown.disable_windows_island=true` on non-Windows builds.
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
npm test
```

MCP server & Alibaba Cloud backend unit tests:

```bash
cd mcp-server && npm test
cd ../CDT-server/math_quiz_backend && npm test
```

## Code and UI conventions

- Follow `package:flutter_lints/flutter.yaml`; Dart filenames use
  `snake_case.dart`, types use `PascalCase`, and members use `lowerCamelCase`.
- Add code under an existing feature folder when possible.
- The app uses Material 3 dynamic colors. Custom UI must derive colors from
  `Theme.of(context).colorScheme`, not hard-code standard colors.
- Keep generated files, build output, credentials, certificates, keystores,
  and private deployment configuration out of commits.

## Reuse and modularity

- **Prefer existing shared primitives over reinventing helpers or UI**: before
  creating a new utility, formatter, dialog, bottom sheet chrome, or state view,
  inspect `lib/utils/`, `lib/widgets/`, and the target feature's `widgets/` or
  `services/` folders and reuse or extend what already exists:
  - **Dialogs, bottom sheets, pickers, and SnackBars**: use `showAppDialog`,
    `showAppGeneralDialog`, `showAppModalBottomSheet`, `showAppDatePicker`,
    `showAppDateRangePicker`, `showAppTimePicker`, `AppDialogs.confirm` /
    `confirmSheet` / `showLoading`, and `AppSnackBars.show` / `showSnackBar` /
    `hideCurrent` / `clear` in `lib/utils/app_dialogs.dart`. Avoid raw
    `showDialog`, `showModalBottomSheet`, `showDatePicker`, `showTimePicker`,
    `showDateRangePicker`, and fire-and-forget
    `ScaffoldMessenger.of(context).showSnackBar` (raw `ScaffoldMessenger` is
    only justified when the caller must retain the returned
    `ScaffoldFeatureController`, and raw `showAppDialog<bool>` only when
    distinguishing `null` vs `false` or attaching custom button keys/widgets).
  - **Date/time formatting and calendar math**: use `AppTimeFormats` (`format`,
    `dateFormatter`, `date`, `clock`, `fullDateTime`, `compactDateTime`,
    `monthDaySlash`, `fileTimestamp`, `hourMinute`, `isSameDay`,
    `weekdayShortLabelsZh`, `weekdayLabelsZh`, `weekdayShortZh`, `weekdayZh`,
    `weekdayLabel`) and duration helpers in `lib/utils/time_utils.dart`, plus
    `CalendarDateMath` in `lib/utils/calendar_date_math.dart`. Do not call raw
    `DateFormat(...)` outside `lib/utils/time_utils.dart` or hand-roll local
    `DateFormat` caches, Chinese weekday arrays, same-day comparisons, or
    `padLeft(2, '0')` date/clock strings.
  - **Parsing, color, and platform utilities**: reuse `JsonValueParser`
    (`lib/utils/json_value_parser.dart`), `AppColorUtils`
    (`lib/utils/app_color_utils.dart`), `AppPlatform`
    (`lib/utils/app_platform.dart`), and `ThemeColorTokens`
    (`lib/utils/theme_color_tokens.dart`).
  - **Shared UI shells and state views**: reuse `AppSheetDragHandle` /
    `AppSheetHeader` (`lib/widgets/app_sheet_widgets.dart`), `AppEmptyState` /
    `AppLoadingView` / `AppLoadingIndicator` (`lib/widgets/app_state_views.dart`),
    `AppSettingsSection` / `AppSettingsCard` / `AppSettingsDivider`
    (`lib/widgets/app_settings_widgets.dart`), `AppDetailHeader` /
    `AppDetailSection` (`lib/widgets/app_detail_widgets.dart`),
    `SettingsToggleCard` (`lib/widgets/settings_toggle_card.dart`),
    `SplashScreenShell` (`lib/widgets/splash_screen_shell.dart`), and existing
    feature-level shared widgets or mixins (such as `FinanceRevisionRefreshMixin`).
- **Split oversized files (`> 2000` lines)**:
  - Keep source files focused; do not let a single source file grow beyond
    **2,000 lines**.
  - If a file exceeds 2,000 lines (or a change would push it past 2,000 lines),
    split it along cohesive responsibilities (such as layout, actions,
    dialogs/sheets, and data/helpers) into `part` / `part of` files under a
    matching subfolder (keeping imports on the parent library file) or into
    standalone widgets/services, while preserving platform boundaries
    (`lib/windows_island/`, `*_io.dart`).

## Flutter rendering and runtime performance

- **Use granular `MediaQuery` subscriptions**: read only the specific metric
  needed (`MediaQuery.sizeOf`, `paddingOf`, `viewPaddingOf`, `viewInsetsOf`,
  `orientationOf`, `textScalerOf`, `platformBrightnessOf`) instead of
  `MediaQuery.of(context)` so keyboard animations and unrelated viewport metric
  changes do not rebuild the whole subtree.
- **Hoist allocations out of `build()` and hot loops**:
  - Hoist all literal `RegExp(...)` instances to top-level private `final` or
    `static final` constants rather than constructing them inside `build()`,
    `itemBuilder`, parsers, or string helpers.
  - Cache `NumberFormat` instances and use `AppTimeFormats`
    (`lib/utils/time_utils.dart`) instead of creating `DateFormat` /
    `NumberFormat` during rendering.
  - Never pass a freshly invoked async call directly to `FutureBuilder(future: ...)`
    inside `build()`; store and refresh the `Future` in `State` (`initState` /
    `didUpdateWidget`) so parent rebuilds do not restart I/O or flicker loading
    states.
- **Prefer Slivers over `shrinkWrap: true` on scrollable pages**:
  - Do not nest `ListView` / `GridView` with `shrinkWrap: true` and
    `NeverScrollableScrollPhysics()` inside `SingleChildScrollView` or outer
    scroll views on feeds, dashboards, or detail screens — it defeats lazy
    viewport building and forces eager O(N) layout of off-screen children.
  - Compose heterogeneous scrollable pages with `CustomScrollView` +
    `SliverToBoxAdapter` + `SliverList.builder` / `SliverList.separated` /
    `SliverGrid.builder`, providing `findChildIndexCallback` when items have
    stable keys.
  - `shrinkWrap: true` is only justified for short, bounded lists inside
    tight-sizing dialogs or bottom sheets (`ConstrainedBox(maxHeight: ...)` /
    `mainAxisSize: MainAxisSize.min`) that must collapse to a few rows.
- **Avoid unnecessary GPU `saveLayer` (`Opacity`) and isolate repaint subtrees**:
  - Prefer direct color alpha (`color.withValues(alpha: ...)`) over `Opacity`
    when fading single `Icon`, `Text`, `DecoratedBox`, or `LinearGradient`
    widgets.
  - For animated composite subtrees, prefer `FadeTransition` when an
    `Animation<double>` already exists, short-circuit boundary values
    (`>= 0.999` returns `child!`; `<= 0.001` returns `const SizedBox.shrink()`,
    or `Visibility` with `maintainSize`/`maintainAnimation`/`maintainState`
    when layout space must remain reserved), and wrap the animated `child` in
    `RepaintBoundary` so its rasterized layer is reused across frames.
  - Wrap every `CustomPaint` (especially background grids, charts, and legends
    in `Stack`s or scrollable views) and complex list/grid cards in
    `RepaintBoundary`.
  - Keep intentional `Opacity(opacity: 0.01)` wrappers used for offscreen
    `RepaintBoundary` poster capture and `Opacity` used to dim heterogeneous or
    third-party composite controls (such as disabled `GlassSwitch`).

## Testing and delivery

- Put Flutter tests in `test/` as `*_test.dart`, mirroring `lib/` where useful.
- Prioritize focused tests for parsing, storage, sync, networking, recurrence,
  notifications, and services; use widget tests for visible flows.
- State which commands ran and which were skipped.
- Release commit summaries use the current version prefix, for example
  `v7.22.6 【修复】...`, `v7.22.6 【优化】...`, or `v7.22.6 【新增】...`.
- PRs should summarize changes, tests, linked issues, UI evidence, and any
  version, asset, permission, backend, or platform risk.
