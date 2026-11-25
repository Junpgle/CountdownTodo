part of 'update_service_io.dart';

String _updDownloadGetUpdateFileName(String versionName) {
  if (Platform.isWindows) return "CountdownTodo_v$versionName.exe";
  if (Platform.isMacOS) return "CountdownTodo_v$versionName.zip";
  return "CountdownTodo_v$versionName.apk";
}

String _updDownload_normalizeMacArch(String rawArch) {
  final normalized = rawArch.trim().toLowerCase();
  if (normalized == 'x86_64' ||
      normalized == 'x64' ||
      normalized == 'amd64' ||
      normalized == 'i386') {
    return 'x86_64';
  }
  if (normalized == 'arm64' || normalized == 'aarch64') {
    return 'arm64';
  }
  return '';
}

String _updDownloadSelectAndroidArchitecture(Iterable<String> supportedAbis) {
  final normalized = supportedAbis
      .map((abi) => abi.trim())
      .where((abi) => abi.isNotEmpty)
      .toList();
  for (final abi in normalized) {
    if (UpdateService.supportedAndroidPackageAbis.contains(abi)) {
      return abi;
    }
  }
  return normalized.isNotEmpty ? normalized.first : 'arm64-v8a';
}

Future<String> _updDownloadGetDeviceArchitecture() async {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) {
    try {
      final macInfo = await DeviceInfoPlugin().macOsInfo;
      final arch = _updDownload_normalizeMacArch(macInfo.arch);
      if (arch.isNotEmpty) return arch;
    } catch (_) {}
    try {
      final result = await Process.run('uname', ['-m']);
      if (result.exitCode == 0) {
        final arch = _updDownload_normalizeMacArch(result.stdout.toString());
        if (arch.isNotEmpty) return arch;
      }
    } catch (_) {}
    return 'arm64';
  }
  final deviceInfo = DeviceInfoPlugin();
  final androidInfo = await deviceInfo.androidInfo;
  return UpdateService.selectAndroidArchitecture(androidInfo.supportedAbis);
}

Future<String> _updDownloadGetDownloadUrlForArch(AppManifest manifest) async {
  debugPrint(
    '[UpdateService] getDownloadUrlForArch: macPackageUrl=${manifest.updateInfo.macPackageUrl}, macArchPackages=${manifest.updateInfo.macArchPackages}, pcPackageUrl=${manifest.updateInfo.pcPackageUrl}',
  );
  if (Platform.isMacOS) {
    final macArchPackages = manifest.updateInfo.macArchPackages;
    if (macArchPackages.isNotEmpty) {
      final architecture = await UpdateService.getDeviceArchitecture();
      final packageUrl = macArchPackages[architecture];
      debugPrint(
        '[UpdateService] macOS architecture: $architecture, package: $packageUrl',
      );
      if (packageUrl != null && packageUrl.isNotEmpty) {
        return _updManifest_giteePackageUrl(packageUrl);
      }
    }
    if (manifest.updateInfo.macPackageUrl.isNotEmpty) {
      debugPrint(
        '[UpdateService] Using macPackageUrl: ${manifest.updateInfo.macPackageUrl}',
      );
      return _updManifest_giteePackageUrl(manifest.updateInfo.macPackageUrl);
    }
  }
  if (Platform.isWindows && manifest.updateInfo.pcPackageUrl.isNotEmpty) {
    return _updManifest_giteePackageUrl(manifest.updateInfo.pcPackageUrl);
  }
  final archPackages = manifest.updateInfo.androidArchPackages;
  if (archPackages.isNotEmpty) {
    final architecture = await UpdateService.getDeviceArchitecture();
    final packageUrl = archPackages[architecture];
    debugPrint(
      '[UpdateService] Android architecture: $architecture, package: $packageUrl',
    );
    if (packageUrl != null && packageUrl.isNotEmpty) {
      return _updManifest_giteePackageUrl(packageUrl);
    }
  }
  debugPrint(
    '[UpdateService] Using fullPackageUrl: ${manifest.updateInfo.fullPackageUrl}',
  );
  return _updManifest_giteePackageUrl(manifest.updateInfo.fullPackageUrl);
}

String? _updDownload_resolveExpectedSha256SyncFallback(AppManifest manifest) {
  final fullSha = manifest.updateInfo.fullPackageSha256;
  return fullSha.isEmpty ? null : fullSha;
}

