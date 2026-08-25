# Extending the Windows island

Last reviewed: 2026-08-25.

1. Add the new value to `IslandState` and decide whether it belongs in the
   protected-state set.
2. Add target dimensions in the relevant sizing path (`IslandConfig` or the
   widget's state-specific target-size logic).
3. Add the visual branch and transitions in the island widget/state machine.
4. Define payload fields and serialization in `IslandChannel`/data provider;
   keep old readers tolerant of missing fields.
5. Add the main-window trigger and an explicit return/timeout path.
6. Verify Windows-only initialization, idle/focusing coexistence, hover,
   protected states, multiple monitors/scaling and file-IPC cleanup.

Current state families already cover focus, reminders, confirmations,
copied-link dual islands, quick controls, music, volume, brightness and card
carousel. Reuse an existing family when only payload/content changes; add a new
state only when sizing, protection or transitions differ.

Never import this package from an unguarded Android/web code path. Prefer theme
or configured colors rather than hard-coded application accents.
