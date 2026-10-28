import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'platform_services.dart';

String notificationAccount(Identity identity) =>
    '${identity.schoolId}:${identity.role}:${identity.id}';

class NotificationPreferences {
  const NotificationPreferences({
    this.permission = 'notDetermined',
    this.classes = true,
    this.messages = true,
    this.scheduledClasses = 0,
    this.testDelivered = false,
  });
  final String permission;
  final bool classes, messages;
  final int scheduledClasses;
  final bool testDelivered;
  bool get allowed =>
      permission == 'authorized' ||
      permission == 'provisional' ||
      permission == 'systemManaged';
  factory NotificationPreferences.fromJson(Json json) =>
      NotificationPreferences(
        permission: '${json['permission'] ?? 'notDetermined'}',
        classes: json['classes'] != false,
        messages: json['messages'] != false,
        scheduledClasses: (json['scheduledClasses'] as num?)?.toInt() ?? 0,
        testDelivered: json['testDelivered'] == true,
      );
}

/// Stable identifiers replace a changed lesson rather than creating duplicates.
List<Json> courseReminderRequests(
  Iterable<Lesson> lessons,
  DateTime now,
  String account,
) {
  final unique = <String, Json>{};
  for (final lesson in lessons) {
    if (lesson.kind != 'lesson') continue;
    final fire = lesson.start.subtract(const Duration(minutes: 10));
    if (!fire.isAfter(now.add(const Duration(seconds: 1)))) continue;
    final id =
        'class:$account:${lesson.id}:${lesson.start.millisecondsSinceEpoch}';
    unique[id] = {
      'id': id,
      'title': '10 分钟后上课 · ${lesson.title}',
      'body':
          '${clockTime(lesson.start)}–${clockTime(lesson.end)}${lesson.location.isEmpty ? '' : ' · ${lesson.location}'}${lesson.teachers.isEmpty ? '' : ' · ${lesson.teachers}'}',
      'fireAt': fire.millisecondsSinceEpoch,
      'account': account,
      'destination': 'schedule',
    };
  }
  final result = unique.values.toList()
    ..sort((a, b) => (a['fireAt'] as int).compareTo(b['fireAt'] as int));
  return result.take(60).toList();
}

class NotificationCoordinator {
  NotificationCoordinator(this.mac);
  final MacServices mac;
  NotificationPreferences preferences = const NotificationPreferences();
  String? account;
  int _generation = 0;
  Future<void> _pending = Future.value();
  String? error;

  Future<void> configure({bool request = false}) async {
    try {
      preferences = NotificationPreferences.fromJson(
        await mac.notificationPreferences(request: request),
      );
      error = null;
    } catch (_) {
      error = '无法访问 ${mac.systemName} 通知服务。';
    }
  }

  Future<void> setPreferences({
    required bool classes,
    required bool messages,
  }) async {
    preferences = NotificationPreferences.fromJson(
      await mac.setNotificationPreferences(
        classes: classes,
        messages: messages,
      ),
    );
    error = null;
  }

  Future<void> activate(Identity identity) async {
    account = notificationAccount(identity);
    _generation++;
    try {
      await mac.activateNotifications(account!);
    } catch (_) {}
  }

  Future<void> reset() async {
    deactivate();
    await mac.clearNotifications();
  }

  void deactivate() {
    account = null;
    _generation++;
  }

  Future<void> schedule(Iterable<Lesson> lessons, {DateTime? now}) async {
    final scope = account, generation = _generation;
    if (scope == null || !preferences.allowed || !preferences.classes) return;
    final requests = courseReminderRequests(
      lessons,
      now ?? DateTime.now(),
      scope,
    );
    if (generation != _generation) return;
    await mac.replaceCourseReminders(scope, requests);
  }

  /// A persistent high-water mark prevents history preloads, restarts and read
  /// status changes from replaying old notifications. Each account is isolated.
  Future<void> receive(List<CampusMessage> messages, {required bool system}) {
    final scope = account, generation = _generation;
    if (scope == null) return Future.value();
    final operation = _pending.then((_) async {
      if (generation != _generation || scope != account) return;
      final root = await mac.applicationSupportPath();
      if (root == null) throw const FileSystemException('提醒记录目录不可用');
      final dir = Directory('$root/notification-ledger-v1');
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}/${Uri.encodeComponent(scope)}-${system ? 'system' : 'notices'}.json',
      );
      Json? stored;
      if (await file.exists()) {
        stored = jsonMapLedger(jsonDecode(await file.readAsString()));
      }
      final ids = ((stored?['ids'] as List?) ?? []).map((e) => '$e').toSet();
      final since = int.tryParse('${stored?['since']}') ?? 0;
      var newest = since;
      final fresh = <CampusMessage>[];
      for (final message in messages) {
        final time = message.created.millisecondsSinceEpoch;
        if (stored != null &&
            !ids.contains(message.id) &&
            time >= since &&
            !message.read &&
            !message.cached) {
          fresh.add(message);
        }
        ids.add(message.id);
        if (time > newest) newest = time;
      }
      if (generation != _generation || scope != account) return;
      if (preferences.allowed && preferences.messages && fresh.isNotEmpty) {
        final deliveries = fresh.length > 5
            ? [
                <String, dynamic>{
                  'id':
                      'messages:$scope:${system ? 'system' : 'notices'}:$newest',
                  'title': system ? '新的系统消息' : '新的校园通知',
                  'body': '收到 ${fresh.length} 条新消息，点击查看',
                  'account': scope,
                  'destination': system ? 'system' : 'notices',
                },
              ]
            : fresh
                  .map(
                    (m) => <String, dynamic>{
                      'id':
                          'message:$scope:${system ? 'system' : 'notices'}:${m.id}',
                      'title': m.title,
                      'body': '${m.sender} · ${m.preview}'
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .substring(
                            0,
                            '${m.sender} · ${m.preview}'
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .length
                                .clamp(0, 180),
                          ),
                      'account': scope,
                      'destination': system ? 'system' : 'notices',
                      'messageId': m.id,
                    },
                  )
                  .toList();
        await mac.deliverNotifications(scope, deliveries);
      }
      if (generation != _generation || scope != account) return;
      final trimmed = ids.toList();
      final pending = File('${file.path}.pending');
      await pending.writeAsString(
        jsonEncode({
          'version': 1,
          'since': newest,
          'ids': trimmed.length > 2000
              ? trimmed.sublist(trimmed.length - 2000)
              : trimmed,
        }),
        flush: true,
      );
      await pending.rename(file.path);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}

Json jsonMapLedger(dynamic value) {
  if (value is! Map || value['version'] != 1) {
    throw const FormatException('提醒记录格式无效');
  }
  return Map<String, dynamic>.from(value);
}