Future<String?> _updDownload_getExpectedSha256ForArch(
  AppManifest manifest,
) async {
  if (Platform.isMacOS) {
    if (manifest.updateInfo.macArchSha256.isNotEmpty) {
      final arch = await UpdateService.getDeviceArchitecture();
      final archSha = manifest.updateInfo.macArchSha256[arch]?.trim();
      if (archSha != null && archSha.isNotEmpty) return archSha;
    }
    if (manifest.updateInfo.macPackageSha256.isNotEmpty) {
      return manifest.updateInfo.macPackageSha256;
    }
  }
  if (Platform.isWindows && manifest.updateInfo.pcPackageSha256.isNotEmpty) {
    return manifest.updateInfo.pcPackageSha256;
  }
  if (Platform.isAndroid && manifest.updateInfo.androidArchSha256.isNotEmpty) {
    final arch = await UpdateService.getDeviceArchitecture();
    final archSha = manifest.updateInfo.androidArchSha256[arch]?.trim();
    if (archSha != null && archSha.isNotEmpty) return archSha;
  }
  return _updDownload_resolveExpectedSha256SyncFallback(manifest);
}

Uri _updDownloadValidateDownloadUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    throw FormatException('仅允许通过 HTTPS 下载更新包: $url');
  }
  return uri;
}

Future<void> _updDownloadVerifyArtifactSha256(
  File file,
  String? expectedSha256,
) async {
  final normalizedExpected = expectedSha256?.trim().toLowerCase() ?? '';
  if (normalizedExpected.isEmpty) return;
  final actual = (await AndroidDeltaService.sha256Of(file)).toLowerCase();
  if (actual != normalizedExpected) {
    throw FormatException(
      '更新包 SHA-256 校验失败: expected=$normalizedExpected, actual=$actual',
    );
  }
}

Future<_UpdateArtifact> _updDownload_getUpdateArtifact(
  AppManifest manifest, {
  bool preferDelta = true,
}) async {
  final fullUrl = await UpdateService.getDownloadUrlForArch(manifest);
  final expectedFullSha256 = await _updDownload_getExpectedSha256ForArch(
    manifest,
  );
  final fullArtifact = _UpdateArtifact(
    url: fullUrl,
    fileName: UpdateService.getUpdateFileName(manifest.versionName),
    expectedSha256: expectedFullSha256,
  );

  if (!preferDelta || !Platform.isAndroid) return fullArtifact;

  try {
    final architecture = await UpdateService.getDeviceArchitecture();
    final candidates = manifest.updateInfo.androidDeltaPackages[architecture];
    if (candidates == null || candidates.isEmpty) return fullArtifact;

    final packageInfo = await PackageInfo.fromPlatform();
    final localVersion = _updManifest_cleanVersion(packageInfo.version);
    final basePath = await AndroidDeltaService.getInstalledApkPath();
    if (basePath == null || basePath.isEmpty) return fullArtifact;

    final baseApk = File(basePath);
    if (!await baseApk.exists()) return fullArtifact;
    final baseSha256 = await AndroidDeltaService.sha256Of(baseApk);

    for (final candidate in candidates) {
      if (!candidate.isUsable ||
          _updManifest_cleanVersion(candidate.fromVersion) != localVersion ||
          _updManifest_cleanVersion(candidate.toVersion) !=
              _updManifest_cleanVersion(manifest.versionName) ||
          candidate.fromSha256.toLowerCase() != baseSha256.toLowerCase()) {
        continue;
      }

      final patchUrl = _updManifest_giteePackageUrl(candidate.patchUrl);
      if (patchUrl.isEmpty) continue;

      debugPrint(
        '[UpdateService] Using $architecture delta ${candidate.fromVersion} -> ${candidate.toVersion}',
      );
      return _UpdateArtifact(
        url: patchUrl,
        fileName:
            'CountdownTodo_v${manifest.versionName}_from_${candidate.fromVersion}.patch',
        delta: candidate,
        baseApkPath: baseApk.path,
      );
    }
  } catch (error) {
    debugPrint(
      '[UpdateService] Delta selection failed, using full APK: $error',
    );
  }

  return fullArtifact;
}

Future<bool> _updDownloadHasUsableDeltaPackage(AppManifest manifest) async {
  if (!Platform.isAndroid) return false;
  final artifact = await _updDownload_getUpdateArtifact(manifest);
  return artifact.isDelta;
}

Future<String?> _updDownloadIsPackageAlreadyDownloaded(
  String versionName,
) async {
  final fileName = UpdateService.getUpdateFileName(versionName);
  for (final path in await _updDownload_getDownloadDirectories()) {
    File file = File("$path/$fileName");

    if (!await file.exists()) {
      final zipFile = File("$path/$fileName.zip");
      if (await zipFile.exists()) file = zipFile;
    }

    if (await file.exists() && await file.length() > 1024 * 1024) {
      return file.path;
    }
  }
  return null;
}

