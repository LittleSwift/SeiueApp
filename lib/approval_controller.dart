import 'package:flutter/foundation.dart';

import 'api.dart';
import 'approval_models.dart';

class ApprovalListState {
  List<ApprovalRecord> items = [];
  bool loading = false, hasMore = false, loaded = false;
  String? error;
  String status = '';
  int page = 1, total = 0, generation = 0;
}

class ApprovalController extends ChangeNotifier {
  ApprovalController(this.api, {required this.onExpired});
  final SeiueApi api;
  final void Function(Object) onExpired;
  ApprovalTab tab = ApprovalTab.templates;
  List<ApprovalTemplate> templates = [];
  bool templatesLoading = false, templatesLoaded = false, demo = false;
  String? templatesError;
  final lists = {
    for (final tab in ApprovalTab.values) tab: ApprovalListState(),
  };
  ApprovalRecord? selected;
  bool detailLoading = false;
  String? detailError;
  int _generation = 0, _templateGeneration = 0, _detailGeneration = 0;
  bool _disposed = false;
  ApprovalListState get list => lists[tab]!;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int generation) => !_disposed && generation == _generation;
  void reset({bool demo = false}) {
    _generation++;
    _templateGeneration++;
    _detailGeneration++;
    this.demo = demo;
    tab = ApprovalTab.templates;
    templates = [];
    templatesLoaded = templatesLoading = false;
    templatesError = null;
    for (final t in ApprovalTab.values) {
      lists[t] = ApprovalListState();
    }
    selected = null;
    detailLoading = false;
    detailError = null;
    if (demo) {
      final template = ApprovalTemplate.fromJson({
        'id': 'demo',
        'school_plugin': {
          'label': '考勤修改申请',
          'simple_description': '填写日期、课程及修改原因，提交后由任课教师审批。',
        },
        'category': {'name': '教务教学'},
        'fields': [
          {'name': 'date', 'label': '课程日期'},
          {'name': 'reason', 'label': '申请原因'},
        ],
      });
      templates = [template];
      templatesLoaded = true;
      final record = ApprovalRecord.fromJson({
        'id': 'demo-record',
        'workflow_id': 'demo',
        'status': 'approved',
        'created_at': '2026-10-23 09:00:00',
        'initiator': {'name': '体验同学'},
        'field_values': [
          {'field_name': 'date', 'value': '2026-10-22'},
          {'field_name': 'reason', 'value': '课程签到记录需核对'},
        ],
        'nodes': [
          {
            'node_label': '发起申请',
            'node_type': 'entry',
            'status': 'approved',
            'stages': [
              {
                'reflection': {'name': '体验同学'},
                'status': 'approved',
              },
            ],
          },
          {
            'node_label': '任课教师审批',
            'node_type': 'approval',
            'status': 'approved',
            'stages': [
              {
                'reflection': {'name': '示例教师'},
                'status': 'approved',
                'remark': '已核对课堂记录',
                'reviewed_at': '2026-10-23 10:00:00',
              },
            ],
          },
        ],
      }, template: template);
      lists[ApprovalTab.initiated]!
        ..items = [record]
        ..total = 1
        ..loaded = true;
    }
    _emit();
  }

  Future<void> selectTab(ApprovalTab value) async {
    tab = value;
    closeDetail();
    _emit();
    await load();
  }

  Future<void> filterStatus(String value) async {
    list.status = value;
    if (demo) {
      _emit();
      return;
    }
    list.generation++;
    list.loading = false;
    list.items = [];
    list.loaded = false;
    _emit();
    await load(force: true);
  }

  Future<void> load({bool force = false, bool more = false}) async {
    if (_disposed || demo || api.session == null) return;
    final generation = _generation;
    if (tab == ApprovalTab.templates) {
      if (templatesLoading || (templatesLoaded && !force)) return;
      final ticket = ++_templateGeneration;
      templatesLoading = true;
      templatesError = null;
      _emit();
      try {
        final result = await api.approvalTemplates();
        if (!_valid(generation) || ticket != _templateGeneration) return;
        templates = result;
        templatesLoaded = true;
      } catch (e) {
        if (_valid(generation) && ticket == _templateGeneration) {
          templatesError = _error(e);
          onExpired(e);
        }
      } finally {
        if (_valid(generation) && ticket == _templateGeneration) {
          templatesLoading = false;
          _emit();
        }
      }
      return;
    }
    final currentTab = tab, state = list;
    if (state.loading ||
        (!force && !more && state.loaded) ||
        (more && !state.hasMore)) {
      return;
    }
    final ticket = ++state.generation;
    state.loading = true;
    state.error = null;
    _emit();
    try {
      final page = more ? state.page + 1 : 1;
      final result = await api.approvals(
        currentTab,
        page: page,
        status: state.status,
      );
      if (!_valid(generation) || ticket != state.generation) return;
      state.items = {
        for (final record in [
          ...(more ? state.items : <ApprovalRecord>[]),
          ...result.items,
        ])
          record.id: record,
      }.values.toList();
      state.items.sort(
        (a, b) => (b.created ?? DateTime(1970)).compareTo(
          a.created ?? DateTime(1970),
        ),
      );
      state.page = page;
      state.hasMore = result.hasMore;
      state.total = result.total;
      state.loaded = true;
    } catch (e) {
      if (_valid(generation) && ticket == state.generation) {
        state.error = _error(e);
        onExpired(e);
      }
    } finally {
      if (_valid(generation) && ticket == state.generation) {
        state.loading = false;
        _emit();
      }
    }
  }

  Future<void> openDetail(ApprovalRecord record) async {
    final generation = _generation, ticket = ++_detailGeneration;
    selected = record;
    detailError = null;
    detailLoading = !demo;
    _emit();
    if (demo) return;
    try {
      final result = await api.approvalDetail(record);
      if (!_valid(generation) || ticket != _detailGeneration) return;
      selected = result;
    } catch (e) {
      if (_valid(generation) && ticket == _detailGeneration) {
        detailError = _error(e);
        onExpired(e);
      }
    } finally {
      if (_valid(generation) && ticket == _detailGeneration) {
        detailLoading = false;
        _emit();
      }
    }
  }

  void closeDetail() {
    _detailGeneration++;
    selected = null;
    detailLoading = false;
    detailError = null;
    _emit();
  }

  String _error(Object e) =>
      e is CampusException ? e.message : '审批暂时无法同步，请稍后重试。';
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
