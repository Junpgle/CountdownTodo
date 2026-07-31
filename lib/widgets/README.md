# Widgets

Last reviewed: 2026-07-20.

The directory contains reusable state views, Material 3 controls, global search,
todo/group/section cards, recurrence progress/calendar helpers, countdown and
course widgets, Pomodoro UI, plan-block UI, calendar views, conflict/version
history sheets, macOS menu-bar UI and Turnstile platform variants.

Notable shared building blocks include `app_state_views.dart`,
`todo_recurrence_progress.dart`, `todo_section_widget.dart`,
`todo_group_widget.dart`, `global_search_overlay.dart`, and the platform-specific
Turnstile/menu widgets.

Widgets should consume services/models rather than duplicate persistence rules,
derive colors from `Theme.of(context).colorScheme`, expose callbacks for
mutation, and dispose animations/controllers. Keep recurrence-series visibility
and todo date-only/deadline semantics covered by widget tests.
