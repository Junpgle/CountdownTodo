part of '../feature_guide_screen.dart';

extension _FeatureGuideData on _FeatureGuideScreenState {
  Future<void> _loadGuideConfiguration() async {
    final tasks = <Future<void>>[
      _checkPermissions(),
      _loadGlobalSettings(),
      _loadLiquidGlassState(),
      _loadDeviceCalendarReadGuideState(),
      _loadMinorModeGuideState(),
    ];
    if (AppPlatform.isWindows) tasks.add(_loadTaiConfig());
    await Future.wait<void>(tasks);
  }

  Future<void> _loadLiquidGlassState() async {
    final offered = await LiquidGlassEffectService.isGuideOfferDone();
    if (mounted) _mutateState(() => _guideOffered = offered);
  }

  Future<void> _loadDeviceCalendarReadGuideState() async {
    final offered = await DeviceCalendarReadService.isGuideOfferDone();
    if (mounted) _mutateState(() => _deviceCalendarReadGuideOffered = offered);
  }

  Future<void> _setupPages() async {
    await _guideConfigurationFuture;
    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey);

    // 如果之前没有记录过版本号，则是首次安装。
    final isFirstLaunch = shownVersion == null || shownVersion.isEmpty;
    // 保存到 state，供 _done 使用
    _isFirstLaunch = isFirstLaunch;

    List<Widget Function()> pages = [];

    // 无论如何，第一页永远是更新日志
    pages.add(_buildChangelogPage);

    // 仅自动升级流程在本次版本范围内确实包含数据库/存储迁移相关变更时展示。
    if (!isFirstLaunch && !_isManualReview && _showDatabaseUpdatePage) {
      pages.add(_buildUniSyncMigrationPage);
    }

    final onlyUnconfigured = !isFirstLaunch && !_isManualReview;
    final platformGuidePages = _buildPlatformGuidePages(
      onlyUnconfigured: onlyUnconfigured,
    );
    final shouldShowGuide =
        widget.mode == FeatureGuideMode.guide ||
        (widget.mode == FeatureGuideMode.automatic &&
            (isFirstLaunch ||
                widget.isManualReview ||
                platformGuidePages.isNotEmpty));
    if (shouldShowGuide) {
      pages.addAll(platformGuidePages);
    }

    // 记录本次引导是否包含外观设置页：用户正常完成引导时写入
    // "已展示"标记，之后不再重复展示（用户可能不想要，不能反复打扰）。
    _themeSetupPageIncluded =
        shouldShowGuide && pages.contains(_buildGlobalThemeSetupPage);
    _deviceCalendarReadSetupPageIncluded =
        shouldShowGuide && pages.contains(_buildDeviceCalendarReadSetupPage);

