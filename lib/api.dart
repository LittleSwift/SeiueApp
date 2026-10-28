import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'subject_models.dart';
import 'approval_models.dart';

class CampusException implements Exception {
  const CampusException(this.message, {this.expired = false, this.statusCode});
  final String message;
  final bool expired;
  final int? statusCode;
  @override
  String toString() => message;
}

class SeiueApi {
  SeiueApi({HttpClient? client, DateTime Function()? now})
    : _client = client ?? HttpClient(),
      _now = now ?? DateTime.now {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.userAgent =
        'SeiueDesktop/0.4.1 (${Platform.operatingSystem}; Flutter)';
  }
  final HttpClient _client;
  final DateTime Function() _now;
  CampusSession? _session;
  CampusSession? get session => _session;
  set session(CampusSession? value) {
    _sessionEpoch++;
    _session = value;
    _cookies
      ..clear()
      ..addAll(value?.passportCookies.where((c) => c.validAt(_now())) ?? []);
    _renewing = null;
  }

  final _cookies = <PassportCookie>[];
  int _sessionEpoch = 0;
  bool _closed = false;
  Future<CampusSession>? _renewing;
  Future<void> Function(CampusSession)? onSessionChanged;
  bool get canRenew => _cookies.any(
    (c) => c.validAt(_now()) && _cookiePathMatches('/authorize', c.path),
  );
  static bool _cookiePathMatches(String request, String path) =>
      request == path ||
      (request.startsWith(path) &&
          (path.endsWith('/') ||
              request.substring(path.length).startsWith('/')));
  void _checkEpoch(int epoch) {
    if (_closed || epoch != _sessionEpoch) {
      throw const CampusException('登录状态已变更，请重试。');
    }
  }

  void close() {
    _closed = true;
    session = null;
    onSessionChanged = null;
    _client.close(force: true);
  }

  /// Like the official web client, reauthorize ten minutes before expiry.
  /// One shared future prevents parallel API calls from rotating the session
  /// independently. A network error never destroys the renewal credentials.
  Future<CampusSession> ensureSession({
    bool force = false,
    String? rejectedToken,
  }) async {
    final current = session;
    if (current == null) throw const CampusException('请重新登录。', expired: true);
    if (rejectedToken != null && rejectedToken != current.token) return current;
    if (!force &&
        current.expiresAt.difference(_now()) >= const Duration(minutes: 10)) {
      return current;
    }
    if (!canRenew) {
      if (!force && current.expiresAt.isAfter(_now())) return current;
      throw const CampusException('登录已过期，请重新登录以建立可自动续期的会话。', expired: true);
    }
    final running = _renewing;
    if (running != null) return running;
    final epoch = _sessionEpoch;
    final future = _renewSession(current, epoch);
    _renewing = future;
    try {
      return await future;
    } finally {
      if (identical(_renewing, future)) _renewing = null;
    }
  }

  Future<CampusSession> _renewSession(CampusSession previous, int epoch) async {
    final response = await _request(
      Uri.https('passport.seiue.com', '/authorize'),
      method: 'POST',
      form: true,
      auth: false,
      renewal: true,
      data: {'response_type': 'token', 'client_id': 'GpxvnjhVKt56qTmnPWH1sA'},
    );
    _checkEpoch(epoch);
    final raw = response.data;
    if (raw is! Map ||
        raw['access_token'] is! String ||
        (raw['access_token'] as String).isEmpty) {
      throw const CampusException('希悦登录会话已失效，请重新登录。', expired: true);
    }
    final lifetime = int.tryParse('${raw['expires_in']}');
    if (lifetime == null || lifetime <= 0) {
      throw const CampusException('希悦返回的续期信息无效，请稍后重试。');
    }
    final updated = CampusSession(
      token: raw['access_token'] as String,
      tokenType: raw['token_type']?.toString() ?? previous.tokenType,
      identity: previous.identity,
      expiresAt: _now().add(Duration(seconds: lifetime)),
      passportCookies: _cookies.where((c) => c.validAt(_now())).toList(),
    );
    _session = updated;
    await onSessionChanged?.call(updated);
    _checkEpoch(epoch);
    return updated;
  }