Future<void> _updDownloadClearDownloadedPackage(String filePath) async {
  if (UpdateService._isDownloading) {
    throw StateError('更新包正在下载，无法清除');
  }

  final file = File(filePath);
  final fileName = file.uri.pathSegments.last;
  final relatedNames = <String>{fileName};
  if (fileName.toLowerCase().endsWith('.zip')) {
    relatedNames.add(fileName.substring(0, fileName.length - 4));
  } else {
    relatedNames.add('$fileName.zip');
  }

  final pathsToClear = <String>{file.path};
  for (final directory in await _updDownload_getDownloadDirectories()) {
    for (final relatedName in relatedNames) {
      pathsToClear.add('$directory/$relatedName');
    }
  }
  for (final path in pathsToClear) {
    final relatedFile = File(path);
    if (await relatedFile.exists()) await relatedFile.delete();
  }

  if (UpdateService._localPackagePath != null &&
      pathsToClear.contains(UpdateService._localPackagePath)) {
    UpdateService._localPackagePath = null;
    UpdateService._isDownloaded = false;
    UpdateService._downloadProgress = 0;
    UpdateService._uiProgressCallback?.call(0);
  }
}

Future<List<String>> _updDownload_getDownloadDirectories() async {
  final directories = <String>[];
  final publicDirectory = await UpdateService.getDownloadDirectory();
  if (publicDirectory != null) directories.add(publicDirectory);

  if (Platform.isAndroid) {
    try {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        final appDirectory = Directory(
          '${externalDirectory.path}/Download/CountdownTodo',
        );
        if (!await appDirectory.exists()) {
          await appDirectory.create(recursive: true);
        }
        if (!directories.contains(appDirectory.path)) {
          directories.add(appDirectory.path);
        }
      }
    } catch (error) {
      debugPrint('[UpdateService] 获取应用更新目录失败: $error');
    }
  }

  return directories;
}

Future<bool> _updDownloadPrepareForDownload(
  BuildContext context,
  String targetVersionName,
) async {
  // Windows 直接放行，跳过移动端权限申请
  if (!Platform.isAndroid) return true;

  final coordinator = PermissionRequestCoordinator(context: context);
  try {
    final storage = await coordinator.request(AppPermissionKind.storage);
    if (!storage.granted) return false;

    final install = await coordinator.request(AppPermissionKind.requestInstall);
    if (!install.granted) return false;
  } finally {
    coordinator.dispose();
  }

  try {
    for (final path in await _updDownload_getDownloadDirectories()) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final List<FileSystemEntity> files = dir.listSync();
        for (var file in files) {
          String name = file.path
              .split(Platform.pathSeparator)
              .last
              .toLowerCase();
          if (name.endsWith(".apk") ||
              name.endsWith(".exe") ||
              name.endsWith(".zip") ||
              name.endsWith(".patch") ||
              name.endsWith(".download")) {
            await file.delete();
          }
        }
      }
    }
  } catch (e) {
    debugPrint('[UpdateService] 清理旧安装包失败: $e');
  }

  return true;
}

Future<String?> _updDownloadGetDownloadDirectory() async {
  if (Platform.isAndroid) {
    const String baseDownloadPath = '/storage/emulated/0/Download';
    final String customPath = '$baseDownloadPath/CountdownTodo';
    final customDir = Directory(customPath);

    try {
      if (!await customDir.exists()) await customDir.create(recursive: true);
      return customDir.path;
    } catch (e) {
      final externalDir = await getExternalStorageDirectory();
      return externalDir?.path;
    }
  }

  // Windows 获取系统 Downloads 文件夹
  final downloadDir = await getDownloadsDirectory();
  if (downloadDir != null) {
    final customDir = Directory('${downloadDir.path}/CountdownTodo');
    if (!await customDir.exists()) await customDir.create(recursive: true);
    return customDir.path;
  }
  return null;
}

