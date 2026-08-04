part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardWallpaperMixin on _HomeDashboardStateBase {
  bool _isLocalFilePath(String path) {
    return !path.startsWith('http://') &&
        !path.startsWith('https://') &&
        !path.startsWith('assets/');
  }

  void _handleWallpaperError() {
    if (!mounted || _isWallpaperLoadingError) return;
    // debugPrint(
    //     "[Wallpaper] Current URL failed: $_wallpaperUrl. Trying fallback...");

    setState(() {
      _wallpaperRetryCount++;
    });

    _triggerNextWallpaperFallback();
  }

  Future<void> _triggerNextWallpaperFallback() async {
    // Priority: Manifest -> Bing -> Random List -> Asset Fallback -> None
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('wallpaper_provider') ?? 'bing';

    // 自定义壁纸模式：不执行任何 fallback
    if (provider == 'custom') return;

    if (_wallpaperRetryCount == 1) {
      // If manifest failed (or was first), try provider
      if (provider == 'bing') {
        _fetchBingWallpaper(isFallback: true);
      } else {
        _fetchRandomWallpaper(isFallback: true);
      }
    } else if (_wallpaperRetryCount == 2) {
      // If provider failed, try random (if not already tried)
      if (provider == 'bing') {
        _fetchRandomWallpaper(isFallback: true);
      } else {
        _tryAnotherRandomWallpaper();
      }
    } else if (_wallpaperRetryCount >= 3 && _wallpaperRetryCount < 6) {
      // Keep trying randoms a few times
      _tryAnotherRandomWallpaper();
    } else if (_wallpaperRetryCount == 6) {
      // 🚀 Final Fallback: Local Asset
      // debugPrint("[Wallpaper] Using local asset fallback.");
      if (mounted) {
        setState(() {
          _wallpaperDominantColor = null;
          _extractedWallpaperUrl = null;
          StorageService.setAppWallpaperColor(null);
          _wallpaperUrl = 'assets/images/default_wallpaper.webp';
          _isWallpaperLoadingError = false; // Reset to allow this to show
        });
      }
    } else {
      // Total failure
      // debugPrint("[Wallpaper] All fallbacks exhausted. Disabling wallpaper.");
      if (mounted) {
        setState(() {
          _wallpaperShow = false;
          _isWallpaperLoadingError = true;
        });
      }
    }
  }

  void _tryAnotherRandomWallpaper() {
    if (_randomWallpaperUrls.isNotEmpty) {
      final nextUrl =
          _randomWallpaperUrls[Random().nextInt(_randomWallpaperUrls.length)];
      if (mounted) {
        setState(() {
          _wallpaperDominantColor = null;
          _extractedWallpaperUrl = null;
          StorageService.setAppWallpaperColor(null);
          _wallpaperUrl = nextUrl;
        });
      }
    } else {
      _fetchRandomWallpaper(isFallback: true);
    }
  }

  Future<void> _fetchBingWallpaper({bool isFallback = false}) async {
    final format = await StorageService.getWallpaperImageFormat();
    final index = await StorageService.getWallpaperIndex();
    final mkt = await StorageService.getWallpaperMkt();
    final resolution = await StorageService.getWallpaperResolution();

    final String bingApiUrl =
        "https://bing.biturl.top/?resolution=$resolution&format=json&index=$index&mkt=$mkt&image_format=$format";
    try {
      final response = await http.get(Uri.parse(bingApiUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? url = data['url'];
        final String? copyright = data['copyright'];
        if (url != null && url.isNotEmpty && mounted) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = url;
            _wallpaperCopyright = copyright;
          });
        }
      } else {
        // 失败兜底
        _fetchRandomWallpaper();
      }
    } catch (e) {
      // debugPrint("获取Bing壁纸失败: $e");
      if (!isFallback) _fetchRandomWallpaper();
    }
  }

  Future<void> _initManifestWallpaper() async {
    _setupWallpaperListeners();
    await _refreshWallpaper();
  }

  void _onWallpaperRefresh() {
    if (mounted) _refreshWallpaper();
  }

  Future<void> _refreshWallpaper() async {
    final provider = await StorageService.getWallpaperProvider();

    // 自定义壁纸模式：直接从本地加载，跳过所有网络逻辑和 manifest 推送
    if (provider == 'custom') {
      final customPath = await StorageService.getWallpaperCustomPath();
      if (customPath != null && customPath.isNotEmpty) {
        if (localImageExists(customPath) && mounted) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            _extractedWallpaperUrl = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = customPath;
            _isWallpaperLoadingError = false;
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          _wallpaperShow = false;
          _wallpaperDominantColor = null;
          _extractedWallpaperUrl = null;
          StorageService.setAppWallpaperColor(null);
          _wallpaperUrl = null;
          _isWallpaperLoadingError = true;
        });
      }
      return;
    }

    await WallpaperCacheService.cleanupIfNeeded();
    await UpdateService.initWallpaper();
    final manifestShow = UpdateService.wallpaperShowNotifier.value;
    final manifestUrl = UpdateService.wallpaperUrlNotifier.value;

    if (manifestShow && manifestUrl != null && manifestUrl.isNotEmpty) {
      setState(() {
        _wallpaperShow = true;
        _wallpaperDominantColor = null;
        StorageService.setAppWallpaperColor(null);
        _wallpaperUrl = manifestUrl;
        _wallpaperRetryCount = 0;
        _isWallpaperLoadingError = false;
      });
    } else {
      if (provider == 'bing') {
        await _fetchBingWallpaper();
      } else {
        await _fetchRandomWallpaper();
      }
    }

    // 启动时立即检查是否需要兜底刷新
    if (await UpdateService.needsWallpaperRefresh()) {
      UpdateService.updateWallpaperFromManifest();
    }
  }

  void _setupWallpaperListeners() {
    UpdateService.wallpaperShowNotifier.addListener(() {
      if (mounted) {
        final show = UpdateService.wallpaperShowNotifier.value;
        final url = UpdateService.wallpaperUrlNotifier.value;
        if (show && url != null && url.isNotEmpty) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = url;
            _wallpaperRetryCount = 0;
            _isWallpaperLoadingError = false;
          });
        } else if (mounted) {
          StorageService.getWallpaperProvider().then((provider) {
            if (provider == 'bing') {
              _fetchBingWallpaper();
            } else {
              _fetchRandomWallpaper();
            }
          });
        }
      }
    });
    UpdateService.wallpaperUrlNotifier.addListener(() {
      if (mounted) {
        final show = UpdateService.wallpaperShowNotifier.value;
        final url = UpdateService.wallpaperUrlNotifier.value;
        if (show && url != null && url.isNotEmpty) {
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = url;
          });
        }
      }
    });
  }

  Future<void> _fetchRandomWallpaper({bool isFallback = false}) async {
    const String repoApiUrl =
        "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await _githubResourceService.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        List<dynamic> files = jsonDecode(response.body);
        List<String> urls = files
            .where((f) =>
                f['name'].toString().toLowerCase().endsWith('.jpg') ||
                f['name'].toString().toLowerCase().endsWith('.png'))
            .map((f) => f['download_url'].toString())
            .toList();
        if (urls.isNotEmpty && mounted) {
          _randomWallpaperUrls = urls;
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = urls[Random().nextInt(urls.length)];
          });
        }
      }
    } catch (e) {
      // debugPrint("获取壁纸失败: $e");
    }
  }

  Widget _buildSemesterProgressBar(bool isLight) {
    if (!_semesterEnabled || _semesterStart == null || _semesterEnd == null) {
      return const SizedBox.shrink();
    }

    double progress = _calculateSemesterProgress();

    return Container(
      width: double.infinity,
      height: 4.0,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: isLight
                ? Colors.lightBlueAccent
                : Theme.of(context).colorScheme.primary,
            boxShadow: [
              if (progress > 0)
                BoxShadow(
                  color: (isLight
                          ? Colors.lightBlueAccent
                          : Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
            ],
          ),
        ),
      ),
    );
  }

  void _showGlobalSearch() {
    PageTransitions.pushFromRect(
      context: context,
      page: const GlobalSearchOverlay(),
      sourceKey: _searchButtonKey,
    ).then((_) async {
      // 🚀 延迟 200ms 恢复，确保键盘收起后再允许背景重排，彻底消除跳变
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _isSearchOpen = false;
          _timelineRevision.value++; // 🚀 搜索完成后刷新时间轴（记录搜索历史）
        });
      }
      _loadAllData(deferred: true);
    });
  }
}
