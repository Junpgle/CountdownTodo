import 'dart:io';
import 'dart:ui' as ui;

import 'package:countdown_todo/widgets/ai_chat_composer.dart';
import 'package:countdown_todo/screens/todo_chat_screen.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/models/ai_context_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _inputKey = ValueKey('ai-chat-input');
const _expandedKey = ValueKey('ai-chat-expanded-input');
const _previewPath = String.fromEnvironment('CDT_COMPOSER_PREVIEW');

Widget _page(
  TextEditingController controller, {
  bool loading = false,
  bool attachment = false,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  VoidCallback? onSend,
  VoidCallback? onStop,
  void Function(String)? onAction,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
  ),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Column(
          children: [
            const Expanded(child: Center(child: Text('对话内容'))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: AiChatComposer(
                controller: controller,
                keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
                modelSelector: TextButton(
                  onPressed: () {},
                  child: const Text(
                    'MiMo v2.6 Flash',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                contextLabel: '原生工具调用',
                isLoading: loading,
                deepThinking: false,
                contextEnabled: true,
                hasAttachment: attachment,
                onSend: onSend ?? () {},
                onVoice: () => onAction?.call('voice'),
                onStop: onStop ?? () {},
                onAttach: () => onAction?.call('attach'),
                onToggleThinking: () => onAction?.call('thinking'),
                onToggleContext: () => onAction?.call('context'),
                onSettings: () => onAction?.call('settings'),
                onModelConfig: () => onAction?.call('model'),
                onCopyPrompt: () => onAction?.call('copy'),
                onPasteReply: () => onAction?.call('paste'),
                onRetry: () => onAction?.call('retry'),
                onClearHistory: () => onAction?.call('clear'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _ctrlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  if (_previewPath.isNotEmpty) {
    setUpAll(() async {
      for (final (family, path) in [
        ('CDTComposerPreview', '/System/Library/Fonts/Supplemental/Songti.ttc'),
        (
          'MaterialIcons',
          '/Users/junpgle/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
            ))
            .load();
      }
    });
  }
  late TextEditingController controller;
  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  testWidgets('默认两行、15号字、独占宽度，所有按钮位于文字区下方', (tester) async {
    await tester.pumpWidget(_page(controller));
    final field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.minLines, 2);
    expect(field.maxLines, 6);
    expect(field.style!.fontSize, 15);
    expect(field.textInputAction, TextInputAction.newline);
    final rect = tester.getRect(find.byKey(_inputKey));
    expect(
      rect.width,
      greaterThan(tester.getSize(find.byType(AiChatComposer)).width - 4),
    );
    expect(
      tester.getRect(find.byTooltip('展开编辑')).top,
      greaterThanOrEqualTo(rect.bottom),
    );
    expect(
      tester.getRect(find.byTooltip('深度思考')).top,
      greaterThanOrEqualTo(rect.bottom),
    );
    expect(find.text('复制提示词'), findsNothing);
    expect(find.text('粘贴AI回复识别'), findsNothing);
  });

  testWidgets('长提示词自动长高但限制为六行，后续内容保留并可滚动编辑', (tester) async {
    await tester.pumpWidget(_page(controller));
    final initialHeight = tester.getSize(find.byKey(_inputKey)).height;
    final longText = List.generate(30, (i) => '第$i行：分析本月账单和待办').join('\n');
    await tester.enterText(find.byKey(_inputKey), longText);
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byKey(_inputKey)).height;
    expect(height, greaterThan(initialHeight));
    expect(height, lessThan(180));
    expect(controller.text, longText);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多行键盘动作不直接发送，Ctrl+Enter发送当前完整草稿', (tester) async {
    var sends = 0;
    await tester.pumpWidget(_page(controller, onSend: () => sends++));
    await tester.enterText(find.byKey(_inputKey), '第一行\n第二行');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    expect(sends, 0);
    await _ctrlEnter(tester);
    expect(sends, 1);
    expect(controller.text, '第一行\n第二行');
  });

  testWidgets('空输入禁用发送，但只有附件时允许发送', (tester) async {
    var sends = 0;
    await tester.pumpWidget(_page(controller, onSend: () => sends++));
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ai-chat-send')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(
      _page(controller, attachment: true, onSend: () => sends++),
    );
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    expect(sends, 1);
  });

  testWidgets('生成期间仍可编辑草稿，快捷发送不触发停止，停止按钮可用', (tester) async {
    var sends = 0;
    var stops = 0;
    await tester.pumpWidget(
      _page(
        controller,
        loading: true,
        onSend: () => sends++,
        onStop: () => stops++,
      ),
    );
    await tester.enterText(find.byKey(_inputKey), '下一条问题');
    await _ctrlEnter(tester);
    expect(sends, 0);
    expect(stops, 0);
    await tester.tap(find.byTooltip('停止生成'));
    expect(stops, 1);
    expect(controller.text, '下一条问题');
  });

  testWidgets('低频操作收进更多菜单，复制、粘贴与重试仍调用原有入口', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(_page(controller, onAction: actions.add));
    for (final (label, action) in [
      ('复制提示词', 'copy'),
      ('粘贴AI回复识别', 'paste'),
      ('重试上一条回复', 'retry'),
      ('模型配置', 'model'),
      ('AI 助手设置', 'settings'),
      ('清空聊天记录', 'clear'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('ai-chat-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(actions.last, action);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开与收起共用草稿，保留编辑后的文本、选区和输入焦点', (tester) async {
    controller.value = const TextEditingValue(
      text: '查询上个月的账单，再总结本周待办',
      selection: TextSelection(baseOffset: 2, extentOffset: 6),
    );
    await tester.pumpWidget(_page(controller));
    await tester.tap(find.byTooltip('展开编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提示词'), findsOneWidget);
    final editor = tester.widget<TextField>(find.byKey(_expandedKey));
    expect(editor.controller, same(controller));
    expect(
      controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 6),
    );
    await tester.enterText(find.byKey(_expandedKey), '修改后的完整提示词\n第二段说明');
    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 8);
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(controller.text, '修改后的完整提示词\n第二段说明');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 3, extentOffset: 8),
    );
    expect(
      tester.widget<TextField>(find.byKey(_inputKey)).focusNode!.hasFocus,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统返回关闭编辑页也保留草稿', (tester) async {
    controller.text = '初始草稿';
    await tester.pumpWidget(_page(controller));
    await tester.tap(find.byTooltip('展开编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_expandedKey), '返回时保留这段文字');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.text, '返回时保留这段文字');
    expect(find.byKey(_inputKey), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320宽度、${brightness.name}主题和大字号下不溢出，键盘出现后隐藏状态栏', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        _page(controller, brightness: brightness, textScale: 1.6),
      );
      expect(find.text('MiMo v2.6 Flash'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.text('MiMo v2.6 Flash'), findsNothing);
      expect(find.byKey(_inputKey), findsOneWidget);
      expect(find.byTooltip('智能上下文 · 原生工具调用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('横屏键盘挤压时限制输入高度，发送与展开入口仍可见', (tester) async {
    tester.view.physicalSize = const Size(720, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    controller.text = List.filled(20, '一行长提示词').join('\n');
    await tester.pumpWidget(_page(controller));
    final field = tester.widget<TextField>(find.byKey(_inputKey));
    expect(field.maxLines, lessThan(6));
    expect(
      tester.getRect(find.byKey(const ValueKey('ai-chat-send'))).bottom,
      lessThanOrEqualTo(160),
    );
    expect(find.byTooltip('展开编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('实际AI对话页面接入输入组件：宽度$width，展开编辑不丢草稿', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await FeatureTipService.markTipShown('todo_chat_guide');
      await ChatStorageService.setContextMode(AiContextMode.functionCalling);
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: _previewPath.isEmpty ? null : 'CDTComposerPreview',
            ),
            home: const TodoChatScreen(username: 'composer-test', todos: []),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(AiChatComposer), findsOneWidget);
      await tester.enterText(find.byKey(_inputKey), '实际页面草稿\n需要按条件查询');
      await tester.pump();
      if (_previewPath.isNotEmpty && width == 390) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final snapshot = await boundary.toImage(pixelRatio: 2);
          final bytes = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File(_previewPath).writeAsBytesSync(bytes!.buffer.asUint8List());
          snapshot.dispose();
        });
      }
      await tester.tap(find.byTooltip('展开编辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.enterText(find.byKey(_expandedKey), '修改后的实际页面草稿');
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(_inputKey)).controller!.text,
        '修改后的实际页面草稿',
      );
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('模型配置'), findsNothing);
      expect(
        tester
            .widget<AiChatComposer>(find.byType(AiChatComposer))
            .keyboardInset,
        300,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('ai-chat-send'))).bottom,
        lessThanOrEqualTo(500),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