    if (mounted) {
      _mutateState(() {
        _pagesBuilder = pages;
      });
    }
  }

  List<Widget Function()> _buildPlatformGuidePages({
    bool onlyUnconfigured = false,
  }) {
    if (AppPlatform.isWeb) {
      if (!onlyUnconfigured) {
        return [
          _buildWebFeaturePage,
          _buildWebCapabilityPage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ];
      }
      return [
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        // 未开启过液态玻璃的老用户，升级引导中也给出外观选择。
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }
    if (AppPlatform.isMacOS) {
      if (!onlyUnconfigured) {
        return [
          _buildMacFeaturePage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ];
      }
      return [
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }
    if (AppPlatform.isWindows) {
      if (!onlyUnconfigured) {
        return [
          _buildWinFeaturePage1,
          _buildWinFeaturePage2,
          _buildTaiSetupPage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ];
      }
      return [
        if (_taiDbPath.isEmpty) _buildTaiSetupPage,
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }
    if (AppPlatform.isAndroid && !onlyUnconfigured) {
      return [
        _buildAndroidFeaturePage1,
        _buildAndroidFeaturePage2,
        _buildAndroidWidgetGuidePage,
        _buildMinorModeGuidePage,
        if (!_deviceCalendarReadGuideOffered) _buildDeviceCalendarReadSetupPage,
        _buildGlobalCourseSetupPage,
        _buildGlobalThemeSetupPage,
      ];
    }

    if (!AppPlatform.isAndroid) {
      return [
        if (DeviceCalendarReadService.isSupported &&
            !_deviceCalendarReadGuideOffered)
          _buildDeviceCalendarReadSetupPage,
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }

    return [
      if (!_hasUsageStats) _buildAndroidFeaturePage1,
      if (_notificationStatus?.isGranted != true || !_hasExactAlarm)
        _buildAndroidFeaturePage2,
      if (!_minorModeGuideConfigured) _buildMinorModeGuidePage,
      if (!_deviceCalendarReadGuideOffered) _buildDeviceCalendarReadSetupPage,
      if (!_semesterEnabled) _buildGlobalCourseSetupPage,
      if (!_guideOffered) _buildGlobalThemeSetupPage,
    ];
  }

  bool get _minorModeGuideConfigured {
    final service = MinorModeService.instance;
    return service.policyState.systemEnabled || service.manualBirthDate != null;
  }

  Future<void> _loadGlobalSettings() async {
    final start = await StorageService.getSemesterStart();
    final end = await StorageService.getSemesterEnd();
    final enabled = await StorageService.getSemesterEnabled();
    if (mounted) {
      _mutateState(() {
        _semesterStart = start;
        _semesterEnd = end;
        _semesterEnabled = enabled;
      });
    }
    unawaited(_checkCloudData());
  }

  Future<void> _checkCloudData() async {
    if (widget.loggedInUser == null || widget.loggedInUser!.isEmpty) return;
    if (mounted) _mutateState(() => _checkingCloudData = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id') ?? 0;
    if (userId == 0) {
      if (mounted) _mutateState(() => _checkingCloudData = false);
      return;
    }

    final results = await Future.wait([
      ApiService.fetchAllCourses(userId),
      ApiService.fetchUserSettings(),
    ]).timeout(const Duration(seconds: 5), onTimeout: () => [null, null]);

    final cloudCoursesRaw = results[0] as List<dynamic>?;
    final cloudSettings = results[1] as Map<String, dynamic>?;

    List<CourseItem>? courses;
    if (cloudCoursesRaw != null && cloudCoursesRaw.isNotEmpty) {
      courses = cloudCoursesRaw.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        // The API uses `semester`, while CourseItem accepts the local storage
        // name `semester_id`; preserve it before deserializing.
        map['semester_id'] =
            map['semester_id'] ??
            map['semester'] ??
            map['semesterId'] ??
            'default';
        return CourseItem.fromJson(map);
      }).toList();
    }

    DateTime? semStart;
    DateTime? semEnd;
    if (cloudSettings != null) {
      if (cloudSettings['semester_start'] != null) {
        semStart = DateTime.fromMillisecondsSinceEpoch(
          (cloudSettings['semester_start'] as num).toInt(),
        );
      }
      if (cloudSettings['semester_end'] != null) {
        semEnd = DateTime.fromMillisecondsSinceEpoch(
          (cloudSettings['semester_end'] as num).toInt(),
        );
      }
    }

    if (mounted) {
      _mutateState(() {
        _checkingCloudData = false;
        _hasCloudCourses = courses != null && courses.isNotEmpty;
        _cloudCourses = courses;
        _hasCloudSemester = semStart != null && semEnd != null;
        _cloudSemesterStart = semStart;
        _cloudSemesterEnd = semEnd;
      });
    }
  }

  Future<void> _importCloudCourses() async {
    if (_cloudCourses == null || _cloudCourses!.isEmpty) return;
    _mutateState(() => _importingCourses = true);
    try {
      await CourseService.replaceCoursesForSemesters(
        widget.loggedInUser!,
        _cloudCourses!,
      );
      if (mounted) {
        _mutateState(() => _hasCloudCourses = false);
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('课表已从云端导入成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _importingCourses = false);
    }
  }

  Future<void> _importCloudSemester() async {
    if (_cloudSemesterStart == null || _cloudSemesterEnd == null) return;
    _mutateState(() => _importingSemester = true);
    try {
      await StorageService.saveAppSetting(
        StorageService.keySemesterStart,
        CourseScheduleSemantics.mondayOf(_cloudSemesterStart!)
            .toIso8601String(),
      );
      await StorageService.saveAppSetting(
        StorageService.keySemesterEnd,
        _cloudSemesterEnd!.toIso8601String(),
      );
      if (mounted) {
        _mutateState(() {
          _semesterStart = CourseScheduleSemantics.mondayOf(
            _cloudSemesterStart!,
          );
          _semesterEnd = _cloudSemesterEnd;
          _hasCloudSemester = false;
        });
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(
            content: Text('开学/放假时间已从云端同步'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('同步失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _importingSemester = false);
    }
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;

    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey) ?? '';
    _previousShownVersion = shownVersion;
    // 仅在“更新后的第一次开屏”时优先联网，避免看到旧缓存更新日志。
    final isFirstSplashAfterUpdate =
        shownVersion.isNotEmpty && shownVersion != _currentVersion;

    try {
      final manifest = await UpdateService.checkManifest(
        preferCache: !isFirstSplashAfterUpdate,
        refreshInBackground: !isFirstSplashAfterUpdate,
      );
      if (manifest != null && mounted) {
        final changelogHistory = await _resolveChangelogHistoryForGuide(
          manifest,
          shownVersion,
          preferArchiveCache: !isFirstSplashAfterUpdate,
        );
        final showDatabaseUpdatePage = _shouldShowDatabaseUpdatePage(
          changelogHistory,
        );
        _mutateState(() {
          _changelogHistory = changelogHistory;
          _showDatabaseUpdatePage = showDatabaseUpdatePage;
          _loadingChangelog = false;
          _changelogNotice = null;
        });
        if (!_isManualReview) await _setupPages();
        return;
      }

      // 更新后首次开屏若联网失败，立即回退到离线缓存并给出提示。
      if (isFirstSplashAfterUpdate) {
        final cachedManifest = await UpdateService.checkManifest(
          preferCache: true,
          refreshInBackground: true,
        );
        if (cachedManifest != null && mounted) {
          final changelogHistory = await _resolveChangelogHistoryForGuide(
            cachedManifest,
            shownVersion,
            preferArchiveCache: true,
          );
          final showDatabaseUpdatePage = _shouldShowDatabaseUpdatePage(
            changelogHistory,
          );
          _mutateState(() {
            _changelogHistory = changelogHistory;
            _showDatabaseUpdatePage = showDatabaseUpdatePage;
            _loadingChangelog = false;
            _changelogNotice = '当前显示离线缓存更新日志，网络恢复后会自动刷新。';
          });
          if (!_isManualReview) await _setupPages();
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      _mutateState(() {
        _changelogHistory = [];
        _showDatabaseUpdatePage = false;
        _loadingChangelog = false;
        _changelogFetchFailed = true; // 🚀 标记为获取失败（通常是无网络）
        _changelogNotice = null;
      });
      if (!_isManualReview) await _setupPages();
    }
  }

  Future<List<ChangelogEntry>> _resolveChangelogHistoryForGuide(
    AppManifest manifest,
    String previousVersion, {
    required bool preferArchiveCache,
  }) async {
    final currentVersion = _normalizeVersion(_currentVersion);
    final previous = _normalizeVersion(previousVersion);
    final hasPrevious = previous.isNotEmpty;
    final isDowngrade =
        hasPrevious && _compareVersionNames(previous, currentVersion) > 0;

    final merged = <ChangelogEntry>[];
    final seen = <String>{};
    void addEntries(Iterable<ChangelogEntry> entries) {
      for (final entry in entries) {
        if (entry.versionName.isEmpty) continue;
        if (seen.add(_normalizeVersion(entry.versionName))) {
          merged.add(entry);
        }
      }
    }

    addEntries(manifest.changelogHistory);

    if (hasPrevious && !isDowngrade && manifest.changelogArchive.isAvailable) {
      try {
        final archive = await UpdateService.loadChangelogArchive(
          manifest: manifest,
          preferCache: preferArchiveCache,
        );
        addEntries(archive);
      } catch (_) {}
    }

    merged.sort((a, b) => _compareVersionNames(b.versionName, a.versionName));

    if (!hasPrevious || isDowngrade) {
      return _currentVersionOnly(merged);
    }

    final inRange = merged
        .where((entry) {
          final version = entry.versionName;
          return _compareVersionNames(version, previous) > 0 &&
              _compareVersionNames(version, currentVersion) <= 0;
        })
        .where((entry) => entry.items.isNotEmpty)
        .toList();

    return inRange.isNotEmpty ? inRange : _currentVersionOnly(merged);
  }

  List<ChangelogEntry> _currentVersionOnly(List<ChangelogEntry> entries) {
    final current = _normalizeVersion(_currentVersion);
    final currentEntries = entries
        .where((entry) => _compareVersionNames(entry.versionName, current) == 0)
        .where((entry) => entry.items.isNotEmpty)
        .take(1)
        .toList();
    if (currentEntries.isNotEmpty) return currentEntries;

    // 当前版本未发布更新日志时，展示清单中最近一个有内容的旧版本。
    return entries
        .where(
          (entry) =>
              _compareVersionNames(entry.versionName, current) < 0 &&
              entry.items.isNotEmpty,
        )
        .take(1)
        .toList();
  }

  String _normalizeVersion(String version) =>
      version.trim().split('+').first.split('-').first;

  int _compareVersionNames(String a, String b) {
    final left = _normalizeVersion(a)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final right = _normalizeVersion(b)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final maxLength = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLength; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  bool _shouldShowDatabaseUpdatePage(List<ChangelogEntry> entries) {
    const databaseKeywords = [
      '数据库',
      'sqlite',
      'sql',
      '表结构',
      '字段',
      '存储引擎',
      '数据迁移',
      '迁移至',
      'migration',
      'schema',
    ];

    for (final entry in entries) {
      for (final item in entry.items) {
        final lower = item.toLowerCase();
        if (databaseKeywords.any(lower.contains)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _loadTaiConfig() async {
    final path =
        await TaiService.getSavedDbPath() ??
        await TaiService.detectDefaultPath();
    if (path != null && mounted) {
      _mutateState(() => _taiDbPath = path);
    }
  }

  Future<void> _checkPermissions() async {
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) return;

    final notifStatus = await Permission.notification.status;

    bool hasUsage = false;
    bool hasExact = false;

    if (AppPlatform.isAndroid) {
      try {
        hasUsage =
            await _featureGuideScreenTimeChannel.invokeMethod(
              'checkUsagePermission',
            ) ??
            false;
      } catch (_) {}
      try {
        hasExact =
            await _featureGuidePlatform.invokeMethod(
              'checkExactAlarmPermission',
            ) ??
            true;
      } catch (_) {}
    } else {
      hasUsage = true;
      hasExact = true;
    }

    if (mounted) {
      _mutateState(() {
        _notificationStatus = notifStatus;
        _hasUsageStats = hasUsage;
        _hasExactAlarm = hasExact;
      });
    }
  }

  Future<void> _loadMinorModeGuideState() async {
    await MinorModeService.instance.initialize();
    final birthDate = MinorModeService.instance.manualBirthDate;
    if (mounted) {
      _mutateState(() => _minorBirthDate = birthDate);
    }
  }

  Future<void> _pickMinorBirthDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final defaultDate = DateTime(today.year - 12, today.month, today.day);
    final selected = await showAppDatePicker(
      context: context,
      initialDate: _minorBirthDate ?? defaultDate,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: '选择出生日期',
      cancelText: '暂不设置',
      confirmText: '确定',
    );
    if (selected == null || !mounted) return;

    _mutateState(() {
      _minorBirthDate = selected;
      _minorBirthDateSaving = true;
    });
    try {
      await MinorModeService.instance.setManualBirthDate(selected);
    } finally {
      if (mounted) _mutateState(() => _minorBirthDateSaving = false);
    }
  }
}
