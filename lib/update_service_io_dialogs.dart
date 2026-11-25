part of 'update_service_io.dart';

Future<void> _updDialogCheckUpdateAndPrompt(
  BuildContext context, {
  bool isManual = false,
}) {
  final running = UpdateService._updateCheckFuture;
  if (running != null) return running;

  final future = _updDialog_checkUpdateAndPromptInternal(
    context,
    isManual: isManual,
  );
  UpdateService._updateCheckFuture = future;
  future.then<void>(
    (_) {
      if (identical(UpdateService._updateCheckFuture, future)) {
        UpdateService._updateCheckFuture = null;
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (identical(UpdateService._updateCheckFuture, future)) {
        UpdateService._updateCheckFuture = null;
      }
    },
  );
  return future;
}

Future<void> _updDialog_checkUpdateAndPromptInternal(
  BuildContext context, {
  bool isManual = false,
}) async {
  if (UpdateService._isDialogShowing) return;

  AppManifest? manifest = await UpdateService.checkManifest(
    preferCache: !isManual,
    refreshInBackground: !isManual,
  );
  if (manifest == null) {
    if (isManual && context.mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('检查失败，请检查网络')),
      );
    }
    return;
  }

  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String localVersion = packageInfo.version;

  bool hasUpdate = false;
  try {
    // 🚀 核心修复：纯三位数版本号对比，不依赖任何 BuildNumber 和 versionCode
    String cleanManifestVersion = manifest.versionName
        .split('+')[0]
        .split('-')[0];
    String cleanLocalVersion = localVersion.split('+')[0].split('-')[0];

    List<int> v1 = cleanManifestVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    List<int> v2 = cleanLocalVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    int maxLen = v1.length > v2.length ? v1.length : v2.length;
    bool isVersionDifferent = false;

    for (int i = 0; i < maxLen; i++) {
      int p1 = i < v1.length ? v1[i] : 0;
      int p2 = i < v2.length ? v2[i] : 0;

      if (p1 > p2) {
        hasUpdate = true;
        isVersionDifferent = true;
        break;
      } else if (p1 < p2) {
        hasUpdate = false;
        isVersionDifferent = true;
        break;
      }
    }

    // 如果 versionName 字符串一致，绝对禁止误判更新
    if (!isVersionDifferent) {
      hasUpdate = false;
    }
  } catch (e) {
    hasUpdate = false;
  }

  // 筛选需要显示的公告
  List<Announcement> announcementsToShow = [];
  for (var ann in manifest.announcements) {
    if (!ann.show) continue;
    bool annRead = await UpdateService.isAnnouncementRead(ann.id);
    if (UpdateService.shouldShowAnnouncement(ann, annRead, localVersion)) {
      announcementsToShow.add(ann);
    }
  }
  bool hasNotice = announcementsToShow.isNotEmpty;

  if (hasUpdate &&
      !manifest.forceUpdate &&
      !isManual &&
      await _updDialog_isUpdateDialogSnoozedToday(manifest.versionName)) {
    hasUpdate = false;
  }

  if (!hasUpdate && !hasNotice) {
    if (isManual && context.mounted) {
      showAppDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("检查完成"),
          content: Text("当前版本 ($localVersion) 已是最新。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("好"),
            ),
          ],
        ),
      );
    }
    return;
  }

  // 🚀 只要检测到更新，就推送系统通知
  if (hasUpdate) {
    NotificationService.showUpdateNotification(
      versionName: manifest.versionName,
      updateTitle: "🚀 官方通道：发现新版本",
      updateContent: manifest.updateInfo.description,
    );
  }

  if (context.mounted) {
    if (hasNotice) {
      await UpdateService.showAnnouncementDialog(
        context,
        announcementsToShow,
        null,
      );
      if (hasUpdate && context.mounted) {
        await UpdateService.showUpdateDialog(
          context,
          manifest,
          localVersion,
          hasUpdate: true,
          hasNotice: false,
          respectTodaySnooze: !isManual,
        );
      }
    } else if (hasUpdate) {
      await UpdateService.showUpdateDialog(
        context,
        manifest,
        localVersion,
        hasUpdate: true,
        hasNotice: false,
        respectTodaySnooze: !isManual,
      );
    }
  }
}

