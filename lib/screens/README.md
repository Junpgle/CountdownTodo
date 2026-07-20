# Screens

The screen layer contains both full pages and several large legacy feature
files. Last reviewed: 2026-07-20.

Major flows include home/dashboard and settings, todo creation/history/chat,
countdowns, courses, Pomodoro and tag management, plan blocks and statistics,
personal timeline/medals, collaboration/conflict inbox, calendar sync, global
search, data import/export, band sync, login/account and onboarding/update UI.

Recurrence administration includes series-aware display/progress and the
settings merge page. Todo time UI is moving toward explicit unscheduled,
date-only and deadline semantics; do not reintroduce duration-based “all day”
heuristics in screens.

When adding a screen, prefer existing services and reusable widgets. Keep
platform calls behind adapters, use theme colors, dispose controllers, and add
widget tests for visible state transitions. The largest dashboard, course, chat
and todo-section files remain priority refactor targets.
