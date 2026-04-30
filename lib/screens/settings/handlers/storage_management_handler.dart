import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import '../../../storage_service.dart';

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
    if (size <= 0) return "0 B";
    const List<String> suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = (log(size) / log(1024)).floor();
    return '${(size / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> calculateCacheSize() async {
    try {
      double size = 0;

      final tempDir = await getTemporaryDirectory();
      size += await _getTotalSizeOfFilesInDir(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      size += await _getTotalSizeOfFilesInDir(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      size += await _getPackageSizeInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          size += await _getPackageSizeInDir(extDir);
        }
      }

      onUpdateCacheSize(formatSize(size));
    } catch (e) {
      onUpdateCacheSize("未知");
    }
  }

  Future<double> _getTotalSizeOfFilesInDir(FileSystemEntity file) async {
    if (file is File) {
      try {
        return (await file.length()).toDouble();
      } catch (_) {
        return 0;
      }
    }
    if (file is Directory) {
      double total = 0;
      try {
        await for (final child in file.list()) {
          total += await _getTotalSizeOfFilesInDir(child);
        }
      } catch (e) {}
      return total;
    }
    return 0;
  }

  Future<double> _getPackageSizeInDir(Directory dir) async {
    double total = 0;
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              total += await child.length();
            }
          }
        }
      } catch (e) {}
    }
    return total;
  }

  Future<void> clearCache() async {
    showLoading("正在深度清理缓存...");

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final tempDir = await getTemporaryDirectory();
      await _deleteDirectoryContents(tempDir);

      final supportDir = await getApplicationSupportDirectory();
      await _deleteDirectoryContents(supportDir);

      final docDir = await getApplicationDocumentsDirectory();
      await _deletePackageFilesInDir(docDir);

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) await _deletePackageFilesInDir(extDir);
      }

      try {
        final tasks = await FlutterDownloader.loadTasks();
        if (tasks != null) {
          for (var task in tasks) {
            await FlutterDownloader.remove(taskId: task.taskId, shouldDeleteContent: true);
          }
        }
      } catch (e) {}
    } catch (e) {
      debugPrint("深度清理缓存失败: $e");
    } finally {
      closeLoading();
      showMessage('✅ 深度清理完成，设备空间已大幅释放！');
      await calculateCacheSize();
    }
  }

  Future<void> clearTodoHistory() async {
    final username = getUsername();
    if (username.isEmpty || username == '未登录' || username == '加载中...') {
      showMessage('请先登录后再清除待办历史记录');
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('清除待办历史记录'),
            content: const Text(
              '将彻底删除今天以前已完成的待办记录，不会删除未完成待办、今天完成的待办、回收站内容或孤儿待办。删除后会同步到其他设备，无法恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('清除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    showLoading('正在清除待办历史记录...');
    try {
      final count = await StorageService.clearHistoricalTodos(username);
      closeLoading();
      showMessage(
        count == 0 ? '没有可清除的待办历史记录' : '已清除 $count 条待办历史记录',
      );
    } catch (e) {
      closeLoading();
      showMessage('清除失败: $e');
    }
  }

  Future<void> _deleteDirectoryContents(Directory dir) async {
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list()) {
          try {
            await child.delete(recursive: true);
          } catch (e) {}
        }
      } catch (e) {}
    }
  }

  Future<void> _deletePackageFilesInDir(Directory dir) async {
    if (dir.existsSync()) {
      try {
        await for (var child in dir.list(recursive: true)) {
          if (child is File) {
            String name = child.path.toLowerCase();
            if (name.endsWith('.apk') || name.endsWith('.exe')) {
              try {
                await child.delete();
              } catch (e) {}
            }
          }
        }
      } catch (e) {}
    }
  }

  Future<void> showStorageAnalysis() async {
    showLoading("正在分析存储空间...");

    List<Map<String, dynamic>> allFiles = [];
    Map<String, double> dirSizes = {
      '沙盒真实根目录 (App Root)': 0,
      '外部存储 (External)': 0,
    };

    Future<void> scanDirectory(Directory? dir, String dirName) async {
      if (dir == null || !dir.existsSync()) return;
      try {
        double totalSize = 0;
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final size = await entity.length();
              totalSize += size;
              if (size > 50 * 1024) {
                allFiles.add({
                  'path': entity.path,
                  'size': size,
                  'file': entity,
                });
              }
            } catch (e) {}
          }
        }
        dirSizes[dirName] = totalSize;
      } catch (e) {}
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final rootDir = docDir.parent;

      await scanDirectory(rootDir, '沙盒真实根目录 (App Root)');

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) await scanDirectory(extDir, '外部存储 (External)');
      }

      allFiles.sort((a, b) => b['size'].compareTo(a['size']));
      final topFiles = allFiles.take(100).toList();

      closeLoading();
      _showFilesDialog(topFiles, dirSizes);
    } catch (e) {
      closeLoading();
      showMessage('扫描失败: $e');
    }
  }

  void _showFilesDialog(List<Map<String, dynamic>> topFiles, Map<String, double> dirSizes) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('空间占用深度分析', style: TextStyle(fontSize: 18)),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("📁 目录总览:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...dirSizes.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: const TextStyle(fontSize: 13)),
                              Text(formatSize(e.value),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        )),
                    const Divider(height: 24),
                    const Text("📄 Top 100 大文件 (点击垃圾桶可直删):", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: topFiles.isEmpty
                          ? const Center(child: Text("未发现大于 50KB 的文件"))
                          : ListView.separated(
                              itemCount: topFiles.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final fileInfo = topFiles[index];
                                final path = fileInfo['path'] as String;
                                final size = fileInfo['size'] as int;
                                final fileName = path.split('/').last;
                                final File file = fileInfo['file'] as File;

                                bool isCore = path.contains('flutter_assets') ||
                                    path.endsWith('.db') ||
                                    path.contains('shared_prefs') ||
                                    path.contains('databases');

                                return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                        isCore ? Icons.warning_amber_rounded : Icons.insert_drive_file,
                                        color: isCore ? Colors.orange : Colors.grey),
                                    title: Text(
                                      fileName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isCore ? Colors.orange : null),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(path,
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text(formatSize(size.toDouble()),
                                          style: const TextStyle(
                                              color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                      IconButton(
                                          padding: const EdgeInsets.only(left: 8),
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(Icons.delete_outline, size: 20),
                                          onPressed: () async {
                                            if (isCore) {
                                              showMessage('⚠️ 这个是应用运行核心文件或你的用户数据库，禁止删除！');
                                              return;
                                            }
                                            try {
                                              if (await file.exists()) {
                                                await file.delete();
                                                setDialogState(() {
                                                  topFiles.removeAt(index);
                                                });
                                                showMessage('✅ 文件已删除');
                                              }
                                            } catch (e) {
                                              showMessage('删除失败: $e');
                                            }
                                          })
                                    ]));
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
              ],
            );
          },
        );
      },
    );
  }
}