Future<void> _updDialogTriggerWebSocketUpdate(
  BuildContext context, {
  required String latestVersion,
  required String releaseNotes,
  required String downloadUrl,
}) async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String localVersion = packageInfo.version;

  // 核心版本对比逻辑
  bool hasUpdate = _updDialog_compareVersions(latestVersion, localVersion);
  if (!hasUpdate) return;
  if (await _updDialog_isUpdateDialogSnoozedToday(latestVersion)) return;

  // 🚀 即使弹窗已显示，也要更新通知栏，以显示“紧急直连”状态
  NotificationService.showUpdateNotification(
    versionName: latestVersion,
    updateTitle: "🚀 紧急直连：发现新版本",
    updateContent: releaseNotes,
  );

  if (UpdateService._isDialogShowing) return;

  // 🚀 偷梁换柱：用 WebSocket 发来的直链数据，动态组装一个虚拟的 AppManifest
  AppManifest mockManifest = AppManifest(
    versionCode: 0,
    versionName: latestVersion,
    forceUpdate: false,
    updateInfo: UpdateInfo.fromJson({
      'title': '发现新版本 $latestVersion',
      'description': releaseNotes,
      'full_package_url': downloadUrl,
      'PC_package_url': downloadUrl,
      'mac_package_url': downloadUrl,
    }),
    announcements: [],
    wallpaper: WallpaperConfig.fromJson({'show': false}),
    changelogArchive: const ChangelogArchiveConfig(url: ''),
  );

  if (context.mounted) {
    UpdateService.showUpdateDialog(
      context,
      mockManifest,
      localVersion,
      hasUpdate: true,
      hasNotice: false,
    );
  }
}

Future<void> _updDialogAutoDownloadLatestOnWifi(
  BuildContext context,
  AppManifest manifest, {
  void Function(double)? onProgress,
  void Function(String)? onComplete,
  void Function(String)? onError,
}) async {
  if (!Platform.isAndroid || !context.mounted) return;
  if (!await UpdateService.getAutoDownloadOnWifi() || !context.mounted) return;
  if (UpdateService._isDownloading || UpdateService._isDownloaded) return;

  // This method is also reached from update dialogs initiated by external
  // signals. Re-check the installed version here so an incorrectly marked
  // signal can never turn into an automatic package download. A manifest
  // explicitly marked as forceUpdate keeps its existing repair-install path.
  final packageInfo = await PackageInfo.fromPlatform();
  if (!manifest.forceUpdate &&
      !_updDialog_compareVersions(manifest.versionName, packageInfo.version)) {
    debugPrint(
      '[UpdateService] 跳过 Wi-Fi 自动下载：${manifest.versionName} 不高于已安装版本 ${packageInfo.version}',
    );
    return;
  }
  if (!context.mounted) return;
  if (!await UpdateService.isWifiConnected() || !context.mounted) return;

  final existingPath = await UpdateService.isPackageAlreadyDownloaded(
    manifest.versionName,
  );
  if (existingPath != null) {
    UpdateService._isDownloaded = true;
    UpdateService._localPackagePath = existingPath;
    UpdateService._uiCompleteCallback?.call(existingPath);
    onComplete?.call(existingPath);
    return;
  }

  if (UpdateService._isDownloading || !context.mounted) return;
  unawaited(
    _updDownload_startForegroundDownload(
      context,
      manifest,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    ),
  );
}

bool _updDialog_compareVersions(String manifestVersion, String localVersion) {
  try {
    String cleanManifestVersion = manifestVersion.split('+')[0].split('-')[0];
    String cleanLocalVersion = localVersion.split('+')[0].split('-')[0];

    List<int> v1 = cleanManifestVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    List<int> v2 = cleanLocalVersion
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    int maxLen = v1.length > v2.length ? v1.length : v2.length;
    for (int i = 0; i < maxLen; i++) {
      int p1 = i < v1.length ? v1[i] : 0;
      int p2 = i < v2.length ? v2[i] : 0;
      if (p1 > p2) return true;
      if (p1 < p2) return false;
    }
  } catch (_) {}
  return false;
}

Future<void> _updDialogShowAnnouncementDialog(
  BuildContext context,
  List<Announcement> announcements,
  VoidCallback? onDismissed,
) async {
  if (UpdateService._isAnnouncementDialogShowing) return;
  if (announcements.isEmpty) return;
  UpdateService._isAnnouncementDialogShowing = true;

  if (!context.mounted) {
    UpdateService._isAnnouncementDialogShowing = false;
    return;
  }

  await showAppDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return _AnnouncementCarouselDialog(announcements: announcements);
    },
  );

  UpdateService._isAnnouncementDialogShowing = false;
  onDismissed?.call();
}

