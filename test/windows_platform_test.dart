import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/approval_models.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/main.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/notifications.dart';
import 'package:seiue_mac/platform_services.dart';
import 'package:seiue_mac/windows_notifications.dart';

class WindowsServices extends MacServices {
  @override
  bool get isWindows => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MacServices.channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MacServices.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows approval browser never receives the native session', () async {
    final session = CampusSession.fromJson({
      'access_token': 'private-test-access-token',
      'token_type': 'Bearer',
      'expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'identity': {'id': '17', 'school_id': '3', 'role': 'student'},
    });
    final services = WindowsServices();
    final url = approvalWebUrl(ApprovalTab.initiated);
    await services.openApprovalPortal(url, session);
    expect(calls.single.method, 'openUrl');
    expect(calls.single.arguments, url.toString());
    expect(jsonEncode(calls.single.arguments), isNot(contains(session.token)));
    expect(services.supportsWebLogin, isFalse);
    await expectLater(services.webLogin(), throwsA(isA<PlatformException>()));
    expect(calls.length, 1);
  });

  test('native URL bridge rejects file and shell protocols', () async {
    final services = WindowsServices();
    for (final url in [
      'file:///C:/secret',
      'javascript:alert(1)',
      'cmd:echo',
      'https:relative',
    ]) {
      await services.openUrl(url);
    }
    expect(calls, isEmpty);
    await services.openUrl('https://chalk-c3.seiue.com/');
    expect(calls.single.method, 'openUrl');
  });

  test('persistent notification identifiers isolate accounts and class cancellation', () {
    final first = windowsNotificationId('message:3:student:17:123');
    expect(first, windowsNotificationId('message:3:student:17:123'));
    expect(first, isNot(windowsNotificationId('message:3:student:18:123')));
    expect(first & 0x20000000, 0);
    final course = windowsNotificationId(
      'class:3:student:17:123',
      course: true,
    );
    expect(course & 0x20000000, isNot(0));
    expect(course, lessThan(0x7fffffff));
    expect(
      NotificationPreferences.fromJson({'permission': 'systemManaged'}).allowed,
      isTrue,
    );
    expect(
      NotificationPreferences.fromJson({'permission': 'denied'}).allowed,
      isFalse,
    );
  });

  testWidgets(
    'Windows login advertises DPAPI and no unsupported embedded login',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CampusController(mac: WindowsServices())
        ..booting = false;
      await tester.pumpWidget(SeiueApp(controller: controller));
      expect(find.text('使用官方网页登录'), findsNothing);
      expect(find.text('会话经 Windows 加密保存，不保存密码'), findsOneWidget);
      await tester.tap(find.text('先体验一下  →'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.destination, Destination.approvals);
      expect(find.textContaining('需在浏览器单独登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
