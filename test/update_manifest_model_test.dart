import 'dart:convert';

import 'package:countdown_todo/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manifest exposes release date, notes and usable Android delta metadata',
    () {
      final manifest = AppManifest.fromJson(
        jsonDecode(
          jsonEncode({
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
          }),
        ) as Map<String, dynamic>,
      );

      final delta =
          manifest.updateInfo.androidDeltaPackages['arm64-v8a']!.single;
      expect(manifest.versionName, '5.7.1');
      expect(manifest.changelogHistory.single.date, '2026-08-10');
      expect(manifest.changelogHistory.single.items, ['【修复】更新流程']);
      expect(delta.fromVersion, '5.7.0');
      expect(delta.patchSize, 1234);
      expect(delta.isUsable, isTrue);
    },
  );

  group('manifest refresh energy policy', () {
    const nowMs = 10 * Duration.millisecondsPerHour;

    test('refreshes when no successful cache exists', () {
      expect(UpdateService.isManifestRefreshDue(nowMs: nowMs), isTrue);
    });

    test('reuses a successful cache for six hours', () {
      expect(
        UpdateService.isManifestRefreshDue(
          nowMs: nowMs,
          lastSuccessfulRefreshMs: nowMs - 5 * Duration.millisecondsPerHour,
        ),
        isFalse,
      );
      expect(
        UpdateService.isManifestRefreshDue(
          nowMs: nowMs,
          lastSuccessfulRefreshMs: nowMs - 6 * Duration.millisecondsPerHour,
        ),
        isTrue,
      );
    });

    test('backs off failed or in-flight refresh attempts for 30 minutes', () {
      expect(
        UpdateService.isManifestRefreshDue(
          nowMs: nowMs,
          lastAttemptMs: nowMs - 29 * Duration.millisecondsPerMinute,
        ),
        isFalse,
      );
      expect(
        UpdateService.isManifestRefreshDue(
          nowMs: nowMs,
          lastAttemptMs: nowMs - 30 * Duration.millisecondsPerMinute,
        ),
        isTrue,
      );
    });
  });

  test('manifest parses mac_arch_packages for arm64 and x86_64', () {
    final manifest = AppManifest.fromJson(
      jsonDecode(
        jsonEncode({
          'version_code': 702408,
          'version_name': '7.24.8',
          'update_info': {
            'title': '版本更新 7.24.8',
            'description': '【新增】macOS x86_64',
            'mac_package_url': 'https://gitee.com/Junpgle/CountdownTodo/releases/download/latest/CountDownTodo-macOS-arm64.zip',
            'mac_arch_packages': {
              'arm64': 'https://gitee.com/Junpgle/CountdownTodo/releases/download/latest/CountDownTodo-macOS-arm64.zip',
              'x86_64': 'https://gitee.com/Junpgle/CountdownTodo/releases/download/latest/CountDownTodo-macOS-x86_64.zip',
            },
          },
          'changelog_history': [],
          'announcements': [],
          'wallpaper': {},
          'changelog_archive': {},
        }),
      ) as Map<String, dynamic>,
    );

    expect(
      manifest.updateInfo.macArchPackages['arm64'],
      endsWith('CountDownTodo-macOS-arm64.zip'),
    );
    expect(
      manifest.updateInfo.macArchPackages['x86_64'],
      endsWith('CountDownTodo-macOS-x86_64.zip'),
    );
  });

  test('selectAndroidArchitecture respects preferred ABI order', () {
    expect(
      UpdateService.selectAndroidArchitecture(['arm64-v8a', 'armeabi-v7a']),
      'arm64-v8a',
    );
    expect(
      UpdateService.selectAndroidArchitecture(['armeabi-v7a', 'armeabi']),
      'armeabi-v7a',
    );
    expect(
      UpdateService.selectAndroidArchitecture([
        'x86_64',
        'x86',
        'arm64-v8a',
        'armeabi-v7a',
      ]),
      'x86_64',
    );
    expect(
      UpdateService.selectAndroidArchitecture(['x86', 'armeabi-v7a']),
      'armeabi-v7a',
    );
    expect(UpdateService.selectAndroidArchitecture(const []), 'arm64-v8a');
  });

  test('manifest parses android_arch_packages and android_delta_packages for all ABIs', () {
    final manifest = AppManifest.fromJson(
      jsonDecode(
        jsonEncode({
          'version_code': 702409,
          'version_name': '7.24.9',
          'update_info': {
            'title': '版本更新 7.24.9',
            'description': '【新增】全架构自更新',
            'android_arch_packages': {
              'arm64-v8a':
                  'https://gitee.com/example/app-arm64-v8a-release.apk',
              'armeabi-v7a':
                  'https://gitee.com/example/app-armeabi-v7a-release.apk',
              'x86_64': 'https://gitee.com/example/app-x86_64-release.apk',
            },
            'android_delta_packages': {
              'arm64-v8a': [
                {
                  'from_version': '7.24.8',
                  'from_sha256': 'a' * 64,
                  'to_version': '7.24.9',
                  'to_sha256': 'b' * 64,
                  'patch_url': 'https://gitee.com/example/arm64.patch',
                  'patch_size': 100,
                },
              ],
              'armeabi-v7a': [
                {
                  'from_version': '7.24.8',
                  'from_sha256': 'c' * 64,
                  'to_version': '7.24.9',
                  'to_sha256': 'd' * 64,
                  'patch_url': 'https://gitee.com/example/armv7.patch',
                  'patch_size': 200,
                },
              ],
              'x86_64': [
                {
                  'from_version': '7.24.8',
                  'from_sha256': 'e' * 64,
                  'to_version': '7.24.9',
                  'to_sha256': 'f' * 64,
                  'patch_url': 'https://gitee.com/example/x86_64.patch',
                  'patch_size': 300,
                },
              ],
            },
          },
          'changelog_history': [],
          'announcements': [],
          'wallpaper': {},
          'changelog_archive': {},
        }),
      ) as Map<String, dynamic>,
    );

    expect(
      manifest.updateInfo.androidArchPackages.keys,
      containsAll(['arm64-v8a', 'armeabi-v7a', 'x86_64']),
    );
    expect(
      manifest.updateInfo.androidDeltaPackages['arm64-v8a']!.single.patchUrl,
      endsWith('arm64.patch'),
    );
    expect(
      manifest.updateInfo.androidDeltaPackages['armeabi-v7a']!.single.patchUrl,
      endsWith('armv7.patch'),
    );
    expect(
      manifest.updateInfo.androidDeltaPackages['x86_64']!.single.patchUrl,
      endsWith('x86_64.patch'),
    );
  });
}
