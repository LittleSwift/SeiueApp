import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_windows/flutter_local_notifications_windows.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

// A dedicated ID range lets course refreshes cancel pending lessons without
// removing message notifications. Do not use String.hashCode across launches.
int windowsNotificationId(String key, {bool course = false}) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return (hash & 0x1fffffff) | (course ? 0x20000000 : 0);
}

class WindowsNotifications {
  WindowsNotifications(this.channel);
  final MethodChannel channel;
  FlutterLocalNotificationsWindows? _plugin;
  Future<void>? _initializing;
  bool _classes = true, _messages = true, _ready = false;
  String? _account;
  Json? _pendingOpen;
  Future<void> Function(Json)? onOpened;
  File? _settings;

  Future<void> _initialize() => _initializing ??= _initializePlugin();

  Future<void> _initializePlugin() async {
    try {
      final root = await channel.invokeMethod<String>('applicationSupportPath');
      if (root == null) throw const FileSystemException('提醒设置目录不可用');
      _settings = File('$root/notification-preferences-v1.json');
      if (await _settings!.exists()) {
        try {
          final data = jsonDecode(await _settings!.readAsString()) as Json;
          _classes = data['classes'] != false;
          _messages = data['messages'] != false;
        } on FormatException {
          // A damaged preference file must not prevent login or notification setup.
        } on TypeError {
          // Treat a preference file with a wrong JSON shape as defaults.
        }
      }
      final plugin = FlutterLocalNotificationsWindows();
      final ok = await plugin.initialize(
        settings: const WindowsInitializationSettings(
          appName: 'Seiue',
          appUserModelId: 'com.littleswift.Seiue',
          guid: '94b36e97-26d6-4e0c-b05e-5b97958919cc',
        ),
        onDidReceiveNotificationResponse: (response) {
          final raw = response.payload;
          if (raw == null) return;
          try {
            _pendingOpen = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            _dispatchOpen();
          } on FormatException {
            // Ignore malformed or obsolete activation payloads.
          } on TypeError {
            // Only app-generated JSON objects are activation payloads.
          }
        },
      );
      if (!ok) {
        throw PlatformException(
          code: 'notifications',
          message: 'Windows 通知初始化失败',
        );
      }
      _plugin = plugin;
      final launch = await plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        try {
          _pendingOpen = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        } on FormatException {
          // Ignore invalid notification launch data.
        } on TypeError {
          // Ignore invalid notification launch data.
        }
      }
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _dispatchOpen() async {
    final info = _pendingOpen, callback = onOpened;
    if (!_ready || info == null || callback == null || _account == null) return;
    _pendingOpen = null;
    if (info['account'] != _account) return;
    try {
      await channel.invokeMethod<void>('activateWindow');
      await callback(info);
    } catch (_) {
      // Activation must not crash the isolate if the window is closing.
    }
  }

  Future<void> ready() async {
    _ready = true;
    await _dispatchOpen();
  }

  Future<Json> preferences({bool request = false}) async {
    await _initialize();
    // Windows has no runtime consent prompt; login must not open Settings.
    final pending = await _plugin!.pendingNotificationRequests();
    return {
      // This plugin has no permission-query API. Do not claim authorization.
      'permission': 'systemManaged',
      'classes': _classes,
      'messages': _messages,
      'scheduledClasses': pending.where((p) => p.id & 0x20000000 != 0).length,
    };
  }

  Future<Json> setPreferences({
    required bool classes,
    required bool messages,
  }) async {
    await _initialize();
    _classes = classes;
    _messages = messages;
    final pending = File('${_settings!.path}.pending');
    await pending.writeAsString(
      jsonEncode({'classes': classes, 'messages': messages}),
      flush: true,
    );
    await pending.rename(_settings!.path);
    if (!classes) await _cancelCourses();
    return preferences();
  }

  Future<void> _cancelCourses() async {
    for (final pending in await _plugin!.pendingNotificationRequests()) {
      if (pending.id & 0x20000000 != 0) await _plugin!.cancel(id: pending.id);
    }
  }

  Future<void> activate(String account) async {
    await _initialize();
    if (_account != account) {
      // Also clears scheduled reminders left by a previous process/account.
      await _plugin!.cancelAll();
      _account = account;
      _ready = false;
    }
  }

  Future<void> clear() async {
    _account = null;
    _ready = false;
    _pendingOpen = null;
    await _initialize();
    await _plugin!.cancelAll();
  }

  Future<void> replaceCourses(String account, List<Json> requests) async {
    await _initialize();
    if (_account != account) return;
    await _cancelCourses();
    if (!_classes) return;
    for (final request in requests.take(60)) {
      if (_account != account || !_classes) return;
      final fire = DateTime.fromMillisecondsSinceEpoch(
        request['fireAt'] as int,
      );
      if (!fire.isAfter(DateTime.now())) continue;
      await _plugin!.zonedSchedule(
        id: windowsNotificationId('${request['id']}', course: true),
        title: '${request['title']}',
        body: '${request['body']}',
        scheduledDate: tz.TZDateTime.from(fire, tz.UTC),
        payload: jsonEncode(request),
      );
    }
  }

  Future<void> deliver(String account, List<Json> requests) async {
    await _initialize();
    for (final request in requests) {
      if (_account != account) return;
      if (!_messages && !'${request['id']}'.startsWith('test:')) continue;
      await _plugin!.show(
        id: windowsNotificationId('${request['id']}'),
        title: '${request['title']}',
        body: '${request['body']}',
        payload: jsonEncode(request),
      );
    }
  }
}