  Future<({dynamic data, HttpHeaders headers, String body})> _request(
    Uri uri, {
    String method = 'GET',
    Object? data,
    bool form = false,
    bool auth = true,
    int redirects = 0,
    bool renewal = false,
    bool retryUnauthorized = true,
  }) async {
    if (redirects > 8) throw const CampusException('登录跳转异常，请使用网页登录重试。');
    final epoch = _sessionEpoch;
    final business = auth && uri.host == 'api.seiue.com';
    if (business && session != null && session!.identity.id.isNotEmpty) {
      await ensureSession();
    }
    _checkEpoch(epoch);
    final requestSession = session;
    try {
      final request = await _client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 25));
      _checkEpoch(epoch);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (business && requestSession != null) {
        final current = requestSession;
        request.headers.set(
          'Authorization',
          '${current.tokenType} ${current.token}',
        );
        if (current.identity.id.isNotEmpty) {
          request.headers.set('X-Reflection-Id', current.identity.id);
          request.headers.set('X-School-Id', current.identity.schoolId);
          request.headers.set('X-Role', current.identity.role);
        }
      }
      // Authentication cookies are only sent to Passport, never to business
      // APIs, school pages, attachments or an arbitrary redirect destination.
      if (uri.scheme == 'https' && uri.host == 'passport.seiue.com') {
        for (final cookie in _cookies.where(
          (c) => c.validAt(_now()) && _cookiePathMatches(uri.path, c.path),
        )) {
          request.cookies.add(Cookie(cookie.name, cookie.value));
        }
      }
      if (data != null) {
        request.headers.contentType = form
            ? ContentType(
                'application',
                'x-www-form-urlencoded',
                charset: 'utf-8',
              )
            : ContentType.json;
        request.write(
          form
              ? Uri(
                  queryParameters: (data as Map).map(
                    (key, value) => MapEntry('$key', '$value'),
                  ),
                ).query
              : jsonEncode(data),
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      _checkEpoch(epoch);
      if (uri.host == 'passport.seiue.com') {
        for (final cookie in response.cookies) {
          final saved = PassportCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain ?? uri.host,
            path: cookie.path ?? '/',
            secure: cookie.secure,
            httpOnly: cookie.httpOnly,
            expiresAt: cookie.maxAge == null
                ? cookie.expires
                : _now().add(Duration(seconds: cookie.maxAge!)),
          );
          if (!saved.allowed) continue;
          _cookies.removeWhere(
            (old) =>
                old.name == saved.name &&
                old.domain.replaceFirst(RegExp(r'^\.'), '') ==
                    saved.domain.replaceFirst(RegExp(r'^\.'), '') &&
                old.path == saved.path,
          );
          if (saved.validAt(_now())) _cookies.add(saved);
        }
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      if (response.isRedirect ||
          [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location != null) {
          if (renewal) {
            throw const CampusException('希悦登录会话已失效，请重新登录。', expired: true);
          }
          final next = uri.resolve(location);
          if (next.scheme != 'https' ||
              !(next.host == 'seiue.com' || next.host.endsWith('.seiue.com'))) {
            throw const CampusException('登录返回了未知站点，请使用官方网页登录。');
          }
          final preserve =
              response.statusCode == 307 || response.statusCode == 308;
          return await _request(
            next,
            method: preserve ? method : 'GET',
            data: preserve ? data : null,
            form: form,
            auth: auth,
            redirects: redirects + 1,
            retryUnauthorized: retryUnauthorized,
          );
        }
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        decoded = null;
      }
      _checkEpoch(epoch);
      if (renewal && [400, 401, 403].contains(response.statusCode)) {
        throw const CampusException('希悦登录会话已失效，请重新登录。', expired: true);
      }
      if (response.statusCode == 401) {
        if (business && requestSession != null && retryUnauthorized) {
          await ensureSession(force: true, rejectedToken: requestSession.token);
          _checkEpoch(epoch);
          return await _request(
            uri,
            method: method,
            data: data,
            form: form,
            auth: auth,
            redirects: redirects,
            retryUnauthorized: false,
          );
        }
        if (!auth) {
          throw const CampusException('账号或密码不正确，或登录需要验证。请检查后重试，也可使用官方网页登录。');
        }
        throw const CampusException('登录已过期，请重新登录。', expired: true);
      }
      if (response.statusCode >= 400) {
        throw CampusException(
          response.statusCode == 403
              ? '暂时没有访问权限，请检查学校及身份。'
              : '服务器请求失败（${response.statusCode}），请稍后重试。',
          statusCode: response.statusCode,
        );
      }
      return (data: decoded, headers: response.headers, body: body);
    } on CampusException {
      rethrow;
    } on TimeoutException {
      throw const CampusException('连接超时，请检查网络后重试。');
    } on SocketException {
      throw const CampusException('无法连接希悦，请检查网络后重试。');
    } on HandshakeException {
      throw const CampusException('无法建立安全连接，请检查系统时间和网络。');
    }
  }

