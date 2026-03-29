# Island Module - Extension Guide

This document provides guidelines for extending the Windows Island module with new features, states, and behaviors.

## Architecture Overview

```
lib/windows_island/
├── island_config.dart      # Centralized constants and configuration
├── island_channel.dart     # IPC communication with main app
├── island_debug.dart       # Debug/testing page
├── island_entry.dart       # Window entry point (islandMain)
├── island_manager.dart     # Window lifecycle management
├── island_payload.dart     # Data transfer objects
├── island_reminder.dart    # Reminder service
├── island_state_handler.dart # Extensible state management
├── island_ui.dart          # UI components and state machine
└── island_win32.dart       # Win32 API utilities
```

## Key Concepts

### 1. States

The island operates through a finite state machine. Each state defines:
- Window size
- UI content
- Transition rules

**Built-in states:**
| State | Description | Size |
|-------|-------------|------|
| `idle` | Default clock display | 120x34 |
| `focusing` | Focus timer active | 100x46 |
| `hoverWide` | Expanded on hover | 380x46 |
| `splitAlert` | Split notification | 300x36 |
| `stackedCard` | Detailed view | 280x140 |
| `reminderPopup` | Reminder notification | 320x150/180 |
| `reminderSplit` | Dual capsule reminder | 480x46 or 320x300+ |
| `reminderCapsule` | Single reminder capsule | 160x46 |
| `copiedLink` | Copied URL notification | 340x46 |

### 2. Payload

Data is passed to the island via `Map<String, dynamic>` payloads:

```dart
{
  'state': 'focusing',           // Target state
  'focusData': {
    'title': 'Task Name',
    'endMs': 1234567890,
    'timeLabel': '25:00',
    'isCountdown': true,
    'tags': ['study', 'math'],
    'syncMode': 'local',
  },
  'reminderPopupData': {
    'type': 'todo',              // or 'course'
    'title': 'Meeting',
    'subtitle': 'Room 301',
    'startTime': '14:00',
    'endTime': '15:00',
    'minutesUntil': 15,
    'isEnding': false,
    'itemId': 'unique-id',
  },
  'copiedLinkData': {
    'url': 'https://example.com',
    'displayUrl': 'example.com',
  },
}
```

### 3. Actions

User interactions trigger actions sent back to the main app:

| Action | Description | Data |
|--------|-------------|------|
| `finish` | Focus completed | remainingSecs |
| `abandon` | Focus abandoned | 0 |
| `reminder_ok` | Reminder acknowledged | - |
| `remind_later` | Snooze requested | - |
| `open_link` | Open URL | url |
| `check_reminder` | Force check reminders | - |

## Extension Points

### Adding a Custom State

1. **Define the state** in `island_config.dart`:

```dart
enum IslandStateConfig {
  // ... existing states
  myCustomState,
}
```

2. **Add size configuration** in `IslandConfig.sizeForState()`:

```dart
case IslandStateConfig.myCustomState:
  return const Size(200, 100);
```

3. **Create a state handler** (optional):

```dart
class MyCustomHandler extends IslandStateHandler {
  @override
  String get stateId => 'my_custom_state';

  @override
  IslandStateConfig get configState => IslandStateConfig.myCustomState;

  @override
  Widget build(BuildContext context, Map<String, dynamic>? payload, IslandStateContext stateContext) {
    return Container(
      color: Colors.blue,
      child: Text('Custom State'),
    );
  }
}
```

4. **Register the handler**:

```dart
IslandStateRegistry.register(MyCustomHandler());
```

### Modifying Timing Constants

All timing values are centralized in `island_config.dart`:

```dart
class IslandConfig {
  // Hover behavior
  static const Duration hoverEnterDelay = Duration(milliseconds: 100);
  static const Duration hoverExitDelay = Duration(milliseconds: 120);
  static const Duration hoverMinStay = Duration(milliseconds: 400);

  // Transitions
  static const Duration transitionDuration = Duration(milliseconds: 200);
  static const int transitionDebounceMs = 200;

  // Reminders
  static const Duration reminderCheckInterval = Duration(seconds: 10);
  static const Duration copiedLinkDismissDuration = Duration(seconds: 10);
}
```

