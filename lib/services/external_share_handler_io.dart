import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_service.dart';
import 'external_share_payload_classifier.dart';
import '../storage_service.dart';
import '../models.dart';
import '../models/chat_message.dart';
import '../features/finance/models/finance_models.dart';
import '../features/finance/services/finance_text_parser.dart';
import 'llm_service.dart';
import 'notification_service.dart';
import 'reminder_schedule_service.dart';
import 'recognized_todo_adapter.dart';
import 'todo_recognition_state.dart';
import 'ai_recognition_chat_bridge.dart';
import '../utils/persistent_image_storage.dart';
import '../course_import/course_import_preflight.dart';
import '../course_import/handlers/course_import_handler.dart';
import '../course_import/widgets/course_time_repair_dialog.dart';
import '../course_import/widgets/zf_time_config_dialog.dart';

class ExternalShareHandler {
  static StreamSubscription? _intentDataStreamSubscription;
  static bool _isProcessing = false;
  static final List<String> _processedFileKeys = [];
  static final Set<String> _processingFileKeys = <String>{};
  static const int _maxProcessedKeys = 50;
  static final String _recognitionSessionId =
      'recognition_${DateTime.now().microsecondsSinceEpoch}';

  /// 初始化监听，放在主页的 initState 中调用
  /// [onCourseImported] 课表导入成功回调
  /// [onTodoRecognized] 图片识别事项回调，传入识别结果列表和图片路径
  static void init(
    BuildContext context,
    Function onCourseImported, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    FutureOr<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final previousSubscription = _intentDataStreamSubscription;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }

