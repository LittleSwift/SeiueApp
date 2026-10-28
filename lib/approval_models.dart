import 'dart:convert';

import 'models.dart';
import 'subject_models.dart';

enum ApprovalTab { templates, initiated, handling, copied }

const approvalTabLabels = ['发起申请', '我发起的', '我处理的', '抄送我的'];
const approvalStatuses = {
  'pending': '审批中',
  'withdrawn': '已撤回',
  'rejected': '已驳回',
  'refused': '已拒绝',
  'approved': '已通过',
  'verifying': '待销假',
  'verified': '已销假',
  'submitted': '销假待审核',
};
String approvalStatus(String value) =>
    approvalStatuses[value] ??
    switch (value) {
      'denied' => '已拒绝',
      'returned' => '已退回',
      'forwarded' => '已转交',
      'waiting' => '待处理',
      'invalid' => '已失效',
      'stopped' => '已结束',
      _ => value.isEmpty ? '暂无状态' : value,
    };

class ApprovalTemplate {
  const ApprovalTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.category = '',
    this.extension = '',
    this.fields = const [],
  });
  final String id, name, description, category, extension;
  final List<Json> fields;
  factory ApprovalTemplate.fromJson(Json raw) {
    final plugin = jsonMap(raw['school_plugin']);
    final fields = jsonRows(raw['fields'])
      ..sort(
        (a, b) => (num.tryParse(field(a['sort'])) ?? 0).compareTo(
          num.tryParse(field(b['sort'])) ?? 0,
        ),
      );
    return ApprovalTemplate(
      id: field(raw['id']),
      name: field(plugin['label'], '审批申请'),
      description: field(plugin['simple_description']).isEmpty
          ? field(raw['description'])
          : field(plugin['simple_description']),
      category: field(jsonMap(raw['category'])['name'], '其他'),
      extension: field(raw['extension_type']),
      fields: fields,
    );
  }
  String get bizType => extension.isEmpty
      ? 'approval'
      : switch (extension) {
          'seiue.sams:absence' => 'absence',
          'seiue.scms:adjustment' => 'adjustment',
          _ => 'approval',
        };
  Uri get createUrl => approvalWebUrl(
    ApprovalTab.templates,
    modal: 'NewFlowModal',
    parameters: {'workflowId': id, 'workflowBizType': bizType},
  );
}

Uri approvalWebUrl(ApprovalTab tab, {String? modal, Json? parameters}) =>
    Uri.https(
      'chalk-c3.seiue.com',
      '/workflows/center/${switch (tab) {
        ApprovalTab.templates => 'all',
        ApprovalTab.initiated => 'initiated',
        ApprovalTab.handling => 'to-approve',
        ApprovalTab.copied => 'copied',
      }}',
      {
        'modal': ?modal,
        if (parameters != null)
          'modalQuery': Uri.encodeComponent(jsonEncode(parameters)),
      },
    );

class ApprovalRecord {
  const ApprovalRecord({
    required this.id,
    required this.workflowId,
    required this.status,
    this.initiator = '',
    this.created,
    this.finished,
    this.values = const [],
    this.nodes = const [],
    this.template,
  });
  final String id, workflowId, status, initiator;
  final DateTime? created, finished;
  final List<Json> values, nodes;
  final ApprovalTemplate? template;
  String get title => template?.name ?? '审批申请';
  factory ApprovalRecord.fromJson(Json raw, {ApprovalTemplate? template}) =>
      ApprovalRecord(
        id: field(raw['id']),
        workflowId: field(raw['workflow_id']),
        status: field(raw['status']),
        initiator: field(jsonMap(raw['initiator'])['name']),
        created: parseDate(raw['created_at']),
        finished: parseDate(raw['finished_at']),
        values: jsonRows(raw['field_values']),
        nodes: jsonRows(raw['nodes']),
        template: template,
      );
  Uri url(ApprovalTab tab) => approvalWebUrl(
    tab,
    modal: 'ShowFlowModal',
    parameters: {
      'workflowBizType': template?.bizType ?? 'approval',
      'flowId': id,
    },
  );
  List<ApprovalFieldValue> get displayedFields {
    final byName = {for (final v in values) field(v['field_name']): v['value']};
    return [
      for (final f in template?.fields ?? <Json>[])
        if (jsonMap(f['container'])['hidden'] != true &&
            f['type'] != 'paragraph' &&
            byName.containsKey(field(f['name'])))
          ApprovalFieldValue(
            field(f['label'], field(f['name'])),
            byName[field(f['name'])],
            options: jsonRows(jsonMap(f['container'])['options']),
            kind: field(f['type']),
          ),
    ];
  }

  String get pendingPeople => nodes
      .where((n) => n['status'] == 'pending')
      .expand((n) => jsonRows(n['stages']))
      .where((s) => s['status'] == 'pending')
      .map((s) => field(jsonMap(s['reflection'])['name']))
      .where((s) => s.isNotEmpty)
      .toSet()
      .join('、');
}

class ApprovalFieldValue {
  const ApprovalFieldValue(
    this.label,
    this.value, {
    this.options = const [],
    this.kind = '',
  });
  final String label;
  final String kind;
  final dynamic value;
  final List<Json> options;
  String get text => format(value);
  String format(dynamic v) {
    if (v == null || v == '') return '—';
    if (v is List) return v.isEmpty ? '—' : v.map(format).join('、');
    if (v is Map) {
      for (final key in ['label', 'name', 'filename', 'text', 'title']) {
        if (v[key] != null) return '${v[key]}';
      }
      if (v['value'] != null) return format(v['value']);
      return '复杂表单内容，请在官方表单中查看';
    }
    if (v is bool) return v ? '是' : '否';
    for (final option in options) {
      if (field(option['value'] ?? option['name']) == '$v') {
        return field(option['label'], '$v');
      }
    }
    if (['klass', 'reflection', 'student', 'teacher', 'staff'].contains(kind) &&
        RegExp(r'^\d+$').hasMatch('$v')) {
      return '请在官方表单中查看详细名称';
    }
    return '$v';
  }

  List<({String name, String url})> get attachments {
    final result = <({String name, String url})>[];
    void visit(dynamic v) {
      if (v is List) {
        for (final item in v) {
          visit(item);
        }
      }
      if (v is Map) {
        final url = field(v['url'] ?? v['download_url']);
        final parsed = Uri.tryParse(url);
        if (parsed != null &&
            parsed.scheme == 'https' &&
            parsed.host.isNotEmpty) {
          result.add((name: field(v['name'] ?? v['filename'], '附件'), url: url));
        }
      }
    }

    visit(value);
    return result;
  }
}

class ApprovalPage {
  const ApprovalPage(this.items, this.hasMore, this.total);
  final List<ApprovalRecord> items;
  final bool hasMore;
  final int total;
}
