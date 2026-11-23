import 'dart:io';

import 'package:countdown_todo/services/android_delta_service.dart';
import 'package:countdown_todo/update_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validateDownloadUrl enforces https with non-empty host', () {
    expect(
      () => UpdateService.validateDownloadUrl('http://gitee.com/app.apk'),
      throwsFormatException,
    );
    expect(() => UpdateService.validateDownloadUrl(''), throwsFormatException);
    expect(
      () => UpdateService.validateDownloadUrl('file:///tmp/app.apk'),
      throwsFormatException,
    );

    final valid = UpdateService.validateDownloadUrl(
      'https://gitee.com/junpgle/releases/app.apk',
    );
    expect(valid.scheme, 'https');
    expect(valid.host, 'gitee.com');
  });

  test(
    'verifyArtifactSha256 validates matching and mismatched digests',
    () async {
      final dir = await Directory.systemTemp.createTemp('update_sha_test_');
      try {
        final file = File('${dir.path}/sample.bin');
        await file.writeAsBytes(const [1, 2, 3, 4, 5], flush: true);
        final digest = await AndroidDeltaService.sha256Of(file);

        await UpdateService.verifyArtifactSha256(file, null);
        await UpdateService.verifyArtifactSha256(file, '');
        await UpdateService.verifyArtifactSha256(file, digest.toUpperCase());

        await expectLater(
          UpdateService.verifyArtifactSha256(file, '0' * 64),
          throwsFormatException,
        );
      } finally {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    },
  );

  test('UpdateInfo parses optional full and per-arch sha256 fields', () {
    final info = UpdateInfo.fromJson({
      'title': '7.25.2',
      'full_package_url': 'https://gitee.com/full.apk',
      'full_package_sha256': 'aaa',
      'PC_package_sha256': 'bbb',
      'mac_package_sha256': 'ccc',
      'mac_arch_sha256': {'arm64': 'ddd', 'x86_64': 'eee'},
      'android_arch_sha256': {'arm64-v8a': 'fff'},
    });

    expect(info.fullPackageSha256, 'aaa');
    expect(info.pcPackageSha256, 'bbb');
    expect(info.macPackageSha256, 'ccc');
    expect(info.macArchSha256['arm64'], 'ddd');
    expect(info.androidArchSha256['arm64-v8a'], 'fff');
  });
}
