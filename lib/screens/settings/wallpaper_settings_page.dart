import 'package:flutter/material.dart';
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

    if (mounted) {
      setState(() {
        _provider = provider;
        _format = format;
        _index = index;
        _mkt = mkt;
        _resolution = resolution;
        _isLoading = false;
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
            subtitle: const Text('GitHub: 随机仓库壁纸 | Bing: 必应每日一图'),
            trailing: DropdownButton<String>(
              value: _provider,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'github', child: Text('GitHub 随机')),
                DropdownMenuItem(value: 'bing', child: Text('Bing 每日一图')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _provider = val);
                  StorageService.saveWallpaperProvider(val);
                }
              },
            ),
          ),
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
