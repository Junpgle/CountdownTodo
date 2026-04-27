import 'dart:io';

void main(List<String> args) {
  final pubspecFile = File('pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();

  // 匹配 version: x.y.z 或 version: x.y.z+build
  final versionRegex =
      RegExp(r'^version:\s*(\d+\.\d+\.\d+)(\+(\d+))?\s*$', multiLine: true);
  final match = versionRegex.firstMatch(content);

  if (match == null) {
    stderr.writeln('Error: Could not find version in pubspec.yaml');
    exit(1);
  }

  final currentVersion = match.group(1)!;
  final parts = currentVersion.split('.');

  int major = int.parse(parts[0]);
  int minor = int.parse(parts[1]);
  int patch = int.parse(parts[2]);

  // 默认递增 patch 版本
  // 可以通过参数指定: patch (默认), minor, major
  String incrementType = 'patch';
  if (args.isNotEmpty) {
    incrementType = args[0];
  }

  switch (incrementType) {
    case 'major':
      major++;
      minor = 0;
      patch = 0;
      break;
    case 'minor':
      minor++;
      patch = 0;
      break;
    case 'patch':
    default:
      patch++;
      break;
  }

  final newVersion = '$major.$minor.$patch';
  final newVersionLine = 'version: $newVersion';

  final newContent = content.replaceFirst(versionRegex, newVersionLine);

  pubspecFile.writeAsStringSync(newContent);

  stdout.writeln('Version updated: $currentVersion -> $newVersion');
}
