import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/notifications.dart';
import 'package:seiue_mac/platform_services.dart';
import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/controller.dart';

const student = Identity(id: 'one', name: '同学', schoolId: '3', role: 'student');

class ReminderApi extends SeiueApi {
  final weeks = <DateTime>[];
  final responses = <Completer<List<Lesson>>>[];
  @override
  Future<List<Lesson>> lessons(DateTime week) {
    weeks.add(week);
    final result = Completer<List<Lesson>>();
    responses.add(result);
    return result.future;
  }
}

class NotificationMac extends MacServices {
  NotificationMac(this.directory);
  final Directory directory;
  final deliveries = <Json>[], reminders = <List<Json>>[];
  bool classes = true, messages = true, allowed = true, fail = false;
  int cleared = 0;
  @override
  Future<void> clearSession() async {}
  Completer<String?>? blockedDirectory;
  @override
  Future<String?> applicationSupportPath() async =>
      blockedDirectory == null ? directory.path : blockedDirectory!.future;
  @override
  Future<Json> notificationPreferences({bool request = false}) async => {
    'permission': allowed ? 'authorized' : 'denied',
    'classes': classes,
    'messages': messages,
  };
  @override
  Future<Json> setNotificationPreferences({
    required bool classes,
    required bool messages,
  }) async {
    this.classes = classes;
    this.messages = messages;
    return notificationPreferences();
  }

  @override
  Future<void> activateNotifications(String account) async {}
  @override
  Future<void> clearNotifications() async {
    cleared++;
  }

  @override
  Future<void> deliverNotifications(String account, List<Json> requests) async {
    if (fail) throw StateError('notification failed');
    deliveries.addAll(requests);
  }

  @override
  Future<void> replaceCourseReminders(
    String account,
    List<Json> requests,
  ) async {
    reminders.add(requests);
  }
}

CampusMessage notice(
  String id,
  int minute, {
  bool read = false,
  bool cached = false,
}) => CampusMessage(
  id: id,
  title: '消息 $id',
  content: '正文',
  sender: '学校',
  created: DateTime(2026, 10, 23, 10, minute),
  read: read,
  cached: cached,
);

