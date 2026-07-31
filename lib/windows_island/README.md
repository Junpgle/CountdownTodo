# Windows island

Windows-only dynamic-island/floating-window implementation. Last reviewed:
2026-07-20.

## Architecture

The main Flutter window writes state/action payloads through file IPC. The island
window polls the action file (currently every 500 ms in `IslandChannel`) and
renders an `IslandState`; payload/config polling may use separate intervals.
Do not initialize this subsystem on Android, macOS or web.

Current states include idle, focusing, hover-wide, stacked/split cards,
finish/abandon confirmations, final completion, reminder popup/split/capsule,
copied link, quick controls, music player, volume control, brightness control
and card carousel. Confirmation, final, copied-link and reminder-popup flows are
protected from ordinary state replacement.

Classic compact sizing starts at 100×34 for idle and 90×40 for focusing;
system-control/card states calculate their own targets. `IslandConfig`, the
state machine and widget layout must be updated together when adding a state.

The implementation still supports hover expansion. It also supports strong
Pomodoro alerts, dual-island copied-link presentation, system controls, media
views and card carousel; older redesign documents that describe these as future
work are historical.