  Future<CampusSession> login(String account, String password) async {
    session = null;
    final uri = Uri.https('passport.seiue.com', '/login', {
      'school_id': '3',
      'type': 'account',
    });
    await _request(uri, auth: false);
    final response = await _request(
      uri,
      method: 'POST',
      auth: false,
      form: true,
      data: {'email': account.trim(), 'password': password, 'school_id': '3'},
    );
    if (response.body.contains('captchaImg') &&
        response.body.contains('login-form')) {
      throw const CampusException('登录未完成，请检查账号密码；如需验证码，请选择“使用官方网页登录”。');
    }
    final authorized = await _request(
      Uri.https('passport.seiue.com', '/authorize'),
      method: 'POST',
      form: true,
      auth: false,
      data: {'response_type': 'token', 'client_id': 'GpxvnjhVKt56qTmnPWH1sA'},
    );
    if (authorized.data is! Map || authorized.data['access_token'] == null) {
      throw const CampusException('登录未完成，请使用官方网页登录。');
    }
    return acceptToken(Map<String, dynamic>.from(authorized.data));
  }

  Future<CampusSession> acceptToken(Json token) async {
    final provisional = CampusSession(
      token: token['access_token'] as String,
      tokenType: token['token_type']?.toString() ?? 'Bearer',
      passportCookies: token['passport_cookies'] is List
          ? (token['passport_cookies'] as List)
                .whereType<Map>()
                .map(
                  (c) => PassportCookie.fromJson(Map<String, dynamic>.from(c)),
                )
                .where((c) => c.validAt(_now()))
                .toList()
          : _cookies.where((c) => c.validAt(_now())).toList(),
      identity: const Identity(
        id: '',
        name: '',
        schoolId: '3',
        role: 'student',
      ),
      expiresAt: _now().add(
        Duration(seconds: int.tryParse('${token['expires_in']}') ?? 3600),
      ),
    );
    session = provisional;
    try {
      final response = await _request(
        Uri.https('api.seiue.com', '/chalk/oauth/info', {
          'expand': 'reflections',
        }),
      );
      final info = response.data as Json;
      late final Identity identity;
      try {
        identity = selectIdentity(
          info['reflections'] as List? ?? [],
          token['active_reflection_id'],
        );
      } on FormatException {
        throw const CampusException('此账号没有北大附中（高中本部）的可用身份。');
      }
      final result = CampusSession(
        token: provisional.token,
        tokenType: provisional.tokenType,
        identity: identity,
        expiresAt: provisional.expiresAt,
        passportCookies: _cookies.where((c) => c.validAt(_now())).toList(),
      );
      _session = result;
      return result;
    } catch (_) {
      session = null;
      rethrow;
    }
  }