### Customizing Colors

```dart
class IslandConfig {
  static const Color successColor = Color(0xFF4CAF50);
  static const Color dangerColor = Color(0xFFD32F2F);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color focusColor = Color(0xFF6366F1);
  static const Color bgColor = Color(0xFF1C1C1E);
}
```

### Adding Reminder Types

In `island_reminder.dart`, extend the reminder checking logic:

```dart
static Future<List<Map<String, dynamic>>> _checkCustomReminders(DateTime now) async {
  final reminders = <Map<String, dynamic>>[];
  
  // Your custom reminder source
  final items = await getCustomReminders();
  for (final item in items) {
    final diff = item.startTime.difference(now).inMinutes;
    if (diff >= 0 && diff <= 20) {
      reminders.add({
        'type': 'custom',
        'title': item.title,
        'subtitle': item.description,
        'minutesUntil': diff,
        'isEnding': false,
        'itemId': item.id,
      });
    }
  }
  
  return reminders;
}
```

Then add it to `checkUpcomingReminder()`:

```dart
final customReminders = await _checkCustomReminders(now);
allReminders.addAll(customReminders);
```

### Win32 Utilities

Use `island_win32.dart` for window manipulation:

```dart
import 'island_win32.dart';

// Get window handle
final hwnd = getSmallestFlutterWindow();

// Resize window
resizeCurrentWindow(200, 100);

// Move window
moveCurrentWindow(100, 200);

// Get current position
final rect = getWindowRect();

// Start dragging
startWindowDragging();

// Get DPI scale
final scale = getIslandScaleFactor(hwnd);
```

## IPC Communication

### Sending Data to Island

From the main app, use `IslandManager`:

```dart
final manager = IslandManager();
await manager.createIsland('island-1');

// Send payload
await manager.sendStructuredPayload('island-1', {
  'state': 'focusing',
  'focusData': {
    'title': 'Study Session',
    'endMs': DateTime.now().add(Duration(minutes: 25)).millisecondsSinceEpoch,
  },
});
```

### Receiving Actions

Actions are written to `island_action.json` and picked up by `IslandChannel`:

```dart
IslandChannel.actionStream.listen((event) {
  final action = event['action'];
  final windowId = event['windowId'];
  
  switch (action) {
    case 'finish':
      // Handle focus completion
      break;
    case 'reminder_ok':
      // Handle reminder acknowledgment
      break;
  }
});
```

## Best Practices

1. **Use constants**: Always use `IslandConfig` for timing, colors, and sizes
2. **State protection**: Check state before transitions to prevent loops
3. **Debounce**: Use appropriate debouncing for user interactions
4. **Memory cleanup**: Cancel timers in `dispose()`
5. **Error handling**: Wrap async operations in try-catch
6. **Testing**: Use `IslandDebugPage` for testing UI states

## Debug Mode

Use the debug page to test states without the full IPC:

```dart
import 'package:math_quiz_app/windows_island/island_debug.dart';

// In your app
Navigator.push(context, MaterialPageRoute(
  builder: (_) => IslandDebugPage(),
));
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Window not transparent | Check Win32 initialization in `initFfiTransparent()` |
| State not updating | Verify payload format matches expected structure |
| Timer leaks | Ensure `dispose()` cancels all timers |
| IPC not working | Check `island_action.json` permissions and path |

## File Reference

| File | Purpose | Lines |
|------|---------|-------|
| `island_config.dart` | Constants and configuration | ~170 |
| `island_win32.dart` | Win32 API wrapper | ~280 |
| `island_reminder.dart` | Reminder service | ~200 |
| `island_state_handler.dart` | State registry | ~150 |
| `island_payload.dart` | Data models | ~130 |
| `island_entry.dart` | Entry point | ~350 |
| `island_ui.dart` | UI components | ~1000 |
| `island_manager.dart` | Window manager | ~330 |
| `island_channel.dart` | IPC channel | ~260 |
