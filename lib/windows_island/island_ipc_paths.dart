import 'dart:convert';
import 'dart:io';

/// File paths shared by the main Windows engine and the island child engine.
///
/// This intentionally avoids plugin-backed directories. Secondary
/// desktop_multi_window engines can be created before every plugin is fully
/// usable in release builds, but dart:io environment paths are available in
/// both engines.
Future<Directory> getIslandIpcDirectory() async {
  final env = Platform.environment;
  final basePath = env['APPDATA'] ??
      env['LOCALAPPDATA'] ??
      Directory.systemTemp.absolute.path;
  final dir = Directory('$basePath${Platform.pathSeparator}CountDownTodo');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> getIslandIpcFile(String fileName) async {
  final dir = await getIslandIpcDirectory();
  return File('${dir.path}${Platform.pathSeparator}$fileName');
}

Future<File> getIslandBoundsFile(String islandId) {
  return getIslandIpcFile('island_bounds_$islandId.json');
}

Future<Map<String, dynamic>?> loadIslandBounds(String islandId) async {
  try {
    final file = await getIslandBoundsFile(islandId);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map && decoded.isNotEmpty) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}

Future<void> saveIslandBounds(
  String islandId,
  Map<String, dynamic> bounds,
) async {
  try {
    final file = await getIslandBoundsFile(islandId);
    await file.writeAsString(jsonEncode(bounds));
  } catch (_) {}
}

Future<void> appendIslandIpcLog(String message) async {
  try {
    final file = await getIslandIpcFile('island_ipc.log');
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString(
      '[$timestamp] $message\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}
