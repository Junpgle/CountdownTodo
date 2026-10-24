# Data export and restore

This document records the client JSON backup format and the current restore
workflow. Selecting a scope decides which existing domain importers run; it
does not introduce one uniform merge or replacement rule across all domains.

## Export

The version 2 JSON envelope records the export timestamp, source account/device
metadata and selected data sections. Export can include todos and schedules,
courses, focus records, habits, the 30-day challenge, personal finance, and
preferences. The export page lets the user choose sections and options for
removing team bindings, image paths, conflict metadata, or device IDs.

Personal finance remains a local personal domain. Its section is a related
bundle containing categories, payment methods, transactions, budgets, recurring
rules, templates, loans, and installments.

## Restore selection

The import preview is read-only. It displays export metadata and groups
supported sections into these selectable scopes:

- **Tasks, plans and focus** keeps todo groups, todos, countdowns, plan blocks,
  fixed schedules, time logs, Pomodoro tags, and Pomodoro records together so
  their UUID references can be remapped as one package.
- **Courses** restores course data independently.
- **Habits and sleep coaching** restores the complete habits bundle.
- **Finance** restores its complete related bundle.
- **30-day challenge** restores its state and task list together.
- **Preferences** is separate because it can change the current account's app
  settings.

All supported scopes present in the file are selected initially, preserving the
existing full-import default. The user can select all scopes or clear them. An
empty selection cannot be imported. Unsupported section keys are identified in
the preview and are not passed to the current import pipeline.

The preview shows archive entry counts, soft-deleted counts, and team-bound
counts where available. The finance total includes categories and payment
methods as well as ledger and plan rows. Counts describe entries in the file;
they are not a row-by-row prediction of local conflicts.

## Restore and identity behavior

Each selected scope is filtered into the existing domain importers, which retain
their own update, skip, and replacement behavior. The scope selector does not
change those rules and the preview does not predict row-by-row conflicts. In
particular, restoring the 30-day challenge applies the challenge state and flags
from the backup as a bundle. Settings import writes the supported keys present
in the backup (excluding sensitive identity credentials); keys absent from the
backup are not visited by that importer. Review the selected scope carefully
when the current device already contains data you want to keep.

For the same account, UUIDs are retained where the existing importer supports
them. Cross-account import uses the existing UUID remapping strategy. Team-bound
records continue to follow the selected “skip” or “convert to personal”
strategy. Soft-deleted entries remain part of selected scopes and follow their
domain importer's existing behavior.

The existing import rollback snapshot and reminder refresh paths remain in
place. Restore selection only filters the JSON sections before the domain
importers run; it does not change the database schema or sync protocol.
