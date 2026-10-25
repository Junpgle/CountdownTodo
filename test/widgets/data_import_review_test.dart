import 'dart:io';

import 'package:countdown_todo/models/data_export_models.dart';
import 'package:countdown_todo/screens/settings/widgets/import_restore_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round46ImportReviewPreview';
const _previewFontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
final _iconFontPath =
    '${Platform.environment['FLUTTER_ROOT'] ?? '/Users/junpgle/develop/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
final _hasPreviewFont = Platform.isMacOS && File(_previewFontPath).existsSync();

Future<void> _loadPreviewFonts() async {
  if (_hasPreviewFont) {
    final font = FontLoader(_previewFontFamily)
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_previewFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
  if (File(_iconFontPath).existsSync()) {
    final font = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(_iconFontPath).readAsBytes()),
        ),
      );
    await font.load();
  }
}

ImportPreview _preview() {
  final types = <ImportTypePreview>[
    ImportTypePreview(key: 'todos', label: '待办事项', count: 2, teamCount: 1),
    ImportTypePreview(key: 'courses', label: '课程', count: 1, teamCount: 1),
    ImportTypePreview(key: 'finance', label: '记账数据', count: 3),
    ImportTypePreview(key: 'thirty_day_challenge', label: '30 天挑战', count: 2),
    ImportTypePreview(key: 'settings', label: '偏好设置', count: 2),
  ];
  return ImportPreview(
    fileVersion: 2,
    exportedAt: DateTime(2026, 10, 24),
    types: types,
    scopes: [
      ImportScopePreview(
        scope: ImportDataScope.productivity,
        types: [types[0]],
      ),
      ImportScopePreview(scope: ImportDataScope.courses, types: [types[1]]),
      ImportScopePreview(scope: ImportDataScope.finance, types: [types[2]]),
      ImportScopePreview(scope: ImportDataScope.challenge, types: [types[3]]),
      ImportScopePreview(scope: ImportDataScope.settings, types: [types[4]]),
    ],
    unsupportedKeys: const [],
  );
}

class _ReviewHost extends StatefulWidget {
  final ImportPreview preview;
  final Set<ImportDataScope> scopes;

  const _ReviewHost({required this.preview, required this.scopes});

  @override
  State<_ReviewHost> createState() => _ReviewHostState();
}

class _ReviewHostState extends State<_ReviewHost> {
  bool? confirmed;
  var executionCount = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () async {
          confirmed = await ImportRestoreReviewDialog.show(
            context: context,
            preview: widget.preview,
            selectedScopes: widget.scopes,
            isSameAccount: false,
            teamStrategy: TeamDataStrategy.convertToPersonal,
            selectedTeamCount: teamScopedImportCount(
              widget.preview,
              widget.scopes,
            ),
          );
          if (confirmed == true) executionCount++;
          if (mounted) setState(() {});
        },
        child: const Text('打开复核'),
      ),
    ),
  );
}

Future<void> _pumpReview(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Set<ImportDataScope>? scopes,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: _previewFontFamily,
        useMaterial3: true,
        brightness: brightness,
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: _ReviewHost(
          preview: _preview(),
          scopes: scopes ?? ImportDataScope.values.toSet(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开复核'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadPreviewFonts);

  testWidgets('手机确认恢复范围截图并明确高影响数据域', (tester) async {
    await _pumpReview(tester);
    expect(find.text('确认恢复范围'), findsOneWidget);
    expect(find.textContaining('可能覆盖当前账号的挑战进度'), findsOneWidget);
    expect(find.textContaining('覆盖对应当前设置'), findsOneWidget);
    expect(find.textContaining('团队数据：2 条；转为个人数据'), findsOneWidget);
    expect(find.text('3 项（备份）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-46/import_review_phone.png',
      ),
    );
  });

  testWidgets('桌面确认恢复范围截图', (tester) async {
    await _pumpReview(tester, size: const Size(1280, 900));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-46/import_review_desktop.png',
      ),
    );
  });

  testWidgets('深色大字号确认界面可滚动且无溢出', (tester) async {
    await _pumpReview(
      tester,
      size: const Size(320, 740),
      textScale: 1.6,
      brightness: Brightness.dark,
    );
    await tester.ensureVisible(find.text('确认恢复'));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-46/import_review_dark_large.png',
      ),
    );
  });

  testWidgets('取消确认不返回继续标志；只选记账时不提示挑战、设置或团队', (tester) async {
    await _pumpReview(tester, scopes: {ImportDataScope.finance});
    final host = tester.state<_ReviewHostState>(find.byType(_ReviewHost));

    expect(find.text('记账'), findsOneWidget);
    expect(find.textContaining('挑战进度'), findsNothing);
    expect(find.textContaining('偏好设置'), findsNothing);
    expect(find.textContaining('团队数据：'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(host.confirmed, isFalse);
    expect(host.executionCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认后返回继续标志；取消不会触发待执行回调', (tester) async {
    await _pumpReview(tester, scopes: {ImportDataScope.settings});
    final host = tester.state<_ReviewHostState>(find.byType(_ReviewHost));

    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();
    expect(host.confirmed, isTrue);
    expect(host.executionCount, 1);
  });

  testWidgets('规则卡只显示所选范围的特殊写入提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ImportRestoreRulesCard(
              selectedScopes: {ImportDataScope.challenge},
              selectedTeamCount: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('各数据域沿用自己的导入规则'), findsOneWidget);
    expect(find.textContaining('可能覆盖当前挑战进度'), findsOneWidget);
    expect(find.textContaining('偏好设置：'), findsNothing);
    expect(find.text('智能合并'), findsNothing);
  });

  testWidgets('结果回执按数据域区分记录、设置和挑战截图', (tester) async {
    tester.view.physicalSize = const Size(390, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: _previewFontFamily, useMaterial3: true),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 350,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ImportScopeRestoreSummaryList(
                    summaries: [
                      ImportScopeRestoreSummary(
                        scope: ImportDataScope.productivity,
                        kind: ImportScopeRestoreKind.recordChanges,
                        importedCount: 4,
                        updatedCount: 2,
                        skippedCount: 1,
                      ),
                      ImportScopeRestoreSummary(
                        scope: ImportDataScope.settings,
                        kind: ImportScopeRestoreKind.settingsApplied,
                        detailCount: 3,
                      ),
                      ImportScopeRestoreSummary(
                        scope: ImportDataScope.challenge,
                        kind: ImportScopeRestoreKind.challengeRestored,
                        detailCount: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新增 4 · 更新 2 · 跳过 1'), findsOneWidget);
    expect(find.text('已应用 3 项设置'), findsOneWidget);
    expect(find.text('挑战状态已恢复 · 包含 5 项任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Card),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-46/import_scope_result_phone.png',
      ),
    );
  });
}
