# Windows host and packaging

The `windows/` directory contains Flutter's C++ desktop runner plus project
packaging. Last reviewed: 2026-07-20.

- `runner/`: window lifecycle, resources, manifest and generated plugin host.
- `flutter/`: generated plugin registration and CMake integration.
- `打包.iss`: Inno Setup installer definition.
- `lib/windows_island/`: Dart island UI/state/IPC; it is intentionally outside
  this native host directory.

Run the client with:

```bash
flutter run -d windows
flutter build windows
```

Do not hand-edit generated files under `windows/flutter/`. Keep Windows-only
window and island initialization behind explicit platform guards so Android,
macOS and web do not load it. Installer changes should be checked against the
Flutter version in `pubspec.yaml`, icons/resources and the produced build path.
