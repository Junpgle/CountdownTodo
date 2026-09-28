# Widgets

Last reviewed: 2026-09-28.

The directory contains reusable state views, Material 3 controls, global search,
todo/group/section cards, recurrence progress/calendar helpers, countdown and
course widgets, Pomodoro UI, plan-block UI, calendar views, conflict/version
history sheets, macOS menu-bar UI and Turnstile platform variants.

Notable shared building blocks include `app_state_views.dart`,
`todo_recurrence_progress.dart`, `todo_section_widget.dart`,
`todo_group_widget.dart`, `global_search_overlay.dart`, and the platform-specific
Turnstile/menu widgets. Search-result cards remain as the source page while a
detail route uses `PageTransitions.pushFromRect`, so opening and returning use
the same container transform when animations are enabled and the source geometry
is available.

Liquid Glass integration follows the shared app preference. `optional_liquid_glass_surface.dart`
provides adaptive surfaces with Material fallbacks; `floating_glass_control.dart`
provides the app bar controls, switch and slider adapters; and
`app_dialogs.dart` is the shared entry point for dialogs, modal sheets, date and
time pickers, and snack messages. Dialogs and date/time pickers retain Flutter's
intrinsic sizing and receive the shared dynamic surface and control themes;
compatible modal routes use `GlassSheet`; simple text snack bars use
`GlassToast`, while custom snack layouts keep their Material behavior. Search
fields use `GlassTextField.search` while the effect is enabled.
Ordinary form fields keep Material validation and editing behavior while
receiving the shared glass-aware input decoration theme; dropdown and popup
menus use the same dynamic color and shape tokens. Dense content rows stay in
their normal content style.
The home bottom navigation content (`home_bottom_navigation_content.dart`)
and quick action buttons (`home_quick_action_button.dart`) own only
layout/selection; the outer glass or fallback material is chosen by the home
screen.

Widgets should consume services/models rather than duplicate persistence rules,
derive colors from `Theme.of(context).colorScheme`, expose callbacks for
mutation, and dispose animations/controllers. Keep recurrence-series visibility,
todo date-only/deadline semantics, and Liquid Glass fallback behavior covered by
widget tests. Habit-specific cards live in `lib/features/habits/widgets/`.
