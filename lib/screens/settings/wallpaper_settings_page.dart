import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../storage_service.dart';

class WallpaperSettingsPage extends StatefulWidget {
  const WallpaperSettingsPage({super.key});

  @override
  State<WallpaperSettingsPage> createState() => _WallpaperSettingsPageState();
}

class _WallpaperSettingsPageState extends State<WallpaperSettingsPage> {
  String _provider = 'bing';
  String _format = 'jpg';
  int _index = 0;
  String _mkt = 'zh-CN';
  String _resolution = '1920';
  String? _customWallpaperPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final provider = await StorageService.getWallpaperProvider();
    final format = await StorageService.getWallpaperImageFormat();
    final index = await StorageService.getWallpaperIndex();
    final mkt = await StorageService.getWallpaperMkt();
    final resolution = await StorageService.getWallpaperResolution();
    final customPath = await StorageService.getWallpaperCustomPath();

    if (mounted) {
      setState(() {
        _provider = provider;
        _format = format;
        _index = index;
        _mkt = mkt;
        _resolution = resolution;
        _customWallpaperPath = customPath;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickCustomWallpaper() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 3840,
      maxHeight: 3840,
    );
    if (pickedFile == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪壁纸',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: '裁剪壁纸',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          boundary: const CroppieBoundary(width: 800, height: 450),
          viewPort: const CroppieViewPort(width: 768, height: 432, type: 'rectangle'),
        ),
        WindowsUiSettings(
          title: '裁剪壁纸',
        ),
      ],
    );
    if (croppedFile == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final wallpaperDir = Directory(p.join(appDir.path, 'wallpaper'));
    if (!await wallpaperDir.exists()) {
      await wallpaperDir.create(recursive: true);
    }

    final fileName = 'custom_wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = p.join(wallpaperDir.path, fileName);
    await File(croppedFile.path).copy(savedPath);

    if (_customWallpaperPath != null) {
      try {
        final oldFile = File(_customWallpaperPath!);
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    }

    await StorageService.saveWallpaperCustomPath(savedPath);
    if (mounted) {
      setState(() {
        _customWallpaperPath = savedPath;
      });
    }
  }

  Future<void> _clearCustomWallpaper() async {
    if (_customWallpaperPath != null) {
      try {
        final oldFile = File(_customWallpaperPath!);
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    }
    await StorageService.clearWallpaperCustomPath();
    if (mounted) {
      setState(() {
        _customWallpaperPath = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('壁纸设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('壁纸设置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildSectionTitle('基本设置'),
          ListTile(
            leading: const Icon(Icons.source_outlined, color: Colors.deepPurple),
            title: const Text('壁纸来源'),
            subtitle: const Text('GitHub: 随机仓库壁纸 | Bing: 必应每日一图 | 自定义: 本地图片'),
            trailing: DropdownButton<String>(
              value: _provider,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'github', child: Text('GitHub 随机')),
                DropdownMenuItem(value: 'bing', child: Text('Bing 每日一图')),
                DropdownMenuItem(value: 'custom', child: Text('自定义壁纸')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _provider = val);
                  StorageService.saveWallpaperProvider(val);
                }
              },
            ),
          ),
          if (_provider == 'custom') ...[
            const Divider(height: 1, indent: 56),
            _buildCustomWallpaperSection(),
          ],
          if (_provider == 'bing') ...[
            const Divider(height: 1, indent: 56),
            _buildSectionTitle('必应选项'),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Colors.deepPurple),
              title: const Text('图片格式'),
              trailing: DropdownButton<String>(
                value: _format,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'jpg', child: Text('JPG')),
                  DropdownMenuItem(value: 'webp', child: Text('WebP')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _format = val);
                    StorageService.saveWallpaperImageFormat(val);
                  }
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.deepPurple),
              title: const Text('壁纸索引'),
              subtitle: const Text('0为今日，1为昨日...'),
              trailing: DropdownButton<int>(
                value: _index,
                underline: const SizedBox(),
                items: List.generate(
                    8,
                    (i) => DropdownMenuItem(
                        value: i, child: Text(i == 0 ? '今日' : '$i 天前'))),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _index = val);
                    StorageService.saveWallpaperIndex(val);
                  }
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.language_outlined, color: Colors.deepPurple),
              title: const Text('地区/语言'),
              trailing: DropdownButton<String>(
                value: _mkt,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'zh-CN', child: Text('中国 (简体)')),
                  DropdownMenuItem(value: 'en-US', child: Text('美国 (英语)')),
                  DropdownMenuItem(value: 'ja-JP', child: Text('日本 (日语)')),
                  DropdownMenuItem(value: 'en-AU', child: Text('澳大利亚')),
                  DropdownMenuItem(value: 'en-GB', child: Text('英国')),
                  DropdownMenuItem(value: 'de-DE', child: Text('德国')),
                  DropdownMenuItem(value: 'en-NZ', child: Text('新西兰')),
                  DropdownMenuItem(value: 'en-CA', child: Text('加拿大')),
                  DropdownMenuItem(value: 'en-IN', child: Text('印度')),
                  DropdownMenuItem(value: 'fr-FR', child: Text('法国')),
                  DropdownMenuItem(value: 'fr-CA', child: Text('加拿大 (法语)')),
                  DropdownMenuItem(value: 'it-IT', child: Text('意大利')),
                  DropdownMenuItem(value: 'es-ES', child: Text('西班牙')),
                  DropdownMenuItem(value: 'pt-BR', child: Text('巴西')),
                  DropdownMenuItem(value: 'en-ROW', child: Text('全球其他地区')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _mkt = val);
                    StorageService.saveWallpaperMkt(val);
                  }
                },
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.monitor_outlined, color: Colors.deepPurple),
              title: const Text('分辨率'),
              trailing: DropdownButton<String>(
                value: _resolution,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: '1366', child: Text('1366x768')),
                  DropdownMenuItem(value: '1920', child: Text('1080P')),
                  DropdownMenuItem(value: '3840', child: Text('4K (3840)')),
                  DropdownMenuItem(value: 'UHD', child: Text('超高清 (UHD)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _resolution = val);
                    StorageService.saveWallpaperResolution(val);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomWallpaperSection() {
    final hasCustom = _customWallpaperPath != null &&
        File(_customWallpaperPath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('自定义壁纸'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: hasCustom
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_customWallpaperPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildPlaceholder(),
                        ),
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: const Center(
                              child: Icon(
                                Icons.touch_app,
                                color: Colors.white70,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildPlaceholder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickCustomWallpaper,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(hasCustom ? '更换壁纸' : '选择壁纸'),
                ),
              ),
              if (hasCustom) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _clearCustomWallpaper,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清除'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '自定义壁纸将从本地加载，不会联网获取。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wallpaper,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无自定义壁纸',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor.withValues(alpha: 0.8),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