  Future<List<Lesson>> lessons(DateTime week) async {
    final start = mondayOf(week);
    String timestamp(DateTime date) => '${dayKey(date)} 00:00:00';
    final response = await _request(
      Uri.https(
        'api.seiue.com',
        '/chalk/calendar/personals/${session!.identity.id}/events',
        {
          'start_time': timestamp(start),
          'end_time': timestamp(start.add(const Duration(days: 7))),
          'expand': 'address,initiators',
        },
      ),
    );
    if (response.data is! List) throw const CampusException('课表数据格式已变更，请稍后重试。');
    return (response.data as List)
        .whereType<Map>()
        .map((raw) => Lesson.fromJson(Map<String, dynamic>.from(raw)))
        .whereType<Lesson>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<List<CampusSubject>> subjects() async {
    final semester = await _request(
      Uri.https('api.seiue.com', '/chalk/system/semesters/current'),
    );
    final semesterId = field(jsonMap(semester.data)['id']);
    final items = <CampusSubject>[];
    var page = 1;
    while (true) {
      final response = await _request(
        Uri.https(
          'api.seiue.com',
          '/chalk/group/reflections/${session!.identity.id}/groups',
          {
            'enhancer': 'seiue.class_group',
            'semester_id': semesterId,
            'page': '$page',
            'per_page': '100',
          },
        ),
      );
      if (response.data is! List) throw const CampusException('科目数据格式已变更。');
      items.addAll(
        jsonRows(response.data)
            .where((r) => r['type'] == 'seiue.class_group')
            .map(CampusSubject.fromGroup),
      );
      if (!_hasMore(response.headers, page, (response.data as List).length)) {
        break;
      }
      page++;
    }
    return items;
  }

  bool _hasMore(HttpHeaders headers, int page, int count, {int size = 100}) {
    final pages = int.tryParse(headers.value('x-pagination-page-count') ?? '');
    return pages == null ? count >= size : page < pages;
  }

  Future<GradeReport> subjectGrades(CampusSubject subject) async {
    try {
      final response = await _request(
        Uri.https(
          'api.seiue.com',
          '/vnas/klass/personal/class/${subject.id}/assessments',
          {
            'owner_id': session!.identity.id,
            'expand': 'items,grade,assessment_stages',
          },
        ),
      );
      if (response.data is! Map) throw const CampusException('成绩数据格式已变更。');
      final assessment = jsonMap(response.data);
      final scores = await _request(
        Uri.https(
          'api.seiue.com',
          '/vnas/personal/assessments/${assessment['id']}/achieved-scores',
          {'owner_id': session!.identity.id, 'paginated': '0'},
        ),
      );
      if (scores.data is! List) throw const CampusException('成绩明细格式已变更。');
      return GradeReport.fromJson(assessment, jsonRows(scores.data));
    } on CampusException catch (error) {
      if (error.statusCode == 404) {
        return const GradeReport(
          score: '—',
          fullScore: '—',
          status: '',
          entries: [],
        );
      }
      rethrow;
    }
  }

  Future<SubjectPage<SubjectTask>> subjectTasks(
    CampusSubject subject, {
    int page = 1,
  }) async {
    final response = await _request(
      Uri.https(
        'api.seiue.com',
        '/chalk/task/v2/assignees/${session!.identity.id}/assigned-tasks',
        {
          'domain': 'group',
          'domain_biz_id_in': subject.groupId,
          'general_status_in': 'published,finished',
          'parent_task_id_is_empty': 'true',
          'expand': 'creator,outline,sub_tasks',
          'sort': '-published_at,-created_at',
          'page': '$page',
          'per_page': '100',
        },
      ),
    );
    if (response.data is! List) throw const CampusException('任务数据格式已变更。');
    return SubjectPage(
      jsonRows(response.data).map(SubjectTask.fromJson).toList(),
      _hasMore(response.headers, page, (response.data as List).length),
    );
  }

  Future<AttendancePage> subjectAttendance(
    CampusSubject subject, {
    int page = 1,
  }) async {
    final results = await Future.wait([
      _request(
        Uri.https(
          'api.seiue.com',
          '/sams/attendance/personal/classes/${subject.id}/records',
          {
            'owner_id': session!.identity.id,
            'expand': 'class_lesson,absence_info',
            'sort': '-attendance_time_start',
            'page': '$page',
            'per_page': '100',
          },
        ),
      ),
      _request(
        Uri.https(
          'api.seiue.com',
          '/sams/attendance/personal/classes/${subject.id}/attendance-statistics',
          {'owner_id': session!.identity.id},
        ),
      ),
    ]);
    if (results.first.data is! List) throw const CampusException('考勤数据格式已变更。');
    return AttendancePage(
      jsonRows(results.first.data).map(AttendanceRecord.fromJson).toList(),
      _hasMore(
        results.first.headers,
        page,
        (results.first.data as List).length,
      ),
      jsonMap(results.last.data).map(
        (key, value) =>
            MapEntry(key, int.tryParse(field(jsonMap(value)['amount'])) ?? 0),
      ),
    );
  }

  Future<SubjectPage<SubjectMember>> subjectMembers(
    CampusSubject subject, {
    int page = 1,
  }) async {
    final response = await _request(
      Uri.https(
        'api.seiue.com',
        '/chalk/group/groups/${subject.groupId}/members',
        {
          'expand': 'reflection',
          'sort': '-member_type,member_id',
          'page': '$page',
          'per_page': '100',
        },
      ),
    );
    if (response.data is! List) throw const CampusException('成员数据格式已变更。');
    return SubjectPage(
      jsonRows(response.data).map(SubjectMember.fromJson).toList(),
      _hasMore(response.headers, page, (response.data as List).length),
    );
  }

  static const _approvalExcluded =
      'seiue.scms:adjustment,seiue.sams:absence_verification,seiue.nuwa:no-code,seiue.chalk:event,seiue.form:cultural_platform,seiue.sgms:psychological_evaluation_workflow,seiue.sgms:psychological_intervention_workflow';

  Future<List<ApprovalTemplate>> approvalTemplates({List<String>? ids}) async {
    final response = await _request(
      Uri.https('api.seiue.com', '/form/workflow/workflows', {
        if (ids != null)
          'id_in': ids.join(',')
        else ...{
          'school_plugin.enabled': 'true',
          'is_active': 'true',
          'extension_type_not_in': _approvalExcluded,
          'sort': '-school_plugin_id',
        },
        'paginated': '0',
        'expand': 'category,school_plugin',
      }),
    );
    if (response.data is! List) throw const CampusException('审批类型数据格式已变更。');
    return jsonRows(response.data).map(ApprovalTemplate.fromJson).toList();
  }

  Future<ApprovalPage> approvals(
    ApprovalTab tab, {
    int page = 1,
    String status = '',
  }) async {
    final response = await _request(
      Uri.https('api.seiue.com', '/form/workflow/involved-stages', {
        'stage.node_type_in': switch (tab) {
          ApprovalTab.initiated => 'entry',
          ApprovalTab.handling => 'approval,handle',
          ApprovalTab.copied => 'cc',
          ApprovalTab.templates => 'entry',
        },
        'extension_type_not_in': _approvalExcluded,
        'expand': 'initiator,tags,nodes,nodes.stages,nodes.stages.reflection',
        'sort': '-created_at',
        'page': '$page',
        'per_page': '30',
        if (status.isNotEmpty) 'status': status,
      }),
    );
    if (response.data is! List) throw const CampusException('审批记录数据格式已变更。');
    final rows = jsonRows(response.data);
    final ids = rows.map((r) => field(r['workflow_id'])).toSet().toList();
    final templates = ids.isEmpty
        ? <ApprovalTemplate>[]
        : await approvalTemplates(ids: ids);
    final byId = {for (final t in templates) t.id: t};
    return ApprovalPage(
      rows
          .map(
            (r) => ApprovalRecord.fromJson(
              r,
              template: byId[field(r['workflow_id'])],
            ),
          )
          .toList(),
      _hasMore(response.headers, page, rows.length, size: 30),
      int.tryParse(response.headers.value('x-pagination-total-count') ?? '') ??
          rows.length,
    );
  }

  Future<ApprovalRecord> approvalDetail(ApprovalRecord record) async {
    final response = await _request(
      Uri.https(
        'api.seiue.com',
        '/form/workflow/flows/${Uri.encodeComponent(record.id)}',
        {
          'expand': 'initiator,tags,nodes,nodes.comments,nodes.comments.reflection,nodes.stages,nodes.stages.reflection,nodes.stages.returned_reflections,nodes.stages.forwarded_reflection',
        },
      ),
    );
    if (response.data is! Map) throw const CampusException('审批详情数据格式已变更。');
    final templates = await approvalTemplates(ids: [record.workflowId]);
    return ApprovalRecord.fromJson(
      jsonMap(response.data),
      template: templates.isEmpty ? record.template : templates.first,
    );
  }

  Future<MessagePage> messages({
    required bool system,
    int page = 1,
    bool unread = false,
  }) async {
    final response = await _request(
      Uri.https('api.seiue.com', '/chalk/me/received-messages', {
        'owner.id': session!.identity.id,
        'sort': '-published_at,-created_at',
        'page': '$page',
        'per_page': '30',
        if (system) 'notice': '1' else 'type': 'message',
        if (!system) 'notice': '0',
        if (unread) 'readed': '0',
        'expand': system ? 'aggregated_messages' : 'sender_reflection',
      }),
    );
    if (response.data is! List) throw const CampusException('消息数据格式已变更，请稍后重试。');
    final items =
        (response.data as List)
            .whereType<Map>()
            .map(
              (raw) => CampusMessage.fromJson(
                Map<String, dynamic>.from(raw),
                system: system,
              ),
            )
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));
    final pageCount = int.tryParse(
      response.headers.value('x-pagination-page-count') ?? '',
    );
    return MessagePage(
      items,
      pageCount == null ? items.length >= 30 : page < pageCount,
    );
  }

  Future<void> markRead(CampusMessage message) async {
    await _request(
      Uri.https('api.seiue.com', '/chalk/me/received-messages/${message.id}'),
      method: 'PATCH',
      data: {'readed': true},
    );
  }

  Future<CampusMessage> message(String id, {required bool system}) async {
    final response = await _request(
      Uri.https('api.seiue.com', '/chalk/me/received-messages/$id'),
    );
    if (response.data is! Map) throw const CampusException('通知详情暂时无法加载，请重试。');
    return CampusMessage.fromJson(
      Map<String, dynamic>.from(response.data),
      system: system,
    );
  }
}
