import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/main.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/subject_models.dart';
import 'package:seiue_mac/notification_settings.dart';

const math = CampusSubject(
  id: 'math',
  groupId: 'math-group',
  name: '数学',
  className: '高三1班',
);

class SubjectApi extends SeiueApi {
  final pending = Completer<GradeReport>();
  @override
  Future<GradeReport> subjectGrades(CampusSubject subject) => pending.future;
}

void main() {
  test(
    'grade hierarchy follows parent order and task content retains child tasks',
    () {
      final report = GradeReport.fromJson({
        'items': [
          {'id': 2, 'pid': 1, 'name': '小测', 'sort': 0, 'full_score': '20'},
          {
            'id': 1,
            'pid': 0,
            'name': '课堂表现',
            'type': 'dimension',
            'sort': 1,
            'within_score': '40',
          },
        ],
      }, []);
      expect(report.entries.map((e) => e.name), ['课堂表现', '小测']);
      expect(report.entries.first.isGroup, isTrue);
      expect(report.entries.first.fullScore, '40');
      expect(report.entries.last.depth, 1);
      final task = SubjectTask.fromJson({
        'task_id': 1,
        'title': '阅读',
        'sub_tasks': [
          {'id': 2, 'title': '思考题', 'content': '写下一个问题'},
        ],
      });
      expect(task.subTasks.single.content, '写下一个问题');
    },
  );
  test('maps group subject, zero scores, textual levels and attendance without inventing grades', () {
    final subject = CampusSubject.fromGroup({
      'id': 1,
      'biz_id': '2',
      'name': '数学 高三1班',
      'extra_fields': {'name': '数学', 'class_name': '高三1班'},
      'labels': {'semester_id': 'term'},
    });
    expect(subject.id, '2');
    expect(subject.groupId, '1');
    expect(subject.semesterId, 'term');
    final report = GradeReport.fromJson(
      {
        'status': 'pending',
        'full_score': '100',
        'grade': {'student_real_score': '0', 'level': 'A'},
        'items': [
          {'id': 3, 'name': '小测', 'full_score': '20', 'status': 'published'},
          {'id': 4, 'name': '未评分', 'full_score': '10'},
        ],
      },
      [
        {'item_id': 3, 'score': '0', 'review': '已批阅'},
      ],
    );
    expect(report.score, '0');
    expect(report.entries.first.score, '0');
    expect(report.entries.last.score, '—');
    expect(report.entries.first.review, '已批阅');
    expect(
      AttendanceRecord.fromJson({
        'id': 1,
        'result': '病假',
        'attendance_time_start': '2026-10-23 08:00:00',
        'absence_info': {'reason': '已批准'},
      }).reason,
      '已批准',
    );
    expect(
      SubjectMember.fromJson({
        'member_type': 'teacher',
        'reflection': {'id': 2, 'name': '教师'},
      }).roleLabel,
      '教师',
    );
  });
  testWidgets('late subject response is ignored after disposal', (
    tester,
  ) async {
    final api = SubjectApi();
    final controller = CampusController(api: api)..booting = false;
    controller.session = CampusSession(
      token: 'test',
      identity: const Identity(
        id: 'one',
        name: '同学',
        schoolId: '3',
        role: 'student',
      ),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    controller.selectSubject(math);
    final state = controller.subjectSection;
    // Dispose has the same generation invalidation as logout, without platform calls.
    controller.dispose();
    api.pending.complete(
      const GradeReport(
        score: '1',
        fullScore: '10',
        status: 'published',
        entries: [],
      ),
    );
    await tester.pump();
    expect(state.data, isNull);
  });
  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in [const Size(1440, 900), const Size(800, 600)]) {
      testWidgets(
        'four subject tabs and task reader ${theme.name} ${size.width}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.platformDispatcher.textScaleFactorTestValue = 1.5;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final c = CampusController()..booting = false;
          c.setTheme(theme);
          c.enterDemo();
          await tester.pumpWidget(SeiueApp(controller: c));
          c.selectSubject(c.subjects.first);
          await tester.pumpAndSettle();
          expect(find.text('评价项成绩'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('任务').last);
          await tester.pumpAndSettle();
          expect(find.text('本周阅读与思考'), findsOneWidget);
          await tester.tap(find.text('本周阅读与思考'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('考勤').last);
          await tester.pumpAndSettle();
          expect(find.text('正常 12'), findsOneWidget);
          await tester.tap(find.text('成员').last);
          await tester.pumpAndSettle();
          expect(find.text('体验同学'), findsWidgets);
          expect(tester.takeException(), isNull);
          c.clearSelectedSubject();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          showNotificationSettings(tester.element(find.byType(Scaffold)), c);
          await tester.pumpAndSettle();
          expect(find.text('演示模式不会发送系统提醒'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
}