Future<void> _updDialogShowUpdateDialog(
  BuildContext context,
  AppManifest manifest,
  String currentVersion, {
  bool hasUpdate = true,
  bool hasNotice = false,
  bool respectTodaySnooze = true,
}) async {
  if (UpdateService._isDialogShowing) return;
  if (hasUpdate &&
      !manifest.forceUpdate &&
      !_updDialog_compareVersions(manifest.versionName, currentVersion)) {
    debugPrint(
      '[UpdateService] 忽略非新版本更新弹窗：${manifest.versionName}，当前版本 $currentVersion',
    );
    return;
  }
  final now = DateTime.now();
  if (hasUpdate &&
      !manifest.forceUpdate &&
      UpdateService._lastPromptedUpdateVersion == manifest.versionName &&
      UpdateService._lastPromptedUpdateAt != null &&
      now.difference(UpdateService._lastPromptedUpdateAt!) <
          const Duration(minutes: 10)) {
    return;
  }
  UpdateService._isDialogShowing = true;
  if (hasUpdate &&
      respectTodaySnooze &&
      !manifest.forceUpdate &&
      await _updDialog_isUpdateDialogSnoozedToday(manifest.versionName)) {
    UpdateService._isDialogShowing = false;
    return;
  }
  if (hasUpdate && !manifest.forceUpdate) {
    UpdateService._lastPromptedUpdateVersion = manifest.versionName;
    UpdateService._lastPromptedUpdateAt = now;
  }

  // 🚀 只要弹窗显示了，就说明用户已经进入更新流程，立即取消通知栏提醒
  NotificationService.cancelUpdateNotification();

  if (!UpdateService._isDownloading && !UpdateService._isDownloaded) {
    String? existingPath = await UpdateService.isPackageAlreadyDownloaded(
      manifest.versionName,
    );
    if (existingPath != null) {
      UpdateService._isDownloaded = true;
      UpdateService._localPackagePath = existingPath;
    }
  }

  if (!context.mounted) {
    UpdateService._isDialogShowing = false;
    return;
  }

  if (hasUpdate &&
      !UpdateService._isDownloading &&
      !UpdateService._isDownloaded) {
    unawaited(UpdateService.autoDownloadLatestOnWifi(context, manifest));
  }

  await showAppDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return PopScope(
        canPop: !manifest.forceUpdate,
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            UpdateService._uiProgressCallback = (p) {
              if (context.mounted) setState(() {});
            };
            UpdateService._uiCompleteCallback = (path) {
              if (context.mounted) setState(() {});
            };
            UpdateService._uiErrorCallback = (err) {
              if (context.mounted) {
                setState(() {});
                AppSnackBars.showSnackBar(ctx, SnackBar(content: Text(err)));
              }
            };

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (manifest.wallpaper.show &&
                        manifest.wallpaper.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        child: GitHubResourceImage(
                          url: manifest.wallpaper.imageUrl,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: Colors.grey[200]),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasUpdate) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.new_releases,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  manifest.updateInfo.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "当前: $currentVersion  →  最新: ${manifest.versionName}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(manifest.updateInfo.description),
                            const SizedBox(height: 20),
                            if (manifest.updateInfo.fullPackageUrl.isNotEmpty)
                              if (UpdateService._isDownloaded)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 🚀 核心防崩区域：安全地保留纯 Text，禁止外部包裹任何 Expanded/Flexible
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.system_update),
                                      label: Text(
                                        Platform.isMacOS
                                            ? "下载完成，打开下载目录"
                                            : "下载完成，立即安装",
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        if (UpdateService._localPackagePath !=
                                            null) {
                                          UpdateService.installPackage(
                                            UpdateService._localPackagePath!,
                                          );
                                          NotificationService.cancelUpdateNotification();
                                        }
                                      },
                                    ),
                                    if (Platform.isMacOS)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          "请在访达中解压 zip 文件，然后将 App 拖入「应用程序」文件夹",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    TextButton(
                                      onPressed: () {
                                        if (UpdateService._isDownloading)
                                          return;
                                        setState(() {});
                                        _updDownload_startForegroundDownload(
                                          context,
                                          manifest,
                                        );
                                      },
                                      child: const Text(
                                        "安装失败？点击强制重新下载",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else if (UpdateService._isDownloading)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "正在下载更新包...",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          "${(UpdateService._downloadProgress * 100).toStringAsFixed(1)}%",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: UpdateService._downloadProgress,
                                        minHeight: 12,
                                        backgroundColor: Colors.grey[200],
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                            ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text(
                                      "立即下载新版本",
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onPressed: () {
                                      if (UpdateService._isDownloading) return;
                                      setState(() {});
                                      _updDownload_startForegroundDownload(
                                        context,
                                        manifest,
                                      );
                                    },
                                  ),
                                ),
                            if (hasNotice) const Divider(height: 30),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!manifest.forceUpdate &&
                    hasUpdate &&
                    !UpdateService._isDownloading)
                  TextButton(
                    onPressed: () async {
                      await _updDialog_snoozeUpdateDialogForToday(
                        manifest.versionName,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("今日不再提醒"),
                  ),
                if (!manifest.forceUpdate)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      UpdateService._isDownloading
                          ? "后台下载"
                          : (UpdateService._isDownloaded ? "关闭" : "稍后再说"),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
  UpdateService._isDialogShowing = false;
  UpdateService._uiProgressCallback = null;
  UpdateService._uiCompleteCallback = null;
  UpdateService._uiErrorCallback = null;
}

String _updDialog_todayKey([DateTime? now]) {
  final date = now ?? DateTime.now();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _updDialog_snoozeValue(String versionName, [DateTime? now]) =>
    '${_updDialog_todayKey(now)}|$versionName';

Future<bool> _updDialog_isUpdateDialogSnoozedToday(String versionName) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(UpdateService._updateDialogSnoozeTodayKey) ==
      _updDialog_snoozeValue(versionName);
}

Future<void> _updDialog_snoozeUpdateDialogForToday(String versionName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    UpdateService._updateDialogSnoozeTodayKey,
    _updDialog_snoozeValue(versionName),
  );
}