    _intentDataStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (!context.mounted) return;
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized,
            onFinanceRecognized: onFinanceRecognized,
            fromInitial: false);
      },
      onError: (err) {
        // debugPrint("获取外部意图失败: $err");
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (!context.mounted) return;
        _processSharedFiles(context, value, onCourseImported,
            onTodoRecognized: onTodoRecognized,
            onFinanceRecognized: onFinanceRecognized,
            fromInitial: true);
      },
    );
  }

  static void _processSharedFiles(
    BuildContext context,
    List<SharedMediaFile> files,
    Function onSuccess, {
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    FutureOr<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
    bool fromInitial = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (files.isEmpty || _isProcessing) return;
    _isProcessing = true;

    await Future.delayed(const Duration(milliseconds: 500));

    final media = files.first;
    final firstPath = media.path.trim();
    final requestedMode = ExternalSharePayloadClassifier.modeFor(media);
    bool isInlineText;
    try {
      isInlineText = await ExternalSharePayloadClassifier.isInlineText(media)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法读取分享内容，请重试: $error')),
        );
      }
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
      return;
    }
    final isSharedText = requestedMode == ExternalShareMode.financeImport
        ? isInlineText
        : requestedMode == ExternalShareMode.automatic && isInlineText;
    if (isSharedText) {
      try {
        final text = _sharedTextPayload(media);
        final drafts = text == null
            ? const <FinanceEntryDraft>[]
            : FinanceTextParser.parse(
                text,
                source: FinanceEntrySource.import,
              );
        if (drafts.isNotEmpty && context.mounted) {
          await onFinanceRecognized?.call(drafts, null);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未识别到符合格式的记账文本')),
          );
        }
      } finally {
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
      }
      return;
    }

    final hasExplicitFileMode = requestedMode != ExternalShareMode.automatic;
    final isValidFile = firstPath.isNotEmpty &&
        (hasExplicitFileMode ||
            firstPath.contains('.') ||
            media.type == SharedMediaType.image ||
            media.mimeType?.toLowerCase().startsWith('image/') == true) &&
        !firstPath.startsWith('countdowntodo://');
    if (!isValidFile) {
      // debugPrint('ExternalShareHandler: skip non-file intent: $firstPath');
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
      return;
    }

    if (!context.mounted) {
      _isProcessing = false;
      return;
    }

    String filePath = firstPath;
    final ext = filePath.split('.').last.toLowerCase();
    const imageExtensions = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'heic',
      'heif',
      'avif',
      'tif',
      'tiff',
    };
    final isImage = requestedMode == ExternalShareMode.imageRecognition ||
        (requestedMode == ExternalShareMode.automatic &&
            (media.type == SharedMediaType.image ||
                imageExtensions.contains(ext) ||
                media.mimeType?.toLowerCase().startsWith('image/') == true));
    final isFinanceImport = requestedMode == ExternalShareMode.financeImport;
    final needsCourseImport = !isImage && !isFinanceImport;

    // 图片分享走识图流程，不需要课表学期；其余文件在任何读取、去重和
    // 解析之前先完成登录与目标学期校验。
    SemesterInfo? targetSemester;
    String? courseUsername;
    if (needsCourseImport) {
      try {
        courseUsername = await StorageService.getLoginSession();
        if (!context.mounted) {
          _isProcessing = false;
          return;
        }
        if (courseUsername == null || courseUsername.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先登录账号，再导入课表')),
          );
          ReceiveSharingIntent.instance.reset();
          _isProcessing = false;
          return;
        }
        targetSemester =
            await CourseImportPreflight.selectTargetSemester(context);
        if (!context.mounted) {
          _isProcessing = false;
          return;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入准备失败，请先检查登录和学期设置: $e')),
          );
        }
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
        return;
      }
      if (targetSemester == null) {
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
        return;
      }
    }
    if (!context.mounted) {
      _isProcessing = false;
      return;
    }

    ValueNotifier<String> statusNotifier = ValueNotifier("正在准备分享内容...");
    NavigatorState? dialogNavigator;
    var isDialogOpen = false;
    var closeRequestedBeforeBuild = false;

    void closeDialogSafely() {
      final navigator = dialogNavigator;
      if (!isDialogOpen || navigator == null || !navigator.mounted) {
        // showDialog installs its route on the next frame. Remember an early
        // failure instead of accidentally popping the page underneath it.
        closeRequestedBeforeBuild = true;
        return;
      }
      isDialogOpen = false;
      navigator.pop();
    }

    try {
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          dialogNavigator = Navigator.of(ctx, rootNavigator: true);
          isDialogOpen = true;
          if (closeRequestedBeforeBuild) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              closeDialogSafely();
            });
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
      ));
    } catch (error) {
      ReceiveSharingIntent.instance.reset();
      _isProcessing = false;
      statusNotifier.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开分享处理窗口: $error')),
        );
      }
      return;
    }

    String? claimedFileKey;
    AiRecognitionHandle? recognitionHandle;
    try {
      statusNotifier.value = isImage
          ? "正在准备图片..."
          : isFinanceImport
              ? "正在准备记账内容..."
              : "正在等待分享课表文件...";
      await Future.delayed(const Duration(milliseconds: 400));

      File file = await _waitForReadableFile(filePath);
      statusNotifier.value = "正在校验分享文件...";

      // 生成文件唯一标识。getInitialMedia 和 getMediaStream 可能同时返回
      // 同一份分享内容，因此两条入口必须使用同一套去重规则。
      final fileKey = await _generateFileKey(filePath);
      // 课表分享是一次明确的“导入”操作。同一份文件重新分享时，仍然
      // 必须让用户选择“共存/替换”，不能被上次失败或取消前留下的状态
      // 静默吞掉；识图和记账仍保留跨进程去重保护。
      final shouldDeduplicate = !needsCourseImport;
      if (shouldDeduplicate &&
          await _isShareAlreadyHandled(fileKey, filePath)) {
        statusNotifier.value = "分享内容已经处理过";
        await Future.delayed(const Duration(milliseconds: 600));
        closeDialogSafely();
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
        return;
      }
      if (!_processingFileKeys.add(fileKey)) {
        statusNotifier.value = "分享内容正在处理中";
        await Future.delayed(const Duration(milliseconds: 600));
        closeDialogSafely();
        ReceiveSharingIntent.instance.reset();
        _isProcessing = false;
        return;
      }
      claimedFileKey = fileKey;

      if (isImage) {
        if (requestedMode == ExternalShareMode.imageRecognition &&
            !await _isLikelyImageFile(file, media, imageExtensions)) {
          statusNotifier.value = "❌ 识别图片仅支持图片文件";
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
          return;
        }

        // 图片处理：调用大模型识别事项并保留类型声明
        statusNotifier.value = "识别到图片\n正在压缩图片...";

        final config = await LLMService.getConfig();
        if (config == null || !config.isConfigured) {
          statusNotifier.value = "⚠️ 需要配置大模型API\n请在设置中配置后重试";
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
          return;
        }

        // 检查原始图片大小
        final fileSize = await file.length();
        if (fileSize > 20 * 1024 * 1024) {
          statusNotifier.value = "⚠️ 图片太大\n请分享小于20MB的图片";
          await NotificationService.cancelTodoRecognizeNotification();
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
          return;
        }

        // 分享插件返回的通常是临时缓存文件。把它复制到应用自己的持久
        // 目录后再进入识别/聊天镜像，避免分享扩展退出或系统清理缓存时，
        // 首轮读取失败、只能靠聊天框重新选图才成功。
        filePath = await _materializeSharedImage(filePath);
        file = File(filePath);

        // 压缩图片
        String compressedPath = await _compressImage(filePath);

        final compressedFile = File(compressedPath);
        if (!await compressedFile.exists()) {
          throw Exception('图片压缩结果不可读取');
        }
        final compressedSize = await compressedFile.length();
        statusNotifier.value =
            "图片已压缩 (${(compressedSize / 1024).toStringAsFixed(0)}KB)\n正在调用大模型分析...";

        try {
          recognitionHandle =
              await AiRecognitionChatBridge.startImage(filePath);
        } catch (_) {
          // 聊天镜像失败不能影响原有的图片识别流程。
        }

        // 保存处理中状态（包含压缩图片路径，用于重试）
        await StorageService.savePendingTodoConfirm(
          imagePath: filePath,
          status: 'processing',
          compressedPath: compressedPath,
          sourceKey: fileKey,
          processingSessionId: _recognitionSessionId,
          recognitionChatSessionId: recognitionHandle?.sessionId,
          recognitionChatMessageId: recognitionHandle?.messageId,
          currentAttempt: 1,
          maxAttempts: 1,
        );

        // 立即显示进度通知上岛
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: 1,
          maxAttempts: 1,
          status: '正在识别图片...',
        );

        try {
          final recognition = await _recognizeImage(compressedPath);
          final results = recognition.todoResults;
          final financeDrafts = recognition.financeDrafts;
          final totalCount = results.length + financeDrafts.length;
          statusNotifier.value = totalCount == 0
              ? '✅ 识别完成，未发现可编辑事件'
              : '✅ 识别成功！\n发现${results.length}个事项，${financeDrafts.length}笔账单';
          // 标记文件为已处理，防止重复处理
          await _markFileProcessed(fileKey);
          await Future.delayed(const Duration(milliseconds: 800));
          closeDialogSafely();

          // 保存成功状态
          await StorageService.savePendingTodoConfirm(
            imagePath: filePath,
            results: results,
            financeResults:
                financeDrafts.map((draft) => draft.toJson()).toList(),
            status: 'success',
            compressedPath: compressedPath,
            sourceKey: fileKey,
            recognitionChatSessionId: recognitionHandle?.sessionId,
            recognitionChatMessageId: recognitionHandle?.messageId,
          );

          if (recognitionHandle != null) {
            await AiRecognitionChatBridge.complete(
              recognitionHandle,
              todoResults: results,
              financeDrafts: financeDrafts,
              usageSummary: recognition.usageSummary,
            );
          }

          // 显示成功通知
          await NotificationService.showTodoRecognizeSuccess(
            todoCount: totalCount,
          );

          // 通知首页刷新（dialog 已关闭）。两个回调按顺序执行，避免
          // 记账编辑页和待办确认页同时抢占导航栈。
          if (context.mounted && financeDrafts.isNotEmpty) {
            await onFinanceRecognized?.call(financeDrafts, filePath);
          }
          if (context.mounted &&
              onTodoRecognized != null &&
              results.isNotEmpty) {
            await onTodoRecognized(results, filePath);
          }
        } catch (e) {
          // debugPrint("大模型图片识别失败: $e");
          String errorMsg = e.toString();

          // 获取重试次数
          final maxRetries = await StorageService.getLLMRetryCount();

          if (maxRetries > 0) {
            // 有重试次数，启动后台重试
            statusNotifier.value = "首次识别失败\n正在后台重试...";
            await Future.delayed(const Duration(milliseconds: 500));
            closeDialogSafely();

            // 保存失败状态（首次尝试）
            await StorageService.updatePendingTodoConfirmStatus(
              status: 'failed',
              errorMsg: errorMsg,
            );

            // 在后台启动重试任务（重试完成后会自动通知首页）
            _startBackgroundRetry(
              filePath: filePath,
              compressedPath: compressedPath,
              fileKey: fileKey,
              maxRetries: maxRetries,
              onTodoRecognized: onTodoRecognized,
              onFinanceRecognized: onFinanceRecognized,
              recognitionHandle: recognitionHandle,
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
            // 保存失败状态
            await StorageService.savePendingTodoConfirm(
              imagePath: filePath,
              status: 'failed',
              compressedPath: compressedPath,
              errorMsg: errorMsg,
              sourceKey: fileKey,
              recognitionChatSessionId: recognitionHandle?.sessionId,
              recognitionChatMessageId: recognitionHandle?.messageId,
            );

            if (recognitionHandle != null) {
              await AiRecognitionChatBridge.fail(recognitionHandle, errorMsg);
            }

            // 显示失败通知
            await NotificationService.showTodoRecognizeFailed(
              errorMsg: errorMsg,
            );

            await Future.delayed(const Duration(seconds: 3));
            closeDialogSafely();
          }
        }
      } else if (isFinanceImport) {
        statusNotifier.value = "正在读取记账文本...";
        final content =
            await _safeReadFile(file).timeout(const Duration(seconds: 20));
        final drafts = FinanceTextParser.parse(
          content,
          source: FinanceEntrySource.import,
        );
        if (drafts.isEmpty) {
          statusNotifier.value = "❌ 未识别到记账内容";
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
          return;
        }
        statusNotifier.value = "✅ 已识别 ${drafts.length} 笔账单";
        await _markFileProcessed(fileKey);
        await Future.delayed(const Duration(milliseconds: 800));
        closeDialogSafely();
        if (context.mounted) {
          await onFinanceRecognized?.call(drafts, filePath);
        }
      } else {
        // 文件处理：课表导入
        statusNotifier.value = "获取课表文件中...";

        String content =
            await _safeReadFile(file).timeout(const Duration(seconds: 20));
        final username = courseUsername!;

        await Future.delayed(const Duration(milliseconds: 400));
        final targetSemesterId = targetSemester!.id;

        Future<List<CourseItem>?> repairMissingTimes(
            List<CourseItem> courses) async {
          if (!context.mounted) return null;
          statusNotifier.value = "部分课程缺少有效时间\n请补全后继续导入";
          return CourseTimeRepairDialog.show(context, courses);
        }

        var importModeCancelled = false;
        if (!context.mounted) {
          closeDialogSafely();
          return;
        }
        final courseImportHandler = CourseImportHandler(
          context: context,
          username: username,
          onRescheduleReminders: ReminderScheduleService.scheduleCurrentUser,
          showMessage: (_) {},
        );

        Future<bool?> selectImportMode(List<CourseItem> courses) async {
          statusNotifier.value = "解析完成\n请选择导入方式";
          final mode = await courseImportHandler.askImportMode(courses);
          if (mode == null) {
            importModeCancelled = true;
            return null;
          }
          statusNotifier.value =
              mode == ImportMode.merge ? "正在合并课表..." : "正在替换原课表...";
          return mode == ImportMode.merge;
        }

        bool success = false;
        String sourceName = "";

        if (ext == 'ics' || content.contains('BEGIN:VCALENDAR')) {
          sourceName = "西安电子科技大学";
          statusNotifier.value = "识别到: $sourceName\n正在导入...";

          success = await CourseService.importXidianScheduleFromIcs(
              username, content, targetSemester.startDate,
              semesterId: targetSemesterId,
              repairMissingTimes: repairMissingTimes,
              selectImportMode: selectImportMode);
        } else if (content.contains('timetable_con') ||
            content.contains('id="table1"') ||
            content.contains('kbgrid_table') ||
            content.toLowerCase().contains('huel')) {
          sourceName =
              content.toLowerCase().contains('huel') ? "河南财经政法大学" : "正方教务系统";
          statusNotifier.value = "识别到: $sourceName\n正在深度解析...";

          if (!context.mounted) {
            closeDialogSafely();
            return;
          }
          final customTimes = await showDialog<Map<int, Map<String, int>>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const ZfTimeConfigDialog(),
          );
          if (customTimes == null) {
            closeDialogSafely();
            return;
          }
          statusNotifier.value = "识别到: $sourceName\n正在深度解析...";

          success = await CourseService.importZfSoftScheduleFromHtml(
              username, content, targetSemester.startDate,
              customTimes: customTimes,
              semesterId: targetSemesterId,
              repairMissingTimes: repairMissingTimes,
              selectImportMode: selectImportMode);
        } else if ((['mhtml', 'html', 'htm'].contains(ext) ||
                content.contains('quoted-printable') ||
                content.toLowerCase().contains('<html')) &&
            (content.contains('XMUSTUDENT') ||
                content.contains('class="arrage') ||
                content.contains('class="arrange'))) {
          sourceName = "厦门大学";
          statusNotifier.value = "识别到: $sourceName\n正在深度解码导入...";

          success = await CourseService.importXmuScheduleFromHtml(
              username, content, targetSemester.startDate,
              semesterId: targetSemesterId,
              repairMissingTimes: repairMissingTimes,
              selectImportMode: selectImportMode);
        } else if (['json', 'txt'].contains(ext) ||
            content.trim().startsWith('[') ||
            content.trim().startsWith('{')) {
          sourceName = "聚在工大";
          statusNotifier.value = "识别到: $sourceName\n正在导入...";
          success = await CourseService.importScheduleFromJson(
              username, content,
              semesterStart: targetSemester.startDate,
              semesterId: targetSemesterId,
              repairMissingTimes: repairMissingTimes,
              selectImportMode: selectImportMode);
        } else {
          statusNotifier.value = "❌ 未知的文件格式\n暂不支持解析该文件";
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
          return;
        }

        if (success) {
          statusNotifier.value = "✅ 导入成功！\n正在刷新课表...";
          // 标记文件为已处理，防止重复处理
          await _markFileProcessed(fileKey);
          await Future.delayed(const Duration(milliseconds: 800));
          closeDialogSafely();
          try {
            await ReminderScheduleService.scheduleCurrentUser();
          } catch (error) {
            // The course data has already been saved. Keep a notification
            // refresh failure from hiding a successful share import.
            debugPrint('⚠️ 分享课表后刷新提醒失败: $error');
          }
          if (context.mounted) onSuccess();
        } else if (importModeCancelled) {
          closeDialogSafely();
        } else {
          statusNotifier.value = "❌ 导入失败\n课表解析错误或文件已损坏";
          await Future.delayed(const Duration(seconds: 2));
          closeDialogSafely();
        }
      }
    } catch (e) {
      // debugPrint("处理外部共享文件崩溃: $e");
      statusNotifier.value = "❌ 发生异常\n读取文件失败或格式崩溃";
      await Future.delayed(const Duration(seconds: 2));
      closeDialogSafely();
    } finally {
      ReceiveSharingIntent.instance.reset();
      if (claimedFileKey != null) {
        _processingFileKeys.remove(claimedFileKey);
      }
      _isProcessing = false;
      statusNotifier.dispose();
    }
  }

  static String? _sharedTextPayload(SharedMediaFile media) {
    final message = media.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    final path = media.path.trim();
    return path.isEmpty ? null : path;
  }

  /// 同一张图片走两条互不排斥的识别通道：待办通道负责取餐/取件码，
  /// 账单通道负责支付记录。任一通道失败都不影响另一类结果。
  static Future<_ImageRecognitionResult> _recognizeImage(
    String imagePath,
  ) async {
    final errors = <Object>[];
    final usageSummaries = <ChatUsageSummary>[];
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _runVisionPass(
        () => LLMService.parseTodoFromImage(
          imagePath,
          onUsage: usageSummaries.add,
        ),
        errors,
      ),
      _runVisionPass(
        () => LLMService.parseFinanceFromImage(
          imagePath,
          onUsage: usageSummaries.add,
        ),
        errors,
      ),
    ]);

    final todoResults = RecognizedTodoAdapter.normalizeImageResults(
      results.first
          .where((result) => !FinanceTextParser.isFinanceResult(result)),
    );
    final financeDrafts = FinanceTextParser.fromRecognitionResults(
      [...results.first, ...results.last],
      source: FinanceEntrySource.import,
    );
    if (todoResults.isEmpty && financeDrafts.isEmpty) {
      final detail = errors.isNotEmpty ? ': ${errors.first}' : '';
      throw Exception('图片识别未返回可识别内容$detail');
    }
    return _ImageRecognitionResult(
      todoResults: todoResults,
      financeDrafts: financeDrafts,
      usageSummary: ChatUsageSummary.combine(usageSummaries),
    );
  }

  static Future<List<Map<String, dynamic>>> _runVisionPass(
    Future<List<Map<String, dynamic>>> Function() operation,
    List<Object> errors,
  ) async {
    try {
      return await operation().timeout(const Duration(seconds: 90));
    } catch (error) {
      errors.add(error);
      return const <Map<String, dynamic>>[];
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

  static Future<bool> _isLikelyImageFile(
    File file,
    SharedMediaFile media,
    Set<String> imageExtensions,
  ) async {
    if (media.type == SharedMediaType.image ||
        media.mimeType?.toLowerCase().startsWith('image/') == true) {
      return true;
    }

    final fileName = file.path.split(RegExp(r'[\\/]')).last.toLowerCase();
    final dot = fileName.lastIndexOf('.');
    if (dot >= 0 && imageExtensions.contains(fileName.substring(dot + 1))) {
      return true;
    }

    try {
      final header = await file.openRead(0, 12).fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      if (header.length >= 3 &&
          header[0] == 0xff &&
          header[1] == 0xd8 &&
          header[2] == 0xff) {
        return true; // JPEG
      }
      if (header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4e &&
          header[3] == 0x47 &&
          header[4] == 0x0d &&
          header[5] == 0x0a &&
          header[6] == 0x1a &&
          header[7] == 0x0a) {
        return true; // PNG
      }
      if (header.length >= 6 &&
          header[0] == 0x47 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x38) {
        return true; // GIF
      }
      if (header.length >= 2 && header[0] == 0x42 && header[1] == 0x4d) {
        return true; // BMP
      }
      if (header.length >= 4 &&
          ((header[0] == 0x49 &&
                  header[1] == 0x49 &&
                  header[2] == 0x2a &&
                  header[3] == 0x00) ||
              (header[0] == 0x4d &&
                  header[1] == 0x4d &&
                  header[2] == 0x00 &&
                  header[3] == 0x2a))) {
        return true; // TIFF
      }
      if (header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return true; // WEBP
      }
      if (header.length >= 12 &&
          header[4] == 0x66 &&
          header[5] == 0x74 &&
          header[6] == 0x79 &&
          header[7] == 0x70) {
        final brand = String.fromCharCodes(header.sublist(8, 12));
        return const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'avif'}
            .contains(brand);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// 等待分享扩展完成文件复制。部分来源会先发送 intent，再异步写入
  /// 缓存文件；直接 File.length/readAsBytes 会把这类正常分享误判成失败。
  static Future<File> _waitForReadableFile(String path) async {
    final file = File(path);
    int? previousSize;
    var stableReads = 0;
    Object? lastError;
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        if (await file.exists()) {
          final size = await file.length();
          if (size > 0) {
            if (size == previousSize) {
              stableReads++;
            } else {
              previousSize = size;
              stableReads = 1;
            }
            if (stableReads >= 2) return file;
          }
        }
      } catch (error) {
        lastError = error;
      }
      await Future.delayed(
        Duration(milliseconds: attempt == 0 ? 100 : 250),
      );
    }
    final detail = lastError == null ? '' : ': $lastError';
    throw Exception('分享文件暂不可读取$detail');
  }

  static Future<String> _materializeSharedImage(String sourcePath) async {
    try {
      final persistedPath = await persistImagePath(
        sourcePath,
        'analysis_images',
      );
      if (persistedPath != null && persistedPath.isNotEmpty) {
        return persistedPath;
      }
    } catch (_) {
      // 复制失败时仍尝试使用插件路径；当前进程内它通常仍然可读。
    }
    return sourcePath;
  }

  static Future<String> _safeReadFile(File file) async {
    try {
      return await file.readAsString();
    } catch (e) {
      List<int> bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 生成文件内容指纹。
  ///
  /// 分享插件在不同生命周期可能为同一张图片返回不同的临时路径，
  /// 因此不能再用路径/修改时间作为唯一标识；内容哈希才能跨重启和
  /// getInitialMedia/getMediaStream 两条回调稳定去重。
  static Future<String> _generateFileKey(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return 'path:$filePath';
      // Stream the digest instead of loading a potentially large MHTML/file
      // share into memory. A full read here used to leave the UI on the
      // initial “处理中...” state for large external shares.
      final digest = await sha256
          .bind(file.openRead())
          .first
          .timeout(const Duration(seconds: 30));
      return 'sha256:${digest.toString()}';
    } catch (e) {
      return 'path:$filePath';
    }
  }

  /// 检查当前分享是否已经被本次运行、历史运行或待确认记录接收。
  ///
  /// 待确认记录是跨进程的最后一道保护：如果 App 在识别过程中被杀，
  /// 下次启动时即使内存缓存消失，也不会因重复回调再次发起请求；只有任务
  /// 已被判定中断时，才允许新的分享或确认卡片上的“重试”主动接管。
  static Future<bool> _isShareAlreadyHandled(
    String fileKey,
    String filePath,
  ) async {
    if (_processingFileKeys.contains(fileKey)) return true;

    try {
      final pending = await StorageService.getPendingTodoConfirm();
      if (pending != null) {
        final pendingStatus =
            pending['status']?.toString().trim().toLowerCase();
        final pendingSessionId =
            pending['processingSessionId']?.toString().trim();

        bool blocksRecognition() {
          return TodoRecognitionState.blocksDuplicate(
            status: pendingStatus,
            processingSessionId: pendingSessionId,
            currentSessionId: _recognitionSessionId,
          );
        }

        final pendingSourceKey = pending['sourceKey']?.toString().trim();
        if (pendingSourceKey != null && pendingSourceKey.isNotEmpty) {
          if (pendingSourceKey == fileKey) return blocksRecognition();
          // 兼容升级前的路径+修改时间标识。
          final legacyKey = await _legacyFileKey(filePath);
          if (legacyKey != null && pendingSourceKey == legacyKey) {
            return blocksRecognition();
          }
        } else if (pending['imagePath']?.toString() == filePath) {
          // 兼容旧版没有 sourceKey 的待确认记录。这个兜底只比较原始路径，
          // 新版记录优先使用内容指纹，避免同路径被复用时误判。
          return blocksRecognition();
        }
      }
    } catch (_) {
      // 存储读取失败时继续使用已处理文件缓存作为兜底。
    }

    // 待确认记录优先于 processed_file_keys：如果 App 在写入成功结果前
    // 被杀，旧 processing 记录允许新会话接管，不能被提前写入的缓存挡住。
    return await _isFileProcessed(fileKey) ||
        await _isLegacyFileProcessed(filePath);
  }

  static Future<bool> _isLegacyFileProcessed(String filePath) async {
    final legacyKey = await _legacyFileKey(filePath);
    return legacyKey != null && await _isFileProcessed(legacyKey);
  }

  static Future<String?> _legacyFileKey(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      return '${filePath}_${stat.modified.millisecondsSinceEpoch}_${stat.size}';
    } catch (_) {
      return null;
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
    _processedFileKeys.remove(fileKey);
    _processedFileKeys.add(fileKey);
    while (_processedFileKeys.length > _maxProcessedKeys) {
      _processedFileKeys.removeAt(0);
    }

    // 持久化存储
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> processedKeys =
          (prefs.getStringList('processed_file_keys') ?? [])
              .where((key) => key != fileKey)
              .toList();
      processedKeys.add(fileKey);
      // 限制列表大小
      while (processedKeys.length > _maxProcessedKeys) {
        processedKeys.removeAt(0);
      }
      await prefs.setStringList('processed_file_keys', processedKeys);
    } catch (e) {
      // debugPrint("持久化存储已处理文件失败: $e");
    }
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  /// 将上一次进程被系统回收后遗留的 processing/retrying 状态收口为失败。
  ///
  /// 识别任务本身没有跨进程执行能力，旧记录如果继续保持 processing，首页
  /// 就会永久显示转圈。当前进程的任务会带有当前 session，且会在最近一次
  /// 状态更新后继续保留；跨进程记录则允许用户从失败卡片主动重试。
  static Future<bool> recoverInterruptedTodoRecognition() async {
    if (_isProcessing || _processingFileKeys.isNotEmpty) return false;

    final pending = await StorageService.getPendingTodoConfirm();
    if (pending == null) return false;
    // 读取持久化状态期间可能刚好收到新的分享事件，重新确认没有活跃任务，
    // 避免把刚启动的识别误判成上一次中断。
    if (_isProcessing || _processingFileKeys.isNotEmpty) return false;

    final status = pending['status']?.toString().trim().toLowerCase();
    if (status != 'processing' && status != 'retrying') return false;

    final sessionId = pending['processingSessionId']?.toString().trim();
    final timestamp = _readInt(pending['timestamp']);
    final isInterrupted = TodoRecognitionState.isInterrupted(
      status: status,
      processingSessionId: sessionId,
      currentSessionId: _recognitionSessionId,
      timestampMs: timestamp,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!isInterrupted) return false;

    await StorageService.updatePendingTodoConfirmStatus(
      status: 'failed',
      errorMsg: '上次图片识别已中断，请点击重试',
    );
    final recognitionHandle =
        AiRecognitionChatBridge.handleFromPending(pending);
    if (recognitionHandle != null) {
      await AiRecognitionChatBridge.fail(
        recognitionHandle,
        '上次图片识别已中断，请点击重试',
      );
    }
    await NotificationService.cancelTodoRecognizeNotification();
    return true;
  }

  static int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// 启动后台重试任务
  /// [filePath] 原始图片路径
  /// [compressedPath] 压缩后的图片路径
  /// [fileKey] 文件唯一标识
  /// [maxRetries] 最大重试次数
  /// [onTodoRecognized] 事项识别成功回调（名称为旧接口兼容保留）
  static void _startBackgroundRetry({
    required String filePath,
    required String compressedPath,
    required String fileKey,
    required int maxRetries,
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    FutureOr<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
    AiRecognitionHandle? recognitionHandle,
  }) async {
    // debugPrint("启动后台重试: filePath=$filePath, maxRetries=$maxRetries");

    // 显示开始重试的通知
    await NotificationService.showTodoRecognizeProgress(
      currentAttempt: 1,
      maxAttempts: maxRetries + 1,
      status: '开始后台重试...',
    );

    bool success = false;
    _ImageRecognitionResult? recognition;
    String? lastError;

    if (recognitionHandle != null) {
      await AiRecognitionChatBridge.markProcessing(recognitionHandle);
    }

    // 尝试原始图片和压缩后的图片
    final pathsToTry = [compressedPath];
    if (compressedPath != filePath) {
      pathsToTry.add(filePath);
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // debugPrint("后台重试第$attempt次...");

        // 更新进度通知和状态
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          status: '正在分析图片...',
        );

        // 更新待确认状态为重试中
        await StorageService.updatePendingTodoConfirmStatus(
          status: 'retrying',
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          processingSessionId: _recognitionSessionId,
          recognitionChatSessionId: recognitionHandle?.sessionId,
          recognitionChatMessageId: recognitionHandle?.messageId,
        );

        // 尝试不同的图片路径
        final currentPath = pathsToTry[(attempt - 1) % pathsToTry.length];

        // 增加超时时间到 180 秒，提高后台识别成功率
        recognition = await _recognizeImage(currentPath);

        success = true;
        // debugPrint("后台重试第$attempt次成功!");
        break;
      } catch (e) {
        lastError = e.toString();
        // debugPrint("后台重试第$attempt次失败: $e");

        // 更新失败通知和状态
        await NotificationService.showTodoRecognizeProgress(
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          status: '第$attempt次失败，准备重试...',
        );

        // 更新状态为失败（准备重试）
        await StorageService.updatePendingTodoConfirmStatus(
          status: 'failed',
          currentAttempt: attempt + 1,
          maxAttempts: maxRetries + 1,
          errorMsg: lastError,
        );

        // 如果不是最后一次，等待更长时间再重试（指数退避）
        if (attempt < maxRetries) {
          final waitSeconds = 5 * attempt; // 增加等待时间
          // debugPrint("等待$waitSeconds秒后重试...");
          await Future.delayed(Duration(seconds: waitSeconds));
        }
      }
    }

    if (success && recognition != null) {
      final results = recognition.todoResults;
      final financeDrafts = recognition.financeDrafts;
      final totalCount = results.length + financeDrafts.length;
      // 标记文件为已处理
      await _markFileProcessed(fileKey);

      // 保存成功状态
      await StorageService.savePendingTodoConfirm(
        imagePath: filePath,
        results: results,
        financeResults: financeDrafts.map((draft) => draft.toJson()).toList(),
        status: 'success',
        compressedPath: compressedPath,
        sourceKey: fileKey,
        recognitionChatSessionId: recognitionHandle?.sessionId,
        recognitionChatMessageId: recognitionHandle?.messageId,
      );

      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.complete(
          recognitionHandle,
          todoResults: results,
          financeDrafts: financeDrafts,
          usageSummary: recognition.usageSummary,
        );
      }

      // 发送成功通知
      await NotificationService.showTodoRecognizeSuccess(
        todoCount: totalCount,
      );

      // 通知首页刷新（成功时自动打开确认页面）
      if (financeDrafts.isNotEmpty) {
        await onFinanceRecognized?.call(financeDrafts, filePath);
      }
      if (onTodoRecognized != null) {
        await onTodoRecognized(results, filePath);
      }

      // debugPrint("后台重试成功，已保存${results.length}个待办，等待用户确认");
    } else {
      // 所有重试都失败，保存最终失败状态
      await StorageService.updatePendingTodoConfirmStatus(
        status: 'failed',
        errorMsg: lastError ?? '未知错误',
      );
      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.fail(
          recognitionHandle,
          lastError ?? '未知错误',
        );
      }

      // 发送失败通知
      await NotificationService.showTodoRecognizeFailed(
        errorMsg: lastError ?? '未知错误',
      );

      // 不通知首页刷新，让用户点击重试按钮来手动刷新
      // debugPrint("后台重试全部失败: $lastError");
    }
  }

  /// 检查是否有待确认的事项数据
  /// 返回 null 表示没有待确认数据
  static Future<Map<String, dynamic>?> getPendingTodoConfirm() async {
    return await StorageService.getPendingTodoConfirm();
  }

  /// 清除待确认的事项数据
  static Future<void> clearPendingTodoConfirm() async {
    await StorageService.clearPendingTodoConfirm();
  }

  static Future<void> clearPendingFinanceRecognized() async {
    final pending = await StorageService.getPendingTodoConfirm();
    if (pending == null) return;
    await StorageService.updatePendingTodoConfirmStatus(
      status: pending['status']?.toString() ?? 'success',
      financeResults: const [],
    );
  }

  /// 重试图片识别
  /// [onTodoRecognized] 事项识别成功回调（名称为旧接口兼容保留）
  static Future<void> retryTodoRecognition({
    Function(List<Map<String, dynamic>>, String?)? onTodoRecognized,
    FutureOr<void> Function(List<FinanceEntryDraft>, String?)?
        onFinanceRecognized,
  }) async {
    final pendingData = await StorageService.getPendingTodoConfirm();
    if (pendingData == null) {
      // debugPrint("没有待确认的事项数据，无法重试");
      return;
    }

    final imagePath = pendingData['imagePath'] as String?;
    final compressedPath = pendingData['compressedPath'] as String?;

    if (imagePath == null) {
      // debugPrint("图片路径为空，无法重试");
      return;
    }

    // 优先使用压缩后的图片路径
    final retryPath = compressedPath ?? imagePath;
    // 无论待确认记录来自哪个版本，重试时都重新计算当前原图指纹，
    // 让旧版路径标识也迁移到新版的跨重启去重协议。
    final sourceKey = await _generateFileKey(imagePath);
    var recognitionHandle =
        AiRecognitionChatBridge.handleFromPending(pendingData);
    if (recognitionHandle == null) {
      try {
        recognitionHandle = await AiRecognitionChatBridge.startImage(imagePath);
      } catch (_) {
        // 聊天镜像失败不能影响原有的图片识别流程。
      }
    }

    // 检查图片文件是否存在
    final file = File(retryPath);
    if (!await file.exists()) {
      // debugPrint("图片文件不存在: $retryPath");
      await StorageService.updatePendingTodoConfirmStatus(
        status: 'failed',
        errorMsg: '图片文件不存在，请重新分享',
      );
      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.fail(
          recognitionHandle,
          '图片文件不存在，请重新分享',
        );
      }
      if (onTodoRecognized != null) {
        onTodoRecognized([], imagePath);
      }
      return;
    }

    // 更新状态为重试中
    await StorageService.updatePendingTodoConfirmStatus(
      status: 'retrying',
      currentAttempt: 1,
      maxAttempts: 1,
      processingSessionId: _recognitionSessionId,
      recognitionChatSessionId: recognitionHandle?.sessionId,
      recognitionChatMessageId: recognitionHandle?.messageId,
    );
    if (recognitionHandle != null) {
      await AiRecognitionChatBridge.markProcessing(recognitionHandle);
    }

    // 显示进度通知
    await NotificationService.showTodoRecognizeProgress(
      currentAttempt: 1,
      maxAttempts: 1,
      status: '正在重新识别...',
    );

    // 不通知首页刷新，让首页通过 _checkPendingTodoConfirm 自动刷新

    try {
      final recognition = await _recognizeImage(retryPath);
      final results = recognition.todoResults;
      final financeDrafts = recognition.financeDrafts;
      final totalCount = results.length + financeDrafts.length;

      if (totalCount > 0) {
        // 标记文件为已处理
        await _markFileProcessed(sourceKey);

        // 保存成功状态
        await StorageService.savePendingTodoConfirm(
          imagePath: imagePath,
          results: results,
          financeResults: financeDrafts.map((draft) => draft.toJson()).toList(),
          status: 'success',
          compressedPath: compressedPath,
          sourceKey: sourceKey,
          recognitionChatSessionId: recognitionHandle?.sessionId,
          recognitionChatMessageId: recognitionHandle?.messageId,
        );

        if (recognitionHandle != null) {
          await AiRecognitionChatBridge.complete(
            recognitionHandle,
            todoResults: results,
            financeDrafts: financeDrafts,
            usageSummary: recognition.usageSummary,
          );
        }

        // 显示成功通知
        await NotificationService.showTodoRecognizeSuccess(
          todoCount: totalCount,
        );

        // 通知首页刷新
        if (financeDrafts.isNotEmpty) {
          await onFinanceRecognized?.call(financeDrafts, imagePath);
        }
        if (onTodoRecognized != null) {
          await onTodoRecognized(results, imagePath);
        }

        // debugPrint("重试成功，已保存${results.length}个待办");
      } else {
        // 识别结果为空
        await StorageService.updatePendingTodoConfirmStatus(
          status: 'failed',
          errorMsg: '未识别到可添加的事项',
        );
        if (recognitionHandle != null) {
          await AiRecognitionChatBridge.fail(
            recognitionHandle,
            '未识别到可添加的事项',
          );
        }

        await NotificationService.showTodoRecognizeFailed(
          errorMsg: '未识别到可添加的事项',
        );

        // 不通知首页刷新，让用户点击重试按钮来手动刷新
      }
    } catch (e) {
      // debugPrint("重试失败: $e");
      String errorMsg = e.toString();

      // 保存失败状态
      await StorageService.updatePendingTodoConfirmStatus(
        status: 'failed',
        errorMsg: errorMsg,
      );
      if (recognitionHandle != null) {
        await AiRecognitionChatBridge.fail(recognitionHandle, errorMsg);
      }

      // 显示失败通知
      await NotificationService.showTodoRecognizeFailed(
        errorMsg: errorMsg,
      );

      // 不通知首页刷新，让用户点击重试按钮来手动刷新
    }
  }
}

class _ImageRecognitionResult {
  final List<Map<String, dynamic>> todoResults;
  final List<FinanceEntryDraft> financeDrafts;
  final ChatUsageSummary? usageSummary;

  const _ImageRecognitionResult({
    required this.todoResults,
    required this.financeDrafts,
    this.usageSummary,
  });
}
