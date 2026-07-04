import 'dart:math';

import 'package:flutter/material.dart';

class StorageManagementHandler {
  final BuildContext context;
  final String Function() getUsername;
  final Function(String) onUpdateCacheSize;
  final Function(String) showLoading;
  final VoidCallback closeLoading;
  final Function(String) showMessage;

  StorageManagementHandler({
    required this.context,
    required this.getUsername,
    required this.onUpdateCacheSize,
    required this.showLoading,
    required this.closeLoading,
    required this.showMessage,
  });

  String formatSize(double size) {
    if (size <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(size) / log(1024)).floor();
    return '${(size / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> calculateCacheSize() async {
    onUpdateCacheSize('浏览器管理');
  }

  Future<void> clearCache() async {
    showLoading('正在清理运行缓存...');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    closeLoading();
    showMessage('✅ 已清理当前页面图片缓存；浏览器存储请在浏览器设置中管理');
    await calculateCacheSize();
  }

  Future<void> showStorageAnalysis() async {
    showMessage('Web 端存储由浏览器沙盒管理，暂不支持文件级分析');
  }
}