Future<void> _updDownloadInstallPackage(String filePath) async {
  File file = File(filePath);

  if (!await file.exists()) {
    final zipFile = File("$filePath.zip");
    if (await zipFile.exists()) {
      file = await zipFile.rename(filePath);
    } else {
      if (filePath.endsWith(".zip")) {
        final apkPath = filePath.substring(0, filePath.length - 4);
        file = await file.rename(apkPath);
      } else {
        return;
      }
    }
  } else {
    if (filePath.endsWith(".zip") && !Platform.isMacOS) {
      final apkPath = filePath.substring(0, filePath.length - 4);
      file = await file.rename(apkPath);
    }
  }

  if (Platform.isWindows) {
    await Process.run(file.path, [], runInShell: true);
    return;
  }

  if (Platform.isMacOS) {
    // macOS: 打开下载目录，让用户手动解压并拖到 Applications
    final dir = file.parent.path;
    await Process.run('open', [dir]);
    return;
  }

  await OpenFile.open(
    file.path,
    type: Platform.isAndroid ? "application/vnd.android.package-archive" : null,
  );
}

Future<void> _updDownloadDownloadLatestPackage(
  BuildContext context,
  AppManifest manifest, {
  bool preferDelta = true,
  required void Function(double) onProgress,
  required void Function(String) onComplete,
  required void Function(String) onError,
}) async {
  await UpdateService._downloadSubscription?.cancel();
  if (!context.mounted) {
    onError('页面已关闭，已取消下载');
    return;
  }

  final existingPath = await UpdateService.isPackageAlreadyDownloaded(
    manifest.versionName,
  );
  if (existingPath != null) {
    onProgress(1.0);
    onComplete(existingPath);
    return;
  }

  if (!context.mounted) {
    onError('页面已关闭，已取消下载');
    return;
  }
  final ready = await UpdateService.prepareForDownload(
    context,
    manifest.versionName,
  );
  if (!ready) {
    onError('准备下载环境失败，请检查存储权限');
    return;
  }

  final path = await UpdateService.getDownloadDirectory();
  if (path == null) {
    onError('无法获取下载保存目录');
    return;
  }

  try {
    final finalFile = await _updDownload_downloadUpdateWithFallback(
      manifest,
      path,
      preferDelta: preferDelta,
      onProgress: onProgress,
    );
    onComplete(finalFile.path);
  } catch (e) {
    onError('更新包下载或校验失败: $e');
  }
}

Future<void> _updDownloadForceDownloadLatest(
  BuildContext context, {
  required Function(double) onProgress,
  required Function(String) onComplete,
  required Function(String) onError,
}) async {
  final manifest = await UpdateService.checkManifest(
    preferCache: false,
    refreshInBackground: false,
  );
  if (manifest == null) {
    onError('获取版本信息失败，请检查网络');
    return;
  }

  // 检查是否已下载
  final existingPath = await UpdateService.isPackageAlreadyDownloaded(
    manifest.versionName,
  );
  if (existingPath != null) {
    onComplete(existingPath);
    return;
  }

  await UpdateService._downloadSubscription?.cancel();
  if (!context.mounted) {
    onError('页面已关闭，已取消权限申请');
    return;
  }

  bool ready = await UpdateService.prepareForDownload(
    context,
    manifest.versionName,
  );
  if (!ready) {
    onError('准备下载环境失败，请检查存储权限');
    return;
  }

  final path = await UpdateService.getDownloadDirectory();
  if (path == null) {
    onError('无法获取下载保存目录');
    return;
  }

  try {
    final finalFile = await _updDownload_downloadUpdateWithFallback(
      manifest,
      path,
      preferDelta: false,
      onProgress: onProgress,
    );
    onComplete(finalFile.path);
  } catch (e) {
    onError("更新包下载或校验失败: $e");
  }
}

Future<File> _updDownload_downloadUpdateWithFallback(
  AppManifest manifest,
  String directory, {
  bool preferDelta = true,
  required void Function(double) onProgress,
}) async {
  final artifact = await _updDownload_getUpdateArtifact(
    manifest,
    preferDelta: preferDelta,
  );
  if (artifact.url.isEmpty) {
    throw const FormatException('未找到可用的下载链接');
  }

  try {
    return await _updDownload_downloadArtifact(
      artifact,
      directory,
      onProgress: onProgress,
    );
  } catch (error) {
    if (!artifact.isDelta) rethrow;

    debugPrint(
      '[UpdateService] Delta update failed, falling back to full APK: $error',
    );
    onProgress(0.0);
    final fullArtifact = await _updDownload_getUpdateArtifact(
      manifest,
      preferDelta: false,
    );
    if (fullArtifact.url.isEmpty) rethrow;
    return _updDownload_downloadArtifact(
      fullArtifact,
      directory,
      onProgress: onProgress,
    );
  }
}

