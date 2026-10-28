import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/main.dart';
import 'package:seiue_mac/models.dart';

void main() {
  Future<CampusController> openDemo(
    WidgetTester tester,
    Size size, {
    ThemeMode theme = ThemeMode.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final controller = CampusController()..booting = false;
    controller.setTheme(theme);
    controller.enterDemo();
    await tester.pumpWidget(SeiueApp(controller: controller));
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpAndSettle();
    expect(find.text('工作台'), findsNothing);
    return controller;
  }

  testWidgets(
    'short timetable entry stays readable and clickable above the next course',
    (tester) async {
      final c = await openDemo(tester, const Size(1440, 900));
      final start = c.week.add(const Duration(hours: 8));
      c.lessons = [
        Lesson(
          id: 'short',
          title: '考勤',
          start: start,
          end: start.add(const Duration(minutes: 5)),
        ),
        Lesson(
          id: 'next',
          title: '第一节',
          start: start.add(const Duration(minutes: 5)),
          end: start.add(const Duration(minutes: 45)),
        ),
      ];
      c.navigate(Destination.schedule);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final attendance = find.byKey(const ValueKey('week-lesson-short'));
      final course = find.byKey(const ValueKey('week-lesson-next'));
      final attendanceRect = tester.getRect(attendance);
      final courseRect = tester.getRect(course);
      expect(attendanceRect.height, greaterThanOrEqualTo(24));
      expect(attendanceRect.width, courseRect.width);
      expect(attendanceRect.overlaps(courseRect), isTrue);
      // Click the overlapping area: the attendance entry must be on top.
      await tester.tapAt(Offset(attendanceRect.center.dx, courseRect.top + 3));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('考勤')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  for (final size in [const Size(1440, 900), const Size(800, 600)]) {
    testWidgets('large text and reduced motion at ${size.width}', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await openDemo(tester, size, scale: 1.5);
      expect(tester.takeException(), isNull);
      c.navigate(Destination.notices);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('把好奇心带进校园：秋季读书分享会').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  for (final size in [
    const Size(1440, 900),
    const Size(1000, 760),
    const Size(800, 600),
  ]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('desktop layout ${size.width} ${theme.name}', (tester) async {
        final controller = await openDemo(tester, size, theme: theme);
        expect(tester.takeException(), isNull);
        controller.navigate(Destination.notices);
        await tester.pumpAndSettle();
        expect(find.text('校园通知'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('把好奇心带进校园：秋季读书分享会').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controller.notices.items.first.read, true);
        controller.navigate(Destination.system);
        await tester.pumpAndSettle();
        expect(find.text('课表已更新'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }
  }

  testWidgets('keyboard navigation and inbox search work without network', (
    tester,
  ) async {
    final c = await openDemo(tester, const Size(1440, 900));
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
    expect(c.destination, Destination.notices);
    await tester.enterText(find.byType(TextField), '图书馆开放');
    await tester.pumpAndSettle();
    expect(find.text('校园图书馆开放时间调整'), findsOneWidget);
    expect(find.text('秋季学期课程学习指南'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('login validates fields and provides official login fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    final c = CampusController()..booting = false;
    await tester.pumpWidget(SeiueApp(controller: c));
    await tester.tap(find.text('登录校园'));
    await tester.pumpAndSettle();
    expect(find.text('请输入你的账号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(
      find.text('使用官方网页登录'),
      c.mac.supportsWebLogin ? findsOneWidget : findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
