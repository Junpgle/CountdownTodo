import 'dart:io';
import 'dart:ui' as ui;

import 'package:countdown_todo/features/journal/models/journal_entry.dart';
import 'package:countdown_todo/features/journal/screens/journal_trash_screen.dart';
import 'package:countdown_todo/features/journal/services/journal_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _screenshotBoundary = Key('journal-trash-screenshot-boundary');
String? _evidenceFontFamily;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUpAll(() async {
    if (Platform.environment['ROUND47_CAPTURE'] != '1' || !Platform.isMacOS) {
      return;
    }
    final fontFile = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (!await fontFile.exists()) return;
    final fontBytes = await fontFile.readAsBytes();
    await (FontLoader(
      'JournalEvidenceCJK',
    )..addFont(Future.value(ByteData.sublistView(fontBytes)))).load();
    final flutterRoot = _findFlutterRoot();
    final iconsFile = flutterRoot == null
        ? null
        : File(
            '${flutterRoot.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          );
    if (iconsFile != null && await iconsFile.exists()) {
      final iconsBytes = await iconsFile.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(iconsBytes)))).load();
    }
    _evidenceFontFamily = 'JournalEvidenceCJK';
  });

  testWidgets('回收站支持恢复、取消永久删除和确认永久删除', (tester) async {
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    await tester.runAsync(() => DatabaseHelper.ensureJournalSchema(database!));
    addTearDown(() => database!.close());
    final storage = JournalStorage.forTesting(
      databaseLoader: (_) async => database!,
    );
    final restoredEntry = JournalEntry(
      id: 'trash-ui-restore',
      title: '秋日散步',
      content: '沿河走到天色变暗。',
      occurredAt: DateTime(2026, 10, 22, 17),
    );
    final deletedEntry = JournalEntry(
      id: 'trash-ui-delete',
      title: '读书摘记',
      content: '记下今天读到的一段话。',
      occurredAt: DateTime(2026, 10, 20, 21),
    );
    final photoDirectory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('round47-journal-photo-'),
    );
    final photoFile = File('${photoDirectory!.path}/photo.png');
    final photo = JournalAttachment(
      id: 'trash-ui-photo',
      entryId: deletedEntry.id,
      localPath: photoFile.path,
      mimeType: 'image/png',
    );
    await tester.runAsync(() => photoFile.writeAsBytes([10, 20, 30]));
    addTearDown(() async {
      if (await photoDirectory.exists()) {
        await photoDirectory.delete(recursive: true);
      }
    });
    await tester.runAsync(() async {
      await storage.saveEntry(restoredEntry, const [], accountId: 'trash-ui');
      await storage.saveEntry(deletedEntry, [photo], accountId: 'trash-ui');
      await storage.moveEntryToTrash(restoredEntry.id, accountId: 'trash-ui');
      await storage.moveEntryToTrash(deletedEntry.id, accountId: 'trash-ui');
    });

    Future<void> mount({
      Size size = const Size(390, 844),
      Brightness brightness = Brightness.light,
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final captureTheme = ThemeData(
        useMaterial3: true,
        brightness: brightness,
        fontFamily: _evidenceFontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: captureTheme,
          darkTheme: captureTheme,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Theme(
            data: captureTheme,
            child: RepaintBoundary(
              key: _screenshotBoundary,
              child: JournalTrashScreen(
                accountId: 'trash-ui',
                storage: storage,
              ),
            ),
          ),
        ),
      );
      await _waitFor(tester, () => find.text('秋日散步').evaluate().isNotEmpty);
    }

    await mount();
    if (Platform.environment['ROUND47_CAPTURE'] == '1') {
      await _capture(tester, 'journal_trash_phone.png');
      await mount(size: const Size(1440, 960));
      await _capture(tester, 'journal_trash_desktop.png');
      await mount(
        size: const Size(390, 844),
        brightness: Brightness.dark,
        textScale: 1.4,
      );
      await _capture(tester, 'journal_trash_dark_large.png');
    }

    final restoreCard = find.ancestor(
      of: find.text('秋日散步'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(
        of: restoreCard,
        matching: find.widgetWithText(FilledButton, '恢复'),
      ),
    );
    await _waitFor(
      tester,
      () =>
          find.text('秋日散步').evaluate().isEmpty &&
          find.text('读书摘记').evaluate().isNotEmpty,
    );
    expect(
      await tester.runAsync(
        () => storage.loadEntry(restoredEntry.id, accountId: 'trash-ui'),
      ),
      isNotNull,
    );

    final deleteCard = find.ancestor(
      of: find.text('读书摘记'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: deleteCard, matching: find.byTooltip('永久删除')),
    );
    await _waitFor(tester, () => find.text('永久删除这篇日记？').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await _waitFor(tester, () => find.text('永久删除这篇日记？').evaluate().isEmpty);
    expect(find.text('读书摘记'), findsOneWidget);
    expect(await tester.runAsync(photoFile.exists), isTrue);

    await tester.tap(
      find.descendant(of: deleteCard, matching: find.byTooltip('永久删除')),
    );
    await _waitFor(tester, () => find.text('永久删除这篇日记？').evaluate().isNotEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '永久删除').last);
    await _waitFor(tester, () => find.text('回收站空空如也').evaluate().isNotEmpty);
    expect(
      await tester.runAsync(
        () => storage.loadEntry(deletedEntry.id, accountId: 'trash-ui'),
      ),
      isNull,
    );
    expect(
      await tester.runAsync(
        () => storage.loadAttachment(photo.id, accountId: 'trash-ui'),
      ),
      isNull,
    );
    expect(await tester.runAsync(photoFile.exists), isFalse);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenshotBoundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory(
      '${_findProjectRoot().path}/docs/reports/evidence/round-47',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name')
        .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  });
}

Directory? _findFlutterRoot() {
  var directory = File(Platform.resolvedExecutable).absolute.parent;
  for (var attempt = 0; attempt < 8; attempt++) {
    final fontPath =
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    if (File(fontPath).existsSync()) return directory;
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  return null;
}

Directory _findProjectRoot() {
  var directory = Directory.current.absolute;
  for (var attempt = 0; attempt < 12; attempt++) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) return directory;
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  return Directory.current.absolute;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('页面未出现预期的日记回收站状态');
}
