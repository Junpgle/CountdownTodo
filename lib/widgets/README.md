# Widgets

Last reviewed: 2026-08-25.

The directory contains reusable state views, Material 3 controls, global search,
todo/group/section cards, recurrence progress/calendar helpers, countdown and
course widgets, Pomodoro UI, plan-block UI, calendar views, conflict/version
history sheets, macOS menu-bar UI and Turnstile platform variants.

Notable shared building blocks include `app_state_views.dart`,
`todo_recurrence_progress.dart`, `todo_section_widget.dart`,
`todo_group_widget.dart`, `global_search_overlay.dart`, and the platform-specific
Turnstile/menu widgets.

Liquid Glass integration is centralized here: `optional_liquid_glass_surface.dart`
exposes `OptionalLiquidGlassSurface/Card/Panel` plus quality/tint helpers, so
callers always provide a Material `fallback`. The home bottom navigation content
(`home_bottom_navigation_content.dart`) and quick action buttons
(`home_quick_action_button.dart`) own only layout/selection; the outer glass or
fallback material is chosen by the home screen.

Widgets should consume services/models rather than duplicate persistence rules,
derive colors from `Theme.of(context).colorScheme`, expose callbacks for
mutation, and dispose animations/controllers. Keep recurrence-series visibility,
todo date-only/deadline semantics, and Liquid Glass fallback behavior covered by
widget tests. Habit-specific cards live in `lib/features/habits/widgets/`.