void main() {
  late Directory directory;
  late NotificationMac mac;
  late NotificationCoordinator notifications;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('seiue-reminders-');
    mac = NotificationMac(directory);
    notifications = NotificationCoordinator(mac);
    await notifications.configure();
    await notifications.activate(student);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('schedules exactly ten minutes early, excludes past and non-course events, deduplicates', () async {
    final now = DateTime(2026, 10, 23, 9);
    Lesson lesson(String id, int hour, int minute, {String kind = 'lesson'}) =>
        Lesson(
          id: id,
          title: '数学',
          start: DateTime(2026, 10, 23, hour, minute),
          end: DateTime(2026, 10, 23, hour, minute + 40),
          kind: kind,
          location: 'W614',
        );
    final future = lesson('later', 10, 0);
    final requests = courseReminderRequests(
      [
        future,
        lesson('past', 8, 0),
        lesson('too-late', 9, 5),
        lesson('event', 11, 0, kind: 'group'),
        future,
        lesson('first', 9, 30),
      ],
      now,
      'account',
    );
    expect(requests.length, 2);
    expect(
      requests.first['fireAt'],
      DateTime(2026, 10, 23, 9, 20).millisecondsSinceEpoch,
    );
    expect(
      requests.last['fireAt'],
      DateTime(2026, 10, 23, 9, 50).millisecondsSinceEpoch,
    );
    expect(requests.last['body'], contains('W614'));
    await notifications.schedule([future], now: now);
    await notifications.schedule([future], now: now);
    expect(mac.reminders[0].single['id'], mac.reminders[1].single['id']);
  });
  test('first sync is silent; only new unread messages alert, including same-timestamp additions', () async {
    await notifications.receive([notice('old', 0)], system: false);
    expect(mac.deliveries, isEmpty);
    await notifications.receive([
      notice('new', 1),
      notice('same-time', 0),
      notice('old', 0),
      notice('older-history', 0, read: true),
    ], system: false);
    expect(mac.deliveries.map((m) => m['messageId']), ['new', 'same-time']);
    await notifications.receive([
      notice('new', 1),
      notice('same-time', 0),
    ], system: false);
    expect(mac.deliveries.length, 2);
  });
  test('persistent account/type isolation prevents replay after restart or history load', () async {
    await notifications.receive([notice('old', 2)], system: false);
    final restarted = NotificationCoordinator(mac);
    await restarted.configure();
    await restarted.activate(student);
    await restarted.receive([
      notice('old', 2),
      notice('historical', 1),
      notice('cached', 3, cached: true),
      notice('already-read', 4, read: true),
    ], system: false);
    expect(mac.deliveries, isEmpty);
    await restarted.receive([notice('fresh', 5)], system: false);
    await restarted.receive([notice('system-baseline', 5)], system: true);
    await restarted.receive([notice('fresh', 6)], system: true);
    expect(mac.deliveries.map((m) => m['destination']), ['notices', 'system']);
    await restarted.activate(
      const Identity(id: 'two', name: '同学', schoolId: '3', role: 'student'),
    );
    await restarted.receive([notice('fresh', 6)], system: false);
    expect(mac.deliveries.length, 2);
  });
  test('denied and disabled notification settings advance baseline without delayed spam', () async {
    await notifications.receive([notice('old', 0)], system: false);
    await notifications.setPreferences(classes: true, messages: false);
    await notifications.receive([notice('muted', 1)], system: false);
    await notifications.setPreferences(classes: true, messages: true);
    await notifications.receive([notice('muted', 1)], system: false);
    mac.allowed = false;
    await notifications.configure();
    await notifications.receive([notice('denied', 2)], system: false);
    await notifications.schedule([
      Lesson(
        id: 'future',
        title: '课程',
        start: DateTime.now().add(const Duration(hours: 1)),
        end: DateTime.now().add(const Duration(hours: 2)),
        kind: 'lesson',
      ),
    ]);
    expect(mac.deliveries, isEmpty);
    expect(mac.reminders, isEmpty);
  });
  test(
    'failed native delivery retries without silently consuming the message',
    () async {
      await notifications.receive([notice('old', 0)], system: false);
      mac.fail = true;
      await expectLater(
        notifications.receive([notice('new', 1)], system: false),
        throwsStateError,
      );
      mac.fail = false;
      await notifications.receive([notice('new', 1)], system: false);
      expect(mac.deliveries.single['messageId'], 'new');
    },
  );
  test(
    'late message work after logout cannot send or commit old account state',
    () async {
      await notifications.receive([notice('old', 0)], system: false);
      mac.blockedDirectory = Completer<String?>();
      final pending = notifications.receive([notice('new', 1)], system: false);
      await Future<void>.delayed(Duration.zero);
      await notifications.reset();
      mac.blockedDirectory!.complete(directory.path);
      await pending;
      expect(mac.deliveries, isEmpty);
      expect(mac.cleared, 1);
      mac.blockedDirectory = null;
      await notifications.activate(student);
      await notifications.receive([notice('new', 1)], system: false);
      expect(mac.deliveries.length, 1);
    },
  );
  test('large catch-up batches use one summary notification', () async {
    await notifications.receive([notice('old', 0)], system: true);
    await notifications.receive([
      for (var i = 1; i < 9; i++) notice('new$i', i),
    ], system: true);
    expect(mac.deliveries.length, 1);
    expect(mac.deliveries.single['body'], contains('8'));
  });
  testWidgets(
    'browsing another week does not change the reminder sync horizon',
    (tester) async {
      final api = ReminderApi();
      final c = CampusController(api: api, mac: mac)..booting = false;
      c.session = CampusSession(
        token: 'test',
        identity: student,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await c.notifications.configure();
      await c.notifications.activate(student);
      c.week = DateTime(2020, 1, 6);
      final sync = c.syncReminders();
      final current = mondayOf(DateTime.now());
      expect(api.weeks, [current, current.add(const Duration(days: 7))]);
      for (final response in api.responses) {
        response.complete([]);
      }
      await sync;
      expect(c.week, DateTime(2020, 1, 6));
      expect(mac.reminders.length, 1);
      c.dispose();
    },
  );
  testWidgets(
    'late calendar responses after logout cannot schedule notifications',
    (tester) async {
      final api = ReminderApi();
      final c = CampusController(api: api, mac: mac)..booting = false;
      c.session = CampusSession(
        token: 'test',
        identity: student,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await c.notifications.configure();
      await c.notifications.activate(student);
      final sync = c.syncReminders();
      await c.logout();
      for (final response in api.responses) {
        response.complete([]);
      }
      await sync;
      expect(mac.reminders, isEmpty);
      expect(mac.cleared, 1);
      c.dispose();
    },
  );
}