Future<File> _updDownload_downloadArtifact(
  _UpdateArtifact artifact,
  String directory, {
  required void Function(double) onProgress,
}) async {
  final savePath = '$directory/${artifact.fileName}';
  final tempFile = File('$savePath.download');
  File? downloadedFile;

  try {
    final downloadUri = UpdateService.validateDownloadUrl(artifact.url);
    if (await tempFile.exists()) await tempFile.delete();
    final response = await UpdateService._resourceService.sendGet(downloadUri);
    if (response.statusCode != 200) {
      throw HttpException('服务器响应异常: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = tempFile.openWrite();
    final completed = Completer<void>();

    UpdateService._downloadSubscription = response.stream.listen(
      (List<int> chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
      },
      onDone: () async {
        try {
          await sink.close();
          if (!completed.isCompleted) completed.complete();
        } catch (error, stackTrace) {
          if (!completed.isCompleted) {
            completed.completeError(error, stackTrace);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) async {
        await sink.close();
        if (!completed.isCompleted) {
          completed.completeError(error, stackTrace);
        }
      },
      cancelOnError: true,
    );
    await completed.future;

    downloadedFile = await tempFile.rename(savePath);
    onProgress(1.0);

    if (!artifact.isDelta) {
      await UpdateService.verifyArtifactSha256(
        downloadedFile,
        artifact.expectedSha256,
      );
      return downloadedFile;
    }

    final delta = artifact.delta!;
    final basePath = artifact.baseApkPath;
    if (basePath == null || basePath.isEmpty) {
      throw const FormatException('差分包缺少基础 APK');
    }

    final targetPath =
        '$directory/${UpdateService.getUpdateFileName(delta.toVersion)}';
    final targetTempFile = File('$targetPath.download');
    if (await targetTempFile.exists()) await targetTempFile.delete();
    await AndroidDeltaService.applyPatch(
      baseApk: File(basePath),
      patchFile: downloadedFile,
      outputApk: targetTempFile,
      expectedBaseSha256: delta.fromSha256,
      expectedTargetSha256: delta.toSha256,
    );

    final targetFile = await targetTempFile.rename(targetPath);
    if (await downloadedFile.exists()) await downloadedFile.delete();
    return targetFile;
  } catch (_) {
    if (await tempFile.exists()) await tempFile.delete();
    if (downloadedFile != null && await downloadedFile.exists()) {
      await downloadedFile.delete();
    }
    rethrow;
  }
}

Future<void> _updDownload_startForegroundDownload(
  BuildContext context,
  AppManifest manifest, {
  void Function(double)? onProgress,
  void Function(String)? onComplete,
  void Function(String)? onError,
}) async {
  if (UpdateService._isDownloading) return;
  UpdateService._isDownloading = true;
  UpdateService._isDownloaded = false;
  UpdateService._downloadProgress = 0.0;
  UpdateService._uiProgressCallback?.call(0.0);
  onProgress?.call(0.0);

  await UpdateService._downloadSubscription?.cancel();
  if (!context.mounted) {
    UpdateService._isDownloading = false;
    UpdateService._uiErrorCallback?.call("页面已关闭，已取消权限申请");
    onError?.call("页面已关闭，已取消权限申请");
    return;
  }

  bool ready = await UpdateService.prepareForDownload(
    context,
    manifest.versionName,
  );
  if (!ready) {
    UpdateService._isDownloading = false;
    UpdateService._uiErrorCallback?.call("准备下载环境失败，请检查存储权限");
    onError?.call("准备下载环境失败，请检查存储权限");
    return;
  }

  final path = await UpdateService.getDownloadDirectory();
  if (path == null) {
    UpdateService._isDownloading = false;
    UpdateService._uiErrorCallback?.call("无法获取下载保存目录");
    onError?.call("无法获取下载保存目录");
    return;
  }

  try {
    final finalFile = await _updDownload_downloadUpdateWithFallback(
      manifest,
      path,
      onProgress: (progress) {
        UpdateService._downloadProgress = progress;
        UpdateService._uiProgressCallback?.call(progress);
        onProgress?.call(progress);
      },
    );

    UpdateService._isDownloading = false;
    UpdateService._isDownloaded = true;
    UpdateService._localPackagePath = finalFile.path;
    UpdateService._uiCompleteCallback?.call(finalFile.path);
    onComplete?.call(finalFile.path);
  } catch (e) {
    UpdateService._isDownloading = false;
    UpdateService._uiErrorCallback?.call("更新包下载或校验失败: $e");
    onError?.call("更新包下载或校验失败: $e");
  }
}
