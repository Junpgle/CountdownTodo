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
        _fetchBingWallpaper();
      } else {
        _fetchRandomWallpaper();
      }
    } else if (_wallpaperRetryCount == 2) {
      // If provider failed, try random (if not already tried)
      if (provider == 'bing') {
        _fetchRandomWallpaper();
      } else {
        _tryAnotherRandomWallpaper();
      }
    } else if (_wallpaperRetryCount >= 3 && _wallpaperRetryCount < 6) {
      // Keep trying randoms a few times
      _tryAnotherRandomWallpaper();
    } else if (_wallpaperRetryCount == 6) {
      // 🚀 Final Fallback: Local Asset
      // debugPrint("[Wallpaper] Using local asset fallback.");
      _showDefaultWallpaper();
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
    if (_randomWallpaperUrls.isEmpty) {
      _fetchRandomWallpaper();
      return;
    }

    final nextUrl = WallpaperUrlSelector.chooseAlternative(
      _randomWallpaperUrls,
      currentUrl: _wallpaperUrl,
    );
    if (nextUrl == null) {
      _showDefaultWallpaper();
      return;
    }

    if (!mounted) return;
    setState(() {
      _wallpaperDominantColor = null;
      _extractedWallpaperUrl = null;
      StorageService.setAppWallpaperColor(null);
      _wallpaperUrl = nextUrl;
    });
  }

  void _showDefaultWallpaper() {
    if (!mounted) return;
    setState(() {
      _wallpaperShow = true;
      _wallpaperDominantColor = null;
      _extractedWallpaperUrl = null;
      _wallpaperCopyright = null;
      _wallpaperRetryCount = 0;
      StorageService.setAppWallpaperColor(null);
      _wallpaperUrl = 'assets/images/default_wallpaper.webp';
      _isWallpaperLoadingError = false;
    });
  }

  Future<Map<String, String?>?> _fetchBingWallpaperFromArchive({
    required int index,
    required String mkt,
  }) async {
    final archiveUrl = Uri.https('cn.bing.com', '/HPImageArchive.aspx', {
      'format': 'js',
      'idx': index.toString(),
      'n': '1',
      'mkt': mkt,
    });

    try {
      final response = await http
          .get(archiveUrl)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['images'] is! List) return null;
      final images = payload['images'] as List;
      if (images.isEmpty || images.first is! Map) return null;

      final image = Map<String, dynamic>.from(images.first as Map);
      final rawUrl = image['url'];
      final copyright = image['copyright'];
      final imageUrl = rawUrl is String ? rawUrl.trim() : null;
      final imageCopyright = copyright is String ? copyright.trim() : null;
      if (imageUrl == null || imageUrl.isEmpty) return null;

      return {
        'url': Uri.parse('https://cn.bing.com').resolve(imageUrl).toString(),
        'copyright': imageCopyright == null || imageCopyright.isEmpty
            ? null
            : imageCopyright,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchBingWallpaper() async {
    final format = await StorageService.getWallpaperImageFormat();
    final index = await StorageService.getWallpaperIndex();
    final mkt = await StorageService.getWallpaperMkt();
    final resolution = await StorageService.getWallpaperResolution();

    final String bingApiUrl =
        "https://bing.biturl.top/?resolution=$resolution&format=json&index=$index&mkt=$mkt&image_format=$format";
    String? url;
    String? copyright;
    try {
      final response = await http
          .get(Uri.parse(bingApiUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          final rawUrl = data['url'];
          final rawCopyright = data['copyright'];
          final responseUrl = rawUrl is String ? rawUrl.trim() : null;
          final responseCopyright = rawCopyright is String
              ? rawCopyright.trim()
              : null;
          if (responseUrl != null && responseUrl.isNotEmpty) {
            url = responseUrl;
            copyright = responseCopyright == null || responseCopyright.isEmpty
                ? null
                : responseCopyright;
          }
        }
      }
    } catch (e) {
      // debugPrint("获取Bing壁纸失败: $e");
    }

    if ((url == null || copyright == null) && !AppPlatform.isWeb) {
      final archiveImage = await _fetchBingWallpaperFromArchive(
        index: index,
        mkt: mkt,
      );
      if (archiveImage != null) {
        // Both requests use the same Bing index and market. Keep the primary
        // URL (and its requested resolution) when it is already available.
        url ??= archiveImage['url'];
        copyright ??= archiveImage['copyright'];
      }
    }

    if (url != null && url.isNotEmpty && mounted) {
      setState(() {
        _wallpaperShow = true;
        _wallpaperDominantColor = null;
        StorageService.setAppWallpaperColor(null);
        _wallpaperUrl = url;
        _wallpaperCopyright = copyright;
      });
      return;
    }

    // Remote API failures do not produce an Image error callback. Always
    // advance explicitly so a fallback request cannot leave the dashboard
    // waiting on a URL that was never set.
    await _fetchRandomWallpaper();
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
    _disposeWallpaperListeners();
    _wallpaperShowListener = () {
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
    };
    _wallpaperUrlListener = () {
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
    };
    UpdateService.wallpaperShowNotifier.addListener(_wallpaperShowListener!);
    UpdateService.wallpaperUrlNotifier.addListener(_wallpaperUrlListener!);
  }

  void _disposeWallpaperListeners() {
    final showListener = _wallpaperShowListener;
    if (showListener != null) {
      UpdateService.wallpaperShowNotifier.removeListener(showListener);
      _wallpaperShowListener = null;
    }
    final urlListener = _wallpaperUrlListener;
    if (urlListener != null) {
      UpdateService.wallpaperUrlNotifier.removeListener(urlListener);
      _wallpaperUrlListener = null;
    }
  }

  Future<void> _fetchRandomWallpaper() async {
    const String repoApiUrl =
        "https://api.github.com/repos/Junpgle/math_quiz_app/contents/wallpaper";
    try {
      final response = await _githubResourceService.get(Uri.parse(repoApiUrl));
      if (response.statusCode == 200) {
        final payload = jsonDecode(response.body);
        final urls = <String>[];
        if (payload is List) {
          for (final file in payload) {
            if (file is! Map) continue;
            final name = file['name'];
            final rawUrl = file['download_url'];
            if (name is! String || rawUrl is! String) continue;
            final extension = name.toLowerCase();
            if (!extension.endsWith('.jpg') && !extension.endsWith('.png')) {
              continue;
            }
            final uri = Uri.tryParse(rawUrl.trim());
            if (uri == null ||
                (uri.scheme != 'https' && uri.scheme != 'http') ||
                uri.host.isEmpty) {
              continue;
            }
            urls.add(uri.toString());
          }
        }
        if (urls.isNotEmpty && mounted) {
          _randomWallpaperUrls = urls;
          final selectedUrl = WallpaperUrlSelector.chooseAlternative(
            urls,
            currentUrl: _wallpaperUrl,
          );
          if (selectedUrl == null) {
            _showDefaultWallpaper();
            return;
          }
          setState(() {
            _wallpaperShow = true;
            _wallpaperDominantColor = null;
            StorageService.setAppWallpaperColor(null);
            _wallpaperUrl = selectedUrl;
          });
          return;
        }
      }
    } catch (e) {
      // debugPrint("获取壁纸失败: $e");
    }
    _showDefaultWallpaper();
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
    if (!_isSearchOpen) {
      setState(() => _isSearchOpen = true);
    }
    PageTransitions.pushFromRect(
      context: context,
      page: const GlobalSearchOverlay(),
      sourceKey: _searchButtonKey,
      placeholderIcon: Icons.search_rounded,
    ).then((_) async {
      // 🚀 延迟 200ms 恢复，确保键盘收起后再允许背景重排，彻底消除跳变
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() => _isSearchOpen = false);
        _timelineRevision.value++; // 搜索历史只影响时间轴，无需重读首页全部数据。
      }
    });
  }
}
