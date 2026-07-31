# Windows island redesign — implementation reconciliation

Originally a redesign proposal; reconciled with code on 2026-07-20.

## Landed

- Compact idle/focusing modes, stacked and split layouts.
- Strong Pomodoro reminder and finish/abandon/final confirmation states.
- Reminder popup/split/capsule variants.
- Dual-island copied-link presentation.
- Quick controls, music player, volume and brightness controls.
- Card carousel and protected-state handling.

## Not landed as originally proposed

- Hover behavior was not removed; `hoverWide` remains a supported current state.
- Polling was not replaced with a push transport. File IPC remains in use, with
  the action poll currently running at 500 ms.
- Some dimensions are state-specific rather than governed by one universal
  capsule-size table.

## Ongoing work

- Keep main-window and island payload schemas backward compatible.
- Reduce duplicated transition/sizing logic and add state-machine tests.
- Verify multiple monitors, DPI scaling, taskbar position, fast state races and
  cleanup after abnormal exits.
- Preserve the hard Windows-only boundary.

For current extension steps and state inventory, use
`../lib/windows_island/EXTENDING.md` and `../lib/windows_island/README.md`.
