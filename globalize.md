# Shared-component and refactor inventory

Last reviewed: 2026-08-25. This replaces the old line-number-based checklist;
line numbers and file sizes change too often to be useful as design contracts.

## Extracted and reusable

- Dialog/snackbar helpers: `lib/utils/app_dialogs.dart`.
- Date/time formatting: `lib/utils/time_utils.dart`.
- Theme-aware color helpers: `lib/utils/app_color_utils.dart` and
  `lib/utils/theme_color_tokens.dart`; theme extensions in `lib/theme/`.
- Loading/empty/error views: `lib/widgets/app_state_views.dart`.
- Glass-or-fallback surfaces: `lib/widgets/optional_liquid_glass_surface.dart`
  with configuration from `lib/services/liquid_glass_effect_service.dart`.
- Storage modules: `lib/services/storage/app_settings_storage.dart`,
  `countdown_storage.dart`, `pomodoro_storage.dart`,
  `user_session_storage.dart`, and `storage_conflict_cleanup.dart`.
- Platform-specific implementations use conditional exports for notifications,
  updates, widgets, calendar, window services, Turnstile and related features.

## Partially centralized

- `StorageService` still owns sync orchestration and a substantial amount of
  todo/recurrence/conflict logic. New extractions should keep its public facade
  compatible while moving one coherent responsibility at a time.
- `navigator_utils.dart` provides the global navigator key, but navigation
  policies are still spread across screens.
- Theme utilities exist, yet some large screens still define local layout and
  presentation conventions.

## Highest-value remaining work

1. Turn the `part` splits of `home_dashboard.dart`, `todo_section_widget.dart`,
   `course_screens.dart`, and `todo_chat_screen.dart` into independently
   testable widgets/controllers instead of same-library fragments.
2. Isolate recurrence migration/repair from general storage sync and surround it
   with focused tests.
3. Extract repeated settings section/tile patterns without hiding platform
   permission behavior.
4. Centralize authenticated HTTP construction and remove insecure certificate
   overrides through a planned migration.
5. Add stable repositories/controllers between SQLite/sync services and the
   largest widgets before attempting broad state-management replacement.

Refactors should be behavior-preserving, small enough to review, and verified
with `dart format`, `flutter analyze`, targeted tests, and platform builds where
the changed boundary requires them.
