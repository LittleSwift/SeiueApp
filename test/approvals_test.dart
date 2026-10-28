import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/approval_controller.dart';
import 'package:seiue_mac/approval_models.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/main.dart';
import 'package:seiue_mac/models.dart';

class PendingApprovalApi extends SeiueApi {
  final pages = <Completer<ApprovalPage>>[];
  final detail = Completer<ApprovalRecord>();
  @override
  Future<ApprovalPage> approvals(
    ApprovalTab tab, {
    int page = 1,
    String status = '',
  }) {
    final result = Completer<ApprovalPage>();
    pages.add(result);
    return result.future;
  }

  @override
  Future<ApprovalRecord> approvalDetail(ApprovalRecord record) => detail.future;
}

const record = ApprovalRecord(
  id: 'record',
  workflowId: 'workflow',
  status: 'pending',
);

void main() {
  test('official modal URL round trips without credentials; hidden fields and unsafe attachments are excluded', () {
    final template = ApprovalTemplate.fromJson({
      'id': 1,
      'school_plugin': {'label': '申请'},
      'fields': [
        {
          'name': 'choice',
          'label': '选项',
          'container': {
            'options': [
              {'value': 'yes', 'label': '同意'},
            ],
          },
        },
        {
          'name': 'hidden',
          'label': '隐藏',
          'container': {'hidden': true},
        },
      ],
    });
    final parsed = template.createUrl;
    expect(parsed.host, 'chalk-c3.seiue.com');
    expect(parsed.queryParameters.keys, ['modal', 'modalQuery']);
    expect(
      Uri.decodeComponent(parsed.queryParameters['modalQuery']!),
      contains('"workflowId":"1"'),
    );
    final value = ApprovalRecord.fromJson({
      'id': 1,
      'field_values': [
        {'field_name': 'choice', 'value': 'yes'},
        {'field_name': 'hidden', 'value': 'secret'},
        {'field_name': 'internal', 'value': 'internal'},
      ],
    }, template: template);
    expect(value.displayedFields.single.text, '同意');
    expect(
      ApprovalFieldValue('files', [
        {'name': 'unsafe', 'url': 'javascript:alert(1)'},
        {'name': 'safe', 'url': 'https://example.com/a.pdf'},
      ]).attachments.single.name,
      'safe',
    );
    expect(approvalStatus('rejected'), '已驳回');
    expect(approvalStatus('refused'), '已拒绝');
  });
  test(
    'status changes and account reset invalidate pending responses',
    () async {
      final api = PendingApprovalApi()
        ..session = CampusSession(
          token: 'test',
          identity: const Identity(
            id: '1',
            name: 'test',
            schoolId: '3',
            role: 'student',
          ),
          expiresAt: DateTime(2099),
        );
      final c = ApprovalController(api, onExpired: (_) {});
      final first = c.selectTab(ApprovalTab.initiated);
      final filter = c.filterStatus('approved');
      api.pages[1].complete(const ApprovalPage([], false, 0));
      await filter;
      api.pages[0].complete(const ApprovalPage([record], true, 20));
      await first;
      expect(c.list.status, 'approved');
      expect(c.list.items, isEmpty);
      expect(c.list.hasMore, isFalse);
      final detail = c.openDetail(record);
      c.reset();
      api.detail.complete(record);
      await detail;
      expect(c.selected, isNull);
      c.dispose();
      api.close();
    },
  );
  test(
    'pagination deduplicates records and preserves newest-first order',
    () async {
      final api = PendingApprovalApi()
        ..session = CampusSession(
          token: 'test',
          identity: const Identity(
            id: '1',
            name: 'test',
            schoolId: '3',
            role: 'student',
          ),
          expiresAt: DateTime(2099),
        );
      final c = ApprovalController(api, onExpired: (_) {});
      final old = ApprovalRecord(
        id: 'old',
        workflowId: 'workflow',
        status: 'approved',
        created: DateTime(2025),
      );
      final recent = ApprovalRecord(
        id: 'new',
        workflowId: 'workflow',
        status: 'approved',
        created: DateTime(2026),
      );
      final first = c.selectTab(ApprovalTab.initiated);
      api.pages[0].complete(ApprovalPage([old, recent], true, 3));
      await first;
      expect(c.list.items.map((r) => r.id), ['new', 'old']);
      final next = c.load(more: true);
      api.pages[1].complete(ApprovalPage([old], false, 2));
      await next;
      expect(c.list.items.map((r) => r.id), ['new', 'old']);
      expect(c.list.hasMore, isFalse);
      expect(c.list.page, 2);
      c.dispose();
      api.close();
    },
  );
  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in [const Size(1440, 900), const Size(800, 600)]) {
      testWidgets(
        'approval tabs, form information and progress ${theme.name} ${size.width}',
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
          c.navigate(Destination.approvals);
          await tester.pumpAndSettle();
          expect(find.text('考勤修改申请'), findsOneWidget);
          await tester.tap(find.text('考勤修改申请'));
          await tester.pumpAndSettle();
          expect(find.text('申请表内容'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('我发起的'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('考勤修改申请'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('审批流程'),
            200,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('approval-detail')),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.text('审批流程'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('返回审批列表'));
          await tester.pumpAndSettle();
          await c.approvals.selectTab(ApprovalTab.copied);
          await tester.pumpAndSettle();
          expect(find.text('暂无审批记录'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
}
