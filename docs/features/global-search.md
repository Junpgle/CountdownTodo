# Global search

Search client reconciled: 2026-10-07. Remote/server notes retained from the
2026-09-26 source audit; live deployment has not been rechecked.

Global search combines indexed app data, feature-owned local stores, static
settings/actions and a small set of remote catalogs. The query is matched in the
client; it is not sent as a server-side search term. Search queries are saved in
the local `search_history` table for search suggestions and usage statistics.
Changing scope, refreshing after remote warmup, retrying or returning from a
result does not record the same query again within the open search session.

## Search scopes

`SearchScope` maps each business result type to one scope. The common choices
are All, Todos, Schedule, Finance and Focus/time; More contains Countdowns,
Habits, Challenges, Screen time, Teams, Journal, AI chat and Settings/actions.
Schedule covers courses, fixed schedules and plan blocks. Finance includes
transactions and every existing finance subtype. Focus/time covers Pomodoro,
time logs and tags. Habits and challenges include their check-ins/tasks; cached
cloud templates belong to Challenges, while announcements and system messages
belong to Teams.

Scope selection keeps the query and immediately replaces the previous results.
Clearing keeps the scope; reopening resets to All. An empty query in a restricted
scope shows an input hint without loading all records. A restricted search with
no matches offers Search all while keeping the query. Returning from details
keeps both query and scope. A request sequence invalidates stale completions,
including the debounce window and A → B → A scope changes.

`SearchService.search` defaults to All for existing callers. Scope selection is
applied before calling local source adapters, including the independent branches
of combined adapters. A final type filter also applies to local and cached
remote results. Remote prewarming and the five-minute account cache retain their
existing behavior; scope selection does not promise fewer network requests.
`onSourceQueried` observes logical source adapters for diagnostics, not individual
SQL statements. `recordHistory: false` supports non-user-initiated refreshes.

## Searchable sources

### Core app data

`SearchService` searches todos and todo groups through the database search
adapter, plus courses, countdowns, Pomodoro records and tags, time logs,
screen-time apps, habit goals, challenge summaries, settings and quick actions.
SQLite uses FTS5 when available, falls back to FTS4, and then uses `LIKE` when
full-text search is unavailable. The fallback also supports Chinese substring
matching.

### Feature-owned local data

`GlobalSearchExtraService` adapts records that live outside the original search
tables:

- Finance transactions, categories, payment methods, budgets, recurring rules,
  entry templates, loans and loan installments.
- Private journal entries, fixed schedules and plan blocks.
- Habit check-ins and thirty-day challenge tasks, including their feeling notes.
- AI chat session titles and individual message content.
- Locally stored team names.

### Remote catalogs and team records

When the search overlay opens, it warms a per-account cache with the cloud
thirty-day challenge catalog, teams, team announcements and team system
messages. The cache is reused for five minutes. Remote results depend on network
availability and the records returned for the signed-in account.

Team system messages are requested in pages of 100. The Alibaba `debug/` route
accepts `limit` and `offset` and caps the page size at 100. The protected
`math_quiz_backend/` route still returns a fixed latest 50 messages, so searches
against that server can only include those 50 until the paging change is
promoted and deployed. This describes repository code, not live deployment
state.

## Opening a result

`SearchNavigationHandler` uses an existing detail or editor destination where
one is available, including todo editing, course pages, time-log/Pomodoro
details, journal details, fixed-schedule editing and finance transaction, loan
or budget pages. Other records open `SearchRecordDetailScreen`, which displays
the captured result fields so records without a deep-link API remain readable
from search.

Result cards keep their source geometry in `GlobalSearchOverlay`. Navigation
uses `PageTransitions.pushFromRect` and its container-transform route, which
animates both opening and the reverse transition when the detail page closes.
The route falls back to a normal page push if animations are disabled or the
source geometry is unavailable.

## Matching and maintenance notes

- Date queries match each source's record date; monthly budgets match any date
  in their configured month.
- The local database search path does not impose a fixed SQL result limit on
  matching rows. Result groups show three matches initially; expand a group to
  reveal its remaining matches. Keep feature-owned stores and their fields
  listed above in sync with `GlobalSearchExtraService.search` when adding
  searchable record types.
- A record deleted after the result list was built can no longer open its native
  detail page; the handler reports that the record is gone and asks the user to
  search again.
- Source of truth: `lib/services/search_service.dart`,
  `lib/services/global_search_extra_service.dart`,
  `lib/widgets/global_search_overlay.dart`,
  `lib/models/search_scope.dart`,
  `lib/screens/search_record_detail_screen.dart` and
  `lib/utils/page_transitions.dart`.

## Verification

The 2026-10-07 change has isolated storage/adapter tests in
`test/services/search_scope_test.dart` and visible-flow tests in
`test/widgets/global_search_overlay_test.dart`, plus the existing search and
page-transition regressions. The acceptance report is
[global search scopes](../reports/2026-10-07-global-search-scopes-acceptance.md).
The browser preview uses the actual search widget with synthetic adapters; it
is not a native-device or full-app data-path verification.
