import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api.dart';
import 'approval_controller.dart';
import 'demo.dart';
import 'models.dart';
import 'notice_cache.dart';
import 'notice_images.dart';
import 'platform_services.dart';
import 'subject_models.dart';
import 'notifications.dart';

enum Destination { schedule, notices, system, subjects, approvals }

class SubjectSectionState {
  bool loading = false, hasMore = false;
  String? error;
  Object? data;
  int page = 1, generation = 0;
}

class InboxState {
  List<CampusMessage> items = [];
  bool loading = false,
      moreLoading = false,
      hasMore = false,
      unreadOnly = false;
  bool prefetching = false, historyComplete = false;
  String? error, cacheError;
  DateTime? synced;
  int page = 1, generation = 0;
}

class CampusController extends ChangeNotifier with WidgetsBindingObserver {
  CampusController({
    SeiueApi? api,
    MacServices? mac,
    NoticeTextCache? cache,
    NoticeImagePreloader? images,
  }) : api = api ?? SeiueApi(),
       mac = mac ?? MacServices(),
       images = images ?? NoticeImagePreloader() {
    approvals = ApprovalController(this.api, onExpired: _handleError)
      ..addListener(_emit);
    this.api.onSessionChanged = _sessionRenewed;
    notifications = NotificationCoordinator(this.mac);
    this.cache =
        cache ??
        NoticeTextCache(
          directory: () async {
            final path = await this.mac.applicationSupportPath();
            if (path == null) throw const FileSystemException('通知缓存目录不可用');
            return Directory(path);
          },
        );
  }
  final SeiueApi api;
  late final ApprovalController approvals;
  bool approvalPortalOpening = false;
  String? approvalPortalError;
  final MacServices mac;
  final NoticeImagePreloader images;
  late final NoticeTextCache cache;
  late final NotificationCoordinator notifications;
  List<CampusSubject> subjects = [];
  CampusSubject? selectedSubject;
  SubjectTab subjectTab = SubjectTab.grades;
  final subjectSections = <String, SubjectSectionState>{};
  bool subjectsLoading = false;
  String? subjectsError, notificationError;
  String? notificationTestStatus;
  int _subjectsGeneration = 0;
  bool _polling = false, _syncingReminders = false;
  int _pollCount = 0;
  CampusMessage? notificationMessage;
  SubjectSectionState get subjectSection => subjectSections.putIfAbsent(
    '${selectedSubject?.id}:${subjectTab.name}',
    SubjectSectionState.new,
  );
  Destination destination = Destination.schedule;
  ThemeMode themeMode = ThemeMode.light;
  CampusSession? session;
  bool demo = false,
      booting = true,
      authenticating = false,
      remember = false,
      expired = false;
  String? loginError, scheduleError, sessionStorageError;
  Future<void> _sessionWrites = Future.value();
  DateTime week = mondayOf(DateTime.now()), selectedDay = DateTime.now();
  DateTime? scheduleSynced;
  List<Lesson> lessons = [];
  final notices = InboxState(), system = InboxState();
  bool scheduleLoading = false;
  int _scheduleGeneration = 0, _authGeneration = 0;
  Timer? _timer;
  bool _disposed = false;
  bool get signedIn => session != null || demo;
  String get displayName => demo ? '体验同学' : session?.identity.name ?? '同学';
  InboxState get inbox => destination == Destination.system ? system : notices;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int auth) => !_disposed && auth == _authGeneration;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final restored = await mac.restoreSession();
      if (restored != null) {
        session = restored;
        api.session = restored;
        remember = true;
        await _restoreCache();
      }
    } catch (_) {
      loginError = '无法恢复登录状态，请重新登录。';
    }
    booting = false;
    _emit();
    if (signedIn) {
      await _setupNotifications();
      await refreshAll();
      _startPolling();
      unawaited(_requestNotificationPermission());
    }
  }

  Future<void> _sessionRenewed(CampusSession updated) async {
    final previous = session, auth = _authGeneration;
    if (_disposed ||
        expired ||
        previous == null ||
        previous.identity.id != updated.identity.id ||
        previous.identity.schoolId != updated.identity.schoolId) {
      return;
    }
    session = updated;
    _emit();
    if (remember) await _saveRenewedSession(updated, auth);
  }

  Future<void> _saveRenewedSession(CampusSession updated, int auth) {
    final write = _sessionWrites.catchError((_) {}).then((_) async {
      if (!_current(auth) ||
          !remember ||
          !identical(session, updated) ||
          expired) {
        return;
      }
      try {
        await mac.saveSession(updated);
        if (_current(auth)) sessionStorageError = null;
      } catch (_) {
        if (_current(auth)) sessionStorageError = '登录状态更新未能保存，关闭应用后可能需要重新登录。';
      }
      if (_current(auth)) _emit();
    });
    _sessionWrites = write;
    return write;
  }

  Future<void> retrySessionSave() async {
    if (session != null && remember && !expired) {
      await _saveRenewedSession(session!, _authGeneration);
    }
  }

  Future<void> _resumeSession() async {
    final auth = _authGeneration;
    try {
      await api.ensureSession();
    } catch (error) {
      if (_current(auth)) {
        _handleError(error);
        _emit();
      }
    }
  }

  Future<void> _restoreCache() async {
    final identity = session!.identity, auth = _authGeneration;
    await Future.wait(
      [false, true].map((isSystem) async {
        final state = isSystem ? system : notices;
        try {
          final stored = await cache.read(identity, system: isSystem);
          if (!_current(auth)) return;
          state.items = stored.items;
          state.historyComplete = stored.complete;
          state.cacheError = null;
        } catch (_) {
          if (_current(auth)) state.cacheError = '本地文字缓存读取失败，可联网后重试。';
        }
      }),
    );
  }

  Future<void> login({
    String? account,
    String? password,
    bool web = false,
  }) async {
    if (authenticating) return;
    authenticating = true;
    loginError = null;
    _emit();
    try {
      final result = web
          ? await api.acceptToken(await mac.webLogin())
          : await api.login(account!, password!);
      if (remember) {
        await mac.saveSession(result);
      } else {
        await mac.clearSession();
      }
      session = result;
      demo = false;
      expired = false;
      sessionStorageError = null;
      _authGeneration++;
      approvals.reset();
      approvalPortalError = null;
      images.reset();
      lessons = [];
      notices.items = [];
      system.items = [];
      await _restoreCache();
      await _setupNotifications();
      _emit();
      await refreshAll();
      _startPolling();
      unawaited(_requestNotificationPermission());
    } catch (error) {
      loginError = error is CampusException
          ? error.message
          : '登录未完成，请重试或使用官方网页登录。';
      if (!mac.supportsWebLogin && loginError!.contains('网页登录')) {
        loginError = '登录未完成，请检查账号密码后重试。Windows 版暂不支持需要验证码的网页登录，此类登录请暂用希悦官方网页。';
      }
      if (session == null) api.session = null;
    } finally {
      authenticating = false;
      _emit();
    }
  }

  void enterDemo() {
    _authGeneration++;
    _scheduleGeneration++;
    images.reset();
    demo = true;
    approvals.reset(demo: true);
    session = null;
    expired = false;
    destination = Destination.schedule;
    notices.unreadOnly = system.unreadOnly = false;
    notices.prefetching = system.prefetching = false;
    lessons = demoLessons(week);
    subjects = {
      for (final lesson in lessons)
        lesson.title: CampusSubject(
          id: lesson.title,
          groupId: 'demo',
          name: lesson.title,
          className: lesson.group,
        ),
    }.values.toList();
    selectedSubject = null;
    subjectSections.clear();
    notices.items = demoMessages(false);
    system.items = demoMessages(true);
    scheduleSynced = notices.synced = system.synced = DateTime.now();
    _emit();
  }

  void navigate(Destination value) {
    destination = value;
    if (value == Destination.approvals) unawaited(approvals.load());
    _emit();
  }

  void setTheme(ThemeMode value) {
    themeMode = value;
    _emit();
  }

  void setRemember(bool value) {
    remember = value;
    _emit();
  }

  Future<void> _setupNotifications() async {
    if (session == null || demo) return;
    final authGeneration = _authGeneration, currentSession = session!;
    await notifications.configure();
    if (!_current(authGeneration) || session != currentSession) return;
    await notifications.activate(currentSession.identity);
    if (!_current(authGeneration) || session != currentSession) return;
    notificationError = notifications.error;
    mac.onNotificationOpened((info) async {
      if (session == null ||
          info['account'] != notificationAccount(session!.identity)) {
        return;
      }
      final target = info['destination'];
      notificationMessage = null;
      destination = target == 'system'
          ? Destination.system
          : target == 'notices'
          ? Destination.notices
          : Destination.schedule;
      if (destination == Destination.schedule) {
        week = mondayOf(DateTime.now());
        selectedDay = DateTime.now();
        unawaited(loadSchedule());
      }
      if (destination != Destination.schedule) {
        final id = info['messageId']?.toString(), auth = _authGeneration;
        final matches = inbox.items.where((m) => m.id == id);
        if (matches.isNotEmpty) {
          notificationMessage = matches.first;
        } else if (id != null && id.isNotEmpty) {
          try {
            final item = await api.message(
              id,
              system: destination == Destination.system,
            );
            if (!_current(auth)) return;
            notificationMessage = item;
            _merge(inbox, [item]);
          } catch (_) {}
        }
      }
      _emit();
    });
    try {
      await mac.notificationsReady();
    } catch (_) {}
  }

  Future<void> _requestNotificationPermission() async {
    if (session == null || demo) return;
    final auth = _authGeneration;
    await notifications.configure(request: true);
    if (!_current(auth) || session == null) return;
    notificationError = notifications.error;
    await syncReminders();
    _emit();
  }

  Future<void> updateNotificationPreferences({
    required bool classes,
    required bool messages,
    bool request = false,
  }) async {
    try {
      if (request) await notifications.configure(request: true);
      await notifications.setPreferences(classes: classes, messages: messages);
      notificationError = notifications.error;
      if (!demo && classes) await syncReminders();
    } catch (_) {
      notificationError = '提醒设置未保存，请重试。';
    }
    _emit();
  }

  Future<void> syncReminders() async {
    if (_syncingReminders ||
        session == null ||
        demo ||
        expired ||
        !notifications.preferences.allowed ||
        !notifications.preferences.classes) {
      return;
    }
    _syncingReminders = true;
    final auth = _authGeneration, currentWeek = mondayOf(DateTime.now());
    try {
      final weeks = await Future.wait([
        api.lessons(currentWeek),
        api.lessons(currentWeek.add(const Duration(days: 7))),
      ]);
      if (!_current(auth)) return;
      await notifications.schedule(weeks.expand((e) => e));
      await notifications.configure();
      notificationError = null;
    } catch (error) {
      if (_current(auth)) {
        notificationError = '课前提醒同步失败，请刷新重试。';
        _handleError(error);
      }
    } finally {
      _syncingReminders = false;
      if (_current(auth)) _emit();
    }
  }

  Future<void> sendTestNotification() async {
    if (demo || session == null || !notifications.preferences.allowed) return;
    try {
      final scope = notificationAccount(session!.identity);
      await mac.deliverNotifications(scope, [
        {
          'id': 'test:$scope',
          'title': '希悦提醒已就绪',
          'body': '课前提醒和新消息将通过 ${mac.systemName} 通知中心送达。',
          'account': scope,
          'destination': 'schedule',
        },
      ]);
      notificationError = null;
      notificationTestStatus = '测试提醒已提交给 ${mac.systemName}，请查看通知中心。';
      await notifications.configure();
    } catch (_) {
      notificationTestStatus = null;
      notificationError = '测试提醒发送失败，请检查 ${mac.systemName} 通知设置。';
    }
    _emit();
  }

  Future<void> refreshNotificationStatus() async {
    await notifications.configure();
    _emit();
  }

  void _startPolling() {
    _timer?.cancel();
    _pollCount = 0;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_polling || !signedIn || demo || expired) return;
      _polling = true;
      try {
        await Future.wait([
          loadInbox(false),
          loadInbox(true),
          syncReminders(),
          if (++_pollCount % 5 == 0) loadSchedule(),
        ]);
      } finally {
        _polling = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        signedIn &&
        !demo &&
        !expired &&
        !_polling) {
      unawaited(_resumeSession());
      unawaited(
        notifications.configure().then((_) {
          if (!_disposed) _emit();
        }),
      );
    }
  }

  void _handleError(Object error) {
    if (error is CampusException && error.expired && !expired) {
      expired = true;
      _timer?.cancel();
      api.session = null;
      final auth = _authGeneration;
      final clear = _sessionWrites
          .catchError((_) {})
          .then((_) async {
            if (_current(auth) && expired) await mac.clearSession();
          })
          .catchError((_) {});
      _sessionWrites = clear;
      unawaited(notifications.reset().catchError((_) {}));
    }
  }

  String _errorText(Object error) =>
      error is CampusException ? error.message : '同步失败，请稍后重试。';
  Future<void> refreshAll() => Future.wait([
    loadSchedule(),
    loadInbox(false),
    loadInbox(true),
    loadSubjects(),
    syncReminders(),
  ]);
  Future<void> refreshCurrent() async {
    if (destination == Destination.schedule) {
      await Future.wait([loadSchedule(), syncReminders()]);
    } else if (destination == Destination.approvals) {
      await approvals.load(force: true);
      final record = approvals.selected;
      if (record != null) await approvals.openDetail(record);
    } else if (destination == Destination.subjects) {
      await loadSubjects();
      if (selectedSubject != null) await loadSubjectSection(force: true);
    } else {
      await loadInbox(destination == Destination.system);
    }
  }

  Future<void> changeWeek(int offset) async {
    week = week.add(Duration(days: offset * 7));
    selectedDay = week;
    await loadSchedule();
  }

  Future<void> goToday() async {
    week = mondayOf(DateTime.now());
    selectedDay = DateTime.now();
    await loadSchedule();
  }

  void selectDay(DateTime day) {
    selectedDay = day;
    _emit();
  }

  Future<void> loadSchedule() async {
    if (!signedIn || expired) return;
    final generation = ++_scheduleGeneration, auth = _authGeneration;
    if (demo) {
      lessons = demoLessons(week);
      scheduleError = null;
      _emit();
      return;
    }
    scheduleLoading = true;
    scheduleError = null;
    lessons = [];
    _emit();
    try {
      final result = await api.lessons(week);
      if (!_current(auth) || generation != _scheduleGeneration) return;
      lessons = result;
      scheduleSynced = DateTime.now();
    } catch (error) {
      if (!_current(auth) || generation != _scheduleGeneration) return;
      scheduleError = _errorText(error);
      _handleError(error);
    } finally {
      if (_current(auth) && generation == _scheduleGeneration) {
        scheduleLoading = false;
        _emit();
      }
    }
  }

  Future<void> loadSubjects() async {
    if (!signedIn || demo || expired) return;
    final generation = ++_subjectsGeneration, auth = _authGeneration;
    subjectsLoading = true;
    subjectsError = null;
    _emit();
    try {
      final result = await api.subjects();
      if (!_current(auth) || generation != _subjectsGeneration) return;
      subjects = result;
      if (selectedSubject != null) {
        final updated = result.where((s) => s.id == selectedSubject!.id);
        selectedSubject = updated.isEmpty ? null : updated.first;
      }
    } catch (error) {
      if (_current(auth) && generation == _subjectsGeneration) {
        subjectsError = _errorText(error);
        _handleError(error);
      }
    } finally {
      if (_current(auth) && generation == _subjectsGeneration) {
        subjectsLoading = false;
        _emit();
      }
    }
  }

  void selectSubject(CampusSubject subject) {
    selectedSubject = subject;
    destination = Destination.subjects;
    _emit();
    unawaited(loadSubjectSection());
  }

  void clearSelectedSubject() {
    selectedSubject = null;
    _emit();
  }

  void selectSubjectTab(SubjectTab tab) {
    subjectTab = tab;
    _emit();
    unawaited(loadSubjectSection());
  }

  Future<void> loadSubjectSection({
    bool force = false,
    bool more = false,
  }) async {
    final subject = selectedSubject, tab = subjectTab;
    if (subject == null || expired) return;
    final state = subjectSection;
    if (state.loading ||
        (!force && !more && state.data != null) ||
        (more && !state.hasMore)) {
      return;
    }
    final auth = _authGeneration, generation = ++state.generation;
    state.loading = true;
    state.error = null;
    _emit();
    try {
      if (demo) {
        state.data = demoSubjectSection(tab);
        state.hasMore = false;
      } else {
        final page = more ? state.page + 1 : 1;
        final Object data = switch (tab) {
          SubjectTab.grades => await api.subjectGrades(subject),
          SubjectTab.tasks => await api.subjectTasks(subject, page: page),
          SubjectTab.attendance => await api.subjectAttendance(
            subject,
            page: page,
          ),
          SubjectTab.members => await api.subjectMembers(subject, page: page),
        };
        if (!_current(auth) || generation != state.generation) return;
        state.page = page;
        if (data is SubjectPage) {
          final previous = more && state.data is SubjectPage
              ? (state.data as SubjectPage).items
              : [];
          final combined = [...previous, ...data.items];
          state.hasMore = data.hasMore;
          state.data = data is AttendancePage
              ? AttendancePage(
                  combined.cast<AttendanceRecord>(),
                  data.hasMore,
                  data.statistics,
                )
              : tab == SubjectTab.tasks
              ? SubjectPage(combined.cast<SubjectTask>(), data.hasMore)
              : SubjectPage(combined.cast<SubjectMember>(), data.hasMore);
        } else {
          state.data = data;
          state.hasMore = false;
        }
      }
    } catch (error) {
      if (_current(auth) && generation == state.generation) {
        state.error = _errorText(error);
        _handleError(error);
      }
    } finally {
      if (_current(auth) && generation == state.generation) {
        state.loading = false;
        _emit();
      }
    }
  }

  Future<void> openApprovalPortal(Uri url) async {
    if (demo || expired || session == null || approvalPortalOpening) return;
    final auth = _authGeneration;
    approvalPortalOpening = true;
    approvalPortalError = null;
    _emit();
    try {
      final renewed = await api.ensureSession();
      if (!_current(auth)) return;
      await mac.openApprovalPortal(url, renewed);
      if (_current(auth)) {
        await approvals.load(force: true);
        final record = approvals.selected;
        if (record != null) await approvals.openDetail(record);
      }
    } catch (error) {
      if (_current(auth)) {
        _handleError(error);
        approvalPortalError = error is CampusException
            ? error.message
            : '官方表单窗口未能打开，请重试。';
      }
    } finally {
      if (_current(auth)) {
        approvalPortalOpening = false;
        _emit();
      }
    }
  }

  Future<void> toggleUnread(bool value) async {
    inbox.unreadOnly = value;
    _emit();
  }

  void _merge(InboxState state, List<CampusMessage> incoming) {
    state.items = {
      for (final item in state.items) item.id: item,
      for (final item in incoming) item.id: item,
    }.values.toList()..sort((a, b) => b.created.compareTo(a.created));
  }

  Future<void> _saveCache(
    Identity identity,
    InboxState state,
    List<CampusMessage> items,
    bool isSystem,
    int auth, {
    bool? complete,
  }) async {
    try {
      await cache.merge(identity, items, system: isSystem, complete: complete);
      if (_current(auth)) state.cacheError = null;
    } catch (_) {
      if (_current(auth)) {
        state.cacheError = '通知文字缓存写入失败，请检查磁盘空间后刷新。';
        _emit();
      }
    }
  }

  Future<void> loadInbox(bool isSystem, {bool more = false}) async {
    if (!signedIn || expired) return;
    final state = isSystem ? system : notices;
    if (more &&
        (state.loading ||
            state.moreLoading ||
            state.prefetching ||
            !state.hasMore)) {
      return;
    }
    if (demo) {
      _emit();
      return;
    }
    final generation = ++state.generation,
        auth = _authGeneration,
        identity = session!.identity;
    final knownIds = state.items.map((item) => item.id).toSet(),
        wasComplete = state.historyComplete;
    state.prefetching = false;
    if (more) {
      state.moreLoading = true;
    } else {
      state.loading = state.items.isEmpty;
      state.moreLoading = false;
    }
    state.error = null;
    _emit();
    try {
      final page = more ? state.page + 1 : 1;
      // Unread is a local filter so background preloading always caches all text.
      final result = await api.messages(system: isSystem, page: page);
      if (!_current(auth) || generation != state.generation) return;
      _merge(state, result.items);
      images.enqueue(result.items);
      if (!more) {
        try {
          await notifications.receive(result.items, system: isSystem);
        } catch (_) {
          if (_current(auth)) notificationError = '新消息提醒未能发送，请检查通知权限和磁盘空间。';
        }
        if (!_current(auth) || generation != state.generation) return;
      }
      state.page = page;
      state.hasMore = result.hasMore;
      state.synced = DateTime.now();
      state.loading = false;
      final reachedArchive =
          !isSystem &&
          wasComplete &&
          result.items.any((message) => knownIds.contains(message.id));
      final complete = !isSystem && (!result.hasMore || reachedArchive);
      if (complete) {
        state.historyComplete = true;
        state.hasMore = false;
      }
      _emit();
      await _saveCache(
        identity,
        state,
        result.items,
        isSystem,
        auth,
        complete: complete ? true : null,
      );
      if (!_current(auth) || generation != state.generation) return;
      if (!isSystem && state.hasMore && !more) {
        unawaited(
          _preloadNotices(
            state,
            identity,
            generation,
            auth,
            knownIds,
            wasComplete,
            result.items.map((item) => item.id).join(','),
          ),
        );
      }
    } catch (error) {
      if (!_current(auth) || generation != state.generation) return;
      state.error = state.items.isEmpty
          ? _errorText(error)
          : '${_errorText(error)} 已保留本地文字。';
      _handleError(error);
    } finally {
      if (_current(auth) && generation == state.generation) {
        state.loading = false;
        state.moreLoading = false;
        _emit();
      }
    }
  }

  Future<void> _preloadNotices(
    InboxState state,
    Identity identity,
    int generation,
    int auth,
    Set<String> knownIds,
    bool wasComplete,
    String previousPage,
  ) async {
    state.prefetching = true;
    _emit();
    try {
      while (_current(auth) &&
          generation == state.generation &&
          state.hasMore &&
          !expired) {
        final result = await api.messages(system: false, page: state.page + 1);
        if (!_current(auth) || generation != state.generation) return;
        final fingerprint = result.items.map((item) => item.id).join(',');
        if (result.items.isNotEmpty && fingerprint == previousPage) {
          throw const CampusException('历史分页返回重复数据，请稍后刷新。');
        }
        previousPage = fingerprint;
        _merge(state, result.items);
        images.enqueue(result.items);
        state.page++;
        final reachedArchive =
            wasComplete &&
            result.items.any((item) => knownIds.contains(item.id));
        state.hasMore =
            result.hasMore && result.items.isNotEmpty && !reachedArchive;
        if (!state.hasMore) state.historyComplete = true;
        state.synced = DateTime.now();
        _emit();
        await _saveCache(
          identity,
          state,
          result.items,
          false,
          auth,
          complete: state.historyComplete ? true : null,
        );
      }
    } catch (error) {
      if (_current(auth) && generation == state.generation) {
        state.error = '历史通知预加载未完成：${_errorText(error)}';
        _handleError(error);
      }
    } finally {
      if (_current(auth) && generation == state.generation) {
        state.prefetching = false;
        _emit();
      }
    }
  }

  Future<CampusMessage> prepareMessage(CampusMessage message) async {
    if (demo || !message.cached || expired) return message;
    final auth = _authGeneration, identity = session!.identity;
    try {
      final fresh = await api.message(message.id, system: message.system);
      if (!_current(auth)) return message;
      final state = message.system ? system : notices;
      _merge(state, [fresh]);
      images.enqueue([fresh]);
      unawaited(_saveCache(identity, state, [fresh], message.system, auth));
      _emit();
      return fresh;
    } catch (_) {
      return message;
    }
  }

  Future<String?> markRead(CampusMessage message) async {
    if (message.read) return null;
    final auth = _authGeneration, identity = session?.identity;
    try {
      if (!demo) await api.markRead(message);
      if (!_current(auth)) return null;
      message.read = true;
      final state = message.system ? system : notices;
      _merge(state, [message]);
      if (!demo && identity != null) {
        await _saveCache(identity, state, [message], message.system, auth);
      }
      _emit();
      return null;
    } catch (error) {
      if (_current(auth)) {
        _handleError(error);
        _emit();
      }
      return _errorText(error);
    }
  }

  Future<void> logout() async {
    _authGeneration++;
    api.session = null;
    await _sessionWrites.catchError((_) {});
    await mac.clearSession();
    await notifications.reset().catchError((_) {});
    _timer?.cancel();
    _scheduleGeneration++;
    notices.generation++;
    system.generation++;
    images.reset();
    approvals.reset();
    approvalPortalOpening = false;
    approvalPortalError = null;
    session = null;
    api.session = null;
    demo = false;
    expired = false;
    notices.items = [];
    system.items = [];
    lessons = [];
    subjects = [];
    selectedSubject = null;
    subjectSections.clear();
    subjectsError = notificationError = sessionStorageError = null;
    notificationTestStatus = null;
    notificationMessage = null;
    subjectsLoading = false;
    _subjectsGeneration++;
    notices.unreadOnly = system.unreadOnly = notices.prefetching =
        system.prefetching = false;
    notices.historyComplete = system.historyComplete = false;
    notices.error = system.error = notices.cacheError = system.cacheError =
        scheduleError = loginError = null;
    scheduleLoading = notices.loading = system.loading = false;
    week = mondayOf(DateTime.now());
    selectedDay = DateTime.now();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    approvals.removeListener(_emit);
    approvals.dispose();
    _authGeneration++;
    _timer?.cancel();
    images.dispose();
    notifications.deactivate();
    mac.onNotificationOpened(null);
    WidgetsBinding.instance.removeObserver(this);
    api.onSessionChanged = null;
    api.close();
    super.dispose();
  }
}
