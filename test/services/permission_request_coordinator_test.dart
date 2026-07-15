import 'dart:async';

import 'package:CountDownTodo/services/permission_request_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  testWidgets('returns the requested status, invokes callback and hides banner',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));

    var statusReads = 0;
    final requestCompleter = Completer<PermissionStatus>();
    PermissionRequestResult? callbackResult;
    final coordinator = PermissionRequestCoordinator(
      context: context,
      statusReader: (_) async => statusReads++ == 0
          ? PermissionStatus.denied
          : PermissionStatus.granted,
      requester: (_) => requestCompleter.future,
      settingsOpener: (_) async => false,
      onResult: (result) => callbackResult = result,
    );

    final resultFuture = coordinator.request(AppPermissionKind.notification);
    await tester.pump();
    expect(find.text('需要“通知”权限'), findsOneWidget);
    expect(find.text('用于发送待办、课程和专注结束提醒。'), findsOneWidget);

    await tester.tap(find.text('允许并继续'));
    await tester.pump();
    expect(find.text('正在打开“通知”权限'), findsOneWidget);

    requestCompleter.complete(PermissionStatus.granted);
    await tester.pump();
    final result = await resultFuture;
    await tester.pump();

    expect(result.granted, isTrue);
    expect(result.changed, isTrue);
    expect(callbackResult, same(result));
    expect(result.cancelledByUser, isFalse);
    expect(find.text('需要“通知”权限'), findsNothing);
    coordinator.dispose();
  });

  testWidgets(
      'permanently denied permission waits for foreground before checking result',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));

    var statusReads = 0;
    var settingsOpened = false;
    var callbackCalled = false;
    final coordinator = PermissionRequestCoordinator(
      context: context,
      statusReader: (_) async => statusReads++ == 0
          ? PermissionStatus.permanentlyDenied
          : PermissionStatus.granted,
      requester: (_) async => PermissionStatus.denied,
      settingsOpener: (_) async {
        settingsOpened = true;
        return true;
      },
      onResult: (_) => callbackCalled = true,
    );

    final resultFuture = coordinator.request(AppPermissionKind.notification);
    await tester.pump();
    expect(settingsOpened, isFalse);
    expect(find.text('需要“通知”权限'), findsOneWidget);

    await tester.tap(find.text('允许并继续'));
    await tester.pump();
    expect(settingsOpened, isTrue);
    expect(callbackCalled, isFalse);
    expect(statusReads, 1);
    expect(find.text('正在打开“通知”权限'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(callbackCalled, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final result = await resultFuture;
    await tester.pump();

    expect(result.openedSettings, isTrue);
    expect(result.cancelledByUser, isFalse);
    expect(result.granted, isTrue);
    expect(callbackCalled, isTrue);
    expect(statusReads, 2);
    expect(find.text('需要“通知”权限'), findsNothing);
    coordinator.dispose();
  });

  testWidgets('denying the rationale does not open Android permission UI',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));

    var requested = false;
    var settingsOpened = false;
    PermissionRequestResult? callbackResult;
    final coordinator = PermissionRequestCoordinator(
      context: context,
      statusReader: (_) async => PermissionStatus.denied,
      requester: (_) async {
        requested = true;
        return PermissionStatus.granted;
      },
      settingsOpener: (_) async {
        settingsOpened = true;
        return true;
      },
      onResult: (result) => callbackResult = result,
    );

    final resultFuture = coordinator.request(AppPermissionKind.notification);
    await tester.pump();
    await tester.tap(find.text('暂不允许'));
    await tester.pump();
    final result = await resultFuture;

    expect(result.cancelledByUser, isTrue);
    expect(result.granted, isFalse);
    expect(result.openedSettings, isFalse);
    expect(requested, isFalse);
    expect(settingsOpened, isFalse);
    expect(callbackResult, same(result));
    expect(find.text('需要“通知”权限'), findsNothing);
    coordinator.dispose();
  });
}
