import 'dart:io';

import 'package:countdown_todo/models/data_export_models.dart';
import 'package:countdown_todo/screens/settings/widgets/import_scope_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewFontFamily = 'Round45ImportPreview';
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
    ImportTypePreview(
      key: 'todo_plan_blocks',
      label: '规划区块',
      count: 1,
      deletedCount: 1,
    ),
    ImportTypePreview(key: 'courses', label: '课表', count: 1),
    ImportTypePreview(
      key: 'habits',
      label: '习惯与睡眠训练',
      count: 2,
      deletedCount: 1,
    ),
    ImportTypePreview(key: 'finance', label: '记账数据', count: 6),
    ImportTypePreview(key: 'thirty_day_challenge', label: '30 天挑战', count: 1),
    ImportTypePreview(key: 'settings', label: '偏好设置', count: 2),
  ];
  return ImportPreview(
    fileVersion: 2,
    exportedAt: DateTime(2026, 10, 24),
    types: types,
    scopes: [
      ImportScopePreview(
        scope: ImportDataScope.productivity,
        types: types
            .where(
              (type) => type.key == 'todos' || type.key == 'todo_plan_blocks',
            )
            .toList(),
      ),
      ImportScopePreview(
        scope: ImportDataScope.courses,
        types: types.where((type) => type.key == 'courses').toList(),
      ),
      ImportScopePreview(
        scope: ImportDataScope.habits,
        types: types.where((type) => type.key == 'habits').toList(),
      ),
      ImportScopePreview(
        scope: ImportDataScope.finance,
        types: types.where((type) => type.key == 'finance').toList(),
      ),
      ImportScopePreview(
        scope: ImportDataScope.challenge,
        types: types
            .where((type) => type.key == 'thirty_day_challenge')
            .toList(),
      ),
      ImportScopePreview(
        scope: ImportDataScope.settings,
        types: types.where((type) => type.key == 'settings').toList(),
      ),
    ],
    unsupportedKeys: const ['future_domain'],
  );
}

class _SelectorHost extends StatefulWidget {
  final ImportPreview preview;

  const _SelectorHost({required this.preview});

  @override
  State<_SelectorHost> createState() => _SelectorHostState();
}

class _SelectorHostState extends State<_SelectorHost> {
  late Set<ImportDataScope> _selectedScopes = widget.preview.scopes
      .map((scope) => scope.scope)
      .toSet();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ImportScopeSelector(
      preview: widget.preview,
      selectedScopes: _selectedScopes,
      onSelectionChanged: (scopes) => setState(() => _selectedScopes = scopes),
    ),
  );
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
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
        child: Scaffold(body: _SelectorHost(preview: _preview())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadPreviewFonts);

  testWidgets('手机恢复范围选择截图', (tester) async {
    await _pumpSelector(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-45/import_scope_selector_phone.png',
      ),
    );
  });

  testWidgets('桌面恢复范围选择截图', (tester) async {
    await _pumpSelector(tester, size: const Size(1280, 900));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-45/import_scope_selector_desktop.png',
      ),
    );
  });

  testWidgets('深色大字号恢复范围选择截图', (tester) async {
    await _pumpSelector(
      tester,
      size: const Size(320, 740),
      textScale: 1.6,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/reports/evidence/round-45/import_scope_selector_dark_large.png',
      ),
    );
  });

  testWidgets('范围选择展示准确汇总、设置提示和不支持的数据段', (tester) async {
    await _pumpSelector(tester);

    expect(find.text('已选 6 个数据域 · 15 项'), findsOneWidget);
    expect(find.textContaining('包含偏好设置'), findsOneWidget);
    expect(find.text('当前版本不会导入以下数据段'), findsOneWidget);
    expect(find.text('future_domain'), findsOneWidget);

    final financeTile = find.byKey(
      const PageStorageKey<ImportDataScope>(ImportDataScope.finance),
    );
    await tester.ensureVisible(financeTile);
    await tester.tap(financeTile);
    await tester.pumpAndSettle();
    expect(find.text('记账数据'), findsOneWidget);

    final settingsCheckbox = find.byType(Checkbox).last;
    await tester.ensureVisible(settingsCheckbox);
    await tester.tap(settingsCheckbox);
    await tester.pumpAndSettle();
    expect(find.text('已选 5 个数据域 · 13 项'), findsOneWidget);
    expect(find.textContaining('包含偏好设置'), findsNothing);
  });

  testWidgets('清空与全选可切换，窄屏大字号无布局异常', (tester) async {
    await _pumpSelector(tester, size: const Size(320, 740), textScale: 1.8);

    await tester.ensureVisible(find.text('清空'));
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个数据域 · 0 项'), findsOneWidget);

    await tester.ensureVisible(find.text('全选'));
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 6 个数据域 · 15 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
