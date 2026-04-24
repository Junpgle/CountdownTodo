import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_service.dart';
import '../storage_service.dart';
import 'llm_service.dart';
import 'notification_service.dart';

class ExternalShareHandler {
  static StreamSubscription? _intentDataStreamSubscription;
  static bool _isProcessing = false;
  static final List<String> _processedFileKeys = [];
  static const int _maxProcessedKeys = 10;

  /// 初始化监听，放在主页的 initState 中调用
  /// [onCourseImported] 课表导入成功回调
  /// [onTodoRecognized] 图片识别待办回调，传入识别结果列表和图片路径
  static void init(
    BuildContext context,
    Function onCourseImported, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _intentDataStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized, fromInitial: false);
      },
      onError: (err) {
        debugPrint("获取外部意图失败: $err");
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized, fromInitial: true);
      },
    );
  }

  static void _processSharedFiles(
    BuildContext context,
    List<SharedMediaFile> files,
    Function onSuccess, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    bool fromInitial = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (files.isEmpty || _isProcessing) return;
    _isProcessing = true;

    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) {
      _isProcessing = false;
      return;
    }

    ValueNotifier<String> statusNotifier = ValueNotifier("处理中...");
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, value, child) {
                    return Text(
                      value,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 400));

      String filePath = files.first.path;
      File file = File(filePath);
      String ext = filePath.split('.').last.toLowerCase();

      // 生成文件唯一标识并检查是否已处理（仅对getInitialMedia去重，防止重复处理）
      final fileKey = await _generateFileKey(filePath);
      if (fromInitial && await _isFileProcessed(fileKey)) {
        debugPrint("文件已处理过，跳过: $filePath");
        _closeDialogSafely(dialogContext);
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
        return;
      }

      // 检测是否为图片
      final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      final isImage = imageExtensions.contains(ext);

      if (isImage) {
        // 图片处理：调用大模型识别待办
        statusNotifier.value = "识别到图片\n正在压缩图片...";

        final config = await LLMService.getConfig();
        if (config == null || !config.isConfigured) {
          statusNotifier.value = "⚠️ 需要配置大模型API\n请在设置中配置后重试";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        // 立即显示进度通知上岛
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: 1,
          maxAttempts: 1,
          status: '正在识别图片...',
        );

        // 检查原始图片大小
        final fileSize = await file.length();
        if (fileSize > 20 * 1024 * 1024) {
          statusNotifier.value = "⚠️ 图片太大\n请分享小于20MB的图片";
          await NotificationService.cancelTodoRecognizeNotification();
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        // 压缩图片
        String compressedPath = await _compressImage(filePath);

        final compressedFile = File(compressedPath);
        final compressedSize = await compressedFile.length();
        statusNotifier.value =
            "图片已压缩 (${(compressedSize / 1024).toStringAsFixed(0)}KB)\n正在调用大模型分析...";

        // 更新通知状态
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: 1,
          maxAttempts: 1,
          status: '正在分析图片...',
        );

        try {
          final results = await LLMService.parseTodoFromImage(compressedPath)
              .timeout(const Duration(seconds: 90));

          statusNotifier.value = "✅ 识别成功！\n发现${results.length}个待办事项";
          // 标记文件为已处理，防止重复处理
          await _markFileProcessed(fileKey);
          await Future.delayed(const Duration(milliseconds: 800));
          _closeDialogSafely(dialogContext);

          // 显示成功通知
          await NotificationService.showTodoRecognizeSuccess(
            todoCount: results.length,
          );

          if (onTodoRecognized != null && results.isNotEmpty) {
            // 传递原始图片路径（用于显示缩略图）
            onTodoRecognized(results, filePath);
          }
        } catch (e) {
          debugPrint("大模型图片识别失败: $e");
          String errorMsg = e.toString();

          // 获取重试次数
          final maxRetries = await StorageService.getLLMRetryCount();

          if (maxRetries > 0) {
            // 有重试次数，启动后台重试
            statusNotifier.value = "首次识别失败\n正在后台重试...";
            await Future.delayed(const Duration(milliseconds: 500));
            _closeDialogSafely(dialogContext);

            // 在后台启动重试任务
            _startBackgroundRetry(
              filePath: filePath,
              compressedPath: compressedPath,
              fileKey: fileKey,
              maxRetries: maxRetries,
              onTodoRecognized: onTodoRecognized,
            );
          } else {
            // 没有重试次数，直接显示错误
            if (errorMsg.contains('TimeoutException')) {
              statusNotifier.value = "❌ 请求超时\n请检查网络或稍后重试";
            } else if (errorMsg.contains('SocketException')) {
              statusNotifier.value = "❌ 网络连接失败\n请检查网络设置";
            } else {
              statusNotifier.value =
                  "❌ 图片识别失败\n${errorMsg.length > 50 ? errorMsg.substring(0, 50) : errorMsg}";
            }
            // 显示失败通知
            await NotificationService.showTodoRecognizeFailed(
              errorMsg: errorMsg,
            );
            await Future.delayed(const Duration(seconds: 3));
            _closeDialogSafely(dialogContext);
          }
        }
      } else {
        // 文件处理：课表导入
        statusNotifier.value = "获取课表文件中...";

        String content = await _safeReadFile(file);
        final username = await StorageService.getLoginSession();
        if (username == null || username.isEmpty) {
          statusNotifier.value = "❌ 未登录\n请先登录后再导入课表";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        await Future.delayed(const Duration(milliseconds: 400));

        bool success = false;
        String sourceName = "";

        if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
          sourceName = "西安电子科技大学";
          statusNotifier.value = "识别到: $sourceName\n正在导入...";

          DateTime? semStart = await StorageService.getSemesterStart();
          if (semStart == null) {
            statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
            await Future.delayed(const Duration(seconds: 2));
            _closeDialogSafely(dialogContext);
            return;
          }
          success = await CourseService.importXidianScheduleFromIcs(
              username, content, semStart);
        } else if (content.contains('timetable_con') ||
            content.contains('id="table1"')) {
          sourceName = "正方教务系统";
          statusNotifier.value = "识别到: $sourceName\n正在深度解析...";

          DateTime? semStart = await StorageService.getSemesterStart();
          if (semStart == null) {
            statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
            await Future.delayed(const Duration(seconds: 2));
            _closeDialogSafely(dialogContext);
            return;
          }
          success = await CourseService.importZfSoftScheduleFromHtml(
              username, content, semStart);
        } else if (['mhtml', 'html', 'htm'].contains(ext) ||
            content.contains('quoted-printable') ||
            content.toLowerCase().contains('<html')) {
          sourceName = "厦门大学";
          statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

          DateTime? semStart = await StorageService.getSemesterStart();
          if (semStart == null) {
            statusNotifier.value = "⚠️ 导入中断\n请先在设置中配置【开学日期】";
            await Future.delayed(const Duration(seconds: 2));
            _closeDialogSafely(dialogContext);
            return;
          }
          success =
              await CourseService.importXmuScheduleFromHtml(username, content, semStart);
        } else if (['json', 'txt'].contains(ext) ||
            content.trim().startsWith('[') ||
            content.trim().startsWith('{')) {
          sourceName = "聚在工大";
          statusNotifier.value = "识别到: $sourceName\n正在导入...";
          success = await CourseService.importScheduleFromJson(username, content);
        } else {
          statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
          return;
        }

        if (success) {
          statusNotifier.value = "✅ 导入成功！\n正在刷新课表...";
          // 标记文件为已处理，防止重复处理
          await _markFileProcessed(fileKey);
          await Future.delayed(const Duration(milliseconds: 800));
          _closeDialogSafely(dialogContext);
          onSuccess();
        } else {
          statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
          await Future.delayed(const Duration(seconds: 2));
          _closeDialogSafely(dialogContext);
        }
      }
    } catch (e) {
      debugPrint("处理外部共享文件崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      _closeDialogSafely(dialogContext);
    } finally {
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
    }
  }

  /// 压缩图片，返回压缩后的文件路径
  static Future<String> _compressImage(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      inputPath,
      targetPath,
      quality: 80,
      minWidth: 1024,
      minHeight: 1024,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      // 压缩失败，返回原路径
      return inputPath;
    }

    return result.path;
  }

  static void _closeDialogSafely(BuildContext? dialogContext) {
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }

  static Future<String> _safeReadFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      List<int> bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 生成文件唯一标识（路径 + 修改时间 + 大小）
  static Future<String> _generateFileKey(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return filePath;
      final stat = await file.stat();
      return '${filePath}_${stat.modified.millisecondsSinceEpoch}_${stat.size}';
    } catch (e) {
      return filePath;
    }
  }

  /// 检查文件是否已处理过（持久化存储）
  static Future<bool> _isFileProcessed(String fileKey) async {
    // 先检查内存缓存
    if (_processedFileKeys.contains(fileKey)) return true;

    // 检查持久化存储
    try {
      final prefs = await SharedPreferences.getInstance();
      final processedKeys = prefs.getStringList('processed_file_keys') ?? [];
      return processedKeys.contains(fileKey);
    } catch (e) {
      return false;
    }
  }

  /// 标记文件为已处理（持久化存储）
  static Future<void> _markFileProcessed(String fileKey) async {
    // 更新内存缓存
    _processedFileKeys.add(fileKey);
    while (_processedFileKeys.length > _maxProcessedKeys) {
      _processedFileKeys.removeAt(0);
    }

    // 持久化存储
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> processedKeys =
          prefs.getStringList('processed_file_keys') ?? [];
      processedKeys.add(fileKey);
      // 限制列表大小
      while (processedKeys.length > _maxProcessedKeys) {
        processedKeys.removeAt(0);
      }
      await prefs.setStringList('processed_file_keys', processedKeys);
    } catch (e) {
      debugPrint("持久化存储已处理文件失败: $e");
    }
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  /// 启动后台重试任务
  /// [filePath] 原始图片路径
  /// [compressedPath] 压缩后的图片路径
  /// [fileKey] 文件唯一标识
  /// [maxRetries] 最大重试次数
  /// [onTodoRecognized] 识别成功回调
  static void _startBackgroundRetry({
    required String filePath,
    required String compressedPath,
    required String fileKey,
    required int maxRetries,
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
  }) async {
    debugPrint("启动后台重试: filePath=$filePath, maxRetries=$maxRetries");

    // 显示开始重试的通知
    await NotificationService.showTodoRecognizeProgress(
      currentAttempt: 1,
      maxAttempts: maxRetries + 1,
      status: '开始后台重试...',
    );

    bool success = false;
    List<Map<String, dynamic>>? results;
    String? lastError;

    // 尝试原始图片和压缩后的图片
    final pathsToTry = [compressedPath];
    if (compressedPath != filePath) {
      pathsToTry.add(filePath);
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint("后台重试第$attempt次...");

        // 更新进度通知
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          status: '正在分析图片...',
        );

        // 尝试不同的图片路径
        final currentPath = pathsToTry[(attempt - 1) % pathsToTry.length];

        // 增加超时时间到 180 秒，提高后台识别成功率
        results = await LLMService.parseTodoFromImage(currentPath)
            .timeout(const Duration(seconds: 180));

        success = true;
        debugPrint("后台重试第$attempt次成功!");
        break;
      } catch (e) {
        lastError = e.toString();
        debugPrint("后台重试第$attempt次失败: $e");

        // 更新失败通知
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          status: '第$attempt次失败，准备重试...',
        );

        // 如果不是最后一次，等待更长时间再重试（指数退避）
        if (attempt < maxRetries) {
          final waitSeconds = 5 * attempt; // 增加等待时间
          debugPrint("等待$waitSeconds秒后重试...");
          await Future.delayed(Duration(seconds: waitSeconds));
        }
      }
    }

    if (success && results != null && results.isNotEmpty) {
      // 标记文件为已处理
      await _markFileProcessed(fileKey);

      // 保存待确认数据
      await StorageService.savePendingTodoConfirm(
        imagePath: filePath,
        results: results,
      );

      // 发送成功通知
      await NotificationService.showTodoRecognizeSuccess(
        todoCount: results.length,
      );

      debugPrint("后台重试成功，已保存${results.length}个待办，等待用户确认");
    } else {
      // 所有重试都失败
      await NotificationService.showTodoRecognizeFailed(
        errorMsg: lastError ?? '未知错误',
      );

      debugPrint("后台重试全部失败: $lastError");
    }
  }

  /// 检查是否有待确认的待办数据
  /// 返回 null 表示没有待确认数据
  static Future<Map<String, dynamic>?> getPendingTodoConfirm() async {
    return await StorageService.getPendingTodoConfirm();
  }

  /// 清除待确认的待办数据
  static Future<void> clearPendingTodoConfirm() async {
    await StorageService.clearPendingTodoConfirm();
  }
}
