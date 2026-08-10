import 'dart:convert';

import 'package:countdown_todo/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest exposes release date, notes and usable Android delta metadata',
      () {
    final manifest = AppManifest.fromJson(jsonDecode(jsonEncode({
      'version_code': 5701,
      'version_name': '5.7.1',
      'update_info': {
        'title': '版本更新 5.7.1',
        'description': '【修复】更新流程',
        'full_package_url': 'https://gitee.com/example/full.apk',
        'android_delta_packages': {
          'arm64-v8a': [
            {
              'from_version': '5.7.0',
              'from_sha256': 'A' * 64,
              'to_version': '5.7.1',
              'to_sha256': 'B' * 64,
              'patch_url': 'https://gitee.com/example/update.patch',
              'patch_size': 1234,
            },
          ],
        },
      },
      'changelog_history': [
        {
          'version_name': '5.7.1',
          'date': '2026-08-10',
          'items': ['【修复】更新流程'],
        },
      ],
      'announcements': [],
      'wallpaper': {},
      'changelog_archive': {},
    })) as Map<String, dynamic>);

    final delta = manifest.updateInfo.androidDeltaPackages['arm64-v8a']!.single;
    expect(manifest.versionName, '5.7.1');
    expect(manifest.changelogHistory.single.date, '2026-08-10');
    expect(manifest.changelogHistory.single.items, ['【修复】更新流程']);
    expect(delta.fromVersion, '5.7.0');
    expect(delta.patchSize, 1234);
    expect(delta.isUsable, isTrue);
  });
}
