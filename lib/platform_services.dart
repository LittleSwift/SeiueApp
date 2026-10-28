import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';
import 'windows_notifications.dart';

class MacServices {
  static const channel = MethodChannel('com.littleswift.seiue/native');
  // Keep the existing type name for callers; native capabilities vary by OS.
  bool get isWindows => Platform.isWindows;
  bool get supportsWebLogin => !isWindows;
  bool get embeddedApprovalPortal => !isWindows;
  String get systemName => isWindows ? 'Windows' : 'macOS';
  String get appName => isWindows ? 'Seiue Windows' : 'Seiue Mac';
  Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('openNotificationSettings');
  late final _windows = WindowsNotifications(channel);
  Future<Json> notificationPreferences({bool request = false}) async =>
      isWindows
      ? _windows.preferences(request: request)
      : Map<String, dynamic>.from(
          await channel.invokeMapMethod<String, dynamic>(
                'notificationPreferences',
                {'request': request},
              ) ??
              {},
        );
  Future<Json> setNotificationPreferences({
    required bool classes,
    required bool messages,
  }) async => isWindows
      ? _windows.setPreferences(classes: classes, messages: messages)
      : Map<String, dynamic>.from(
          await channel.invokeMapMethod<String, dynamic>(
                'setNotificationPreferences',
                {'classes': classes, 'messages': messages},
              ) ??
              {},
        );
  Future<void> replaceCourseReminders(String account, List<Json> requests) =>
      isWindows
      ? _windows.replaceCourses(account, requests)
      : channel.invokeMethod('replaceCourseReminders', {
          'account': account,
          'requests': requests,
        });
  Future<void> deliverNotifications(String account, List<Json> requests) =>
      isWindows
      ? _windows.deliver(account, requests)
      : channel.invokeMethod('deliverNotifications', {
          'account': account,
          'requests': requests,
        });
  Future<void> clearNotifications() =>
      isWindows ? _windows.clear() : channel.invokeMethod('clearNotifications');
  Future<void> activateNotifications(String account) => isWindows
      ? _windows.activate(account)
      : channel.invokeMethod('activateNotifications', {'account': account});
  void onNotificationOpened(Future<void> Function(Json)? callback) {
    if (isWindows) {
      _windows.onOpened = callback;
      return;
    }
    channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'notificationOpened') {
                await callback(
                  Map<String, dynamic>.from(call.arguments as Map),
                );
              }
            },
    );
  }

  Future<void> notificationsReady() =>
      isWindows ? _windows.ready() : channel.invokeMethod('notificationsReady');
  Future<void> saveSession(CampusSession session) =>
      channel.invokeMethod('saveSession', jsonEncode(session.toJson()));
  Future<CampusSession?> restoreSession() async {
    final raw = await channel.invokeMethod<String>('readSession');
    if (raw == null) return null;
    try {
      return CampusSession.fromJson(jsonDecode(raw) as Json);
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() => channel.invokeMethod('clearSession');
  Future<String?> applicationSupportPath() =>
      channel.invokeMethod<String>('applicationSupportPath');
  Future<Json> webLogin() async {
    if (!supportsWebLogin) {
      throw PlatformException(
        code: 'unsupported',
        message: 'Windows 版请使用账号密码登录',
      );
    }
    final raw = await channel.invokeMethod<String>('webLogin');
    if (raw == null) {
      throw PlatformException(code: 'cancelled', message: '登录已取消');
    }
    return jsonDecode(raw) as Json;
  }

  Future<void> openApprovalPortal(Uri url, CampusSession session) => isWindows
      ? openUrl(url.toString())
      : channel.invokeMethod('openApprovalPortal', {
          'url': url.toString(),
          'token': session.token,
          'tokenType': session.tokenType,
          'reflectionId': session.identity.id,
          'expiresAt': session.expiresAt.millisecondsSinceEpoch,
        });

  Future<void> openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return;
    }
    await channel.invokeMethod('openUrl', uri.toString());
  }
}
