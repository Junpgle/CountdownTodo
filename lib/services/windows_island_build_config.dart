/// Compile-time switch set via
/// `--dart-define=countdown.disable_windows_island=true` on non-Windows builds
/// so Dart AOT tree-shaking eliminates `lib/windows_island/` and Win32 FFI code
/// from Android/macOS/iOS binaries.
const bool kDisableWindowsIsland = bool.fromEnvironment(
  'countdown.disable_windows_island',
);

const bool kWindowsIslandEnabledInBuild = !kDisableWindowsIsland;
