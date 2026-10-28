import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/notice_cache.dart';
import 'package:seiue_mac/notice_images.dart';
import 'package:seiue_mac/platform_services.dart';
import 'package:seiue_mac/subject_models.dart';

const identity = Identity(
  id: 'one',
  name: '同学',
  schoolId: '3',
  role: 'student',
);
CampusMessage sampleMessage(String id, {bool rich = false}) => CampusMessage(
  id: id,
  title: '通知 $id',
  content: rich
      ? jsonEncode({
          'blocks': [
            {'text': '永久保留的第一段', 'entityRanges': []},
            {'text': '第二段', 'entityRanges': []},
            {
              'text': ' ',
              'type': 'atomic',
              'entityRanges': [
                {'offset': 0, 'length': 1, 'key': 0},
              ],
            },
          ],
          'entityMap': {
            '0': {
              'type': 'IMAGE',
              'data': {'src': 'https://example.com/private-image.png'},
            },
          },
        })
      : '正文 $id',
  sender: '学校',
  created: DateTime(2026, 10, 23),
  read: false,
);

class FakeMac extends MacServices {
  @override
  Future<CampusSession?> restoreSession() async => CampusSession(
    token: 'test-session',
    identity: identity,
    expiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  @override
  Future<void> clearSession() async {}
}

class FakeImages extends NoticeImagePreloader {
  final received = <String>[];
  @override
  void enqueue(Iterable<CampusMessage> messages) {
    received.addAll(messages.map((item) => item.id));
  }
}

class FakeApi extends SeiueApi {
  FakeApi(this.fetch, {this.offline = false});
  final Future<MessagePage> Function(int page) fetch;
  final bool offline;
  final pages = <int>[], readIds = <String>[];
  @override
  Future<List<CampusSubject>> subjects() async => [];
  @override
  Future<List<Lesson>> lessons(DateTime week) async => [];
  @override
  Future<MessagePage> messages({
    required bool system,
    int page = 1,
    bool unread = false,
  }) async {
    if (offline) throw const CampusException('网络不可用');
    if (system) return const MessagePage([], false);
    pages.add(page);
    return fetch(page);
  }

  @override
  Future<void> markRead(CampusMessage item) async {
    readIds.add(item.id);
  }

  @override
  Future<CampusMessage> message(String id, {required bool system}) async {
    if (offline) throw const CampusException('网络不可用');
    return messageForDetail(id);
  }

  CampusMessage messageForDetail(String id) => sampleMessage(id, rich: true);
}

Future<void> backgroundDone(CampusController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (controller.notices.prefetching) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Notice preload did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late NoticeTextCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('seiue-cache-test-');
    cache = NoticeTextCache(directory: () async => directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'cache survives a new instance and stores text without image data or URLs',
    () async {
      await cache.merge(
        identity,
        [sampleMessage('a', rich: true)],
        system: false,
        complete: true,
      );
      final reopened = NoticeTextCache(directory: () async => directory);
      final snapshot = await reopened.read(identity, system: false);
      expect(snapshot.complete, true);
      expect(snapshot.items.single.cached, true);
      expect(snapshot.items.single.content, '永久保留的第一段\n第二段');
      final files = await directory
          .list(recursive: true)
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      final raw = await files.single.readAsString();
      expect(raw, isNot(contains('private-image')));
      expect(raw, isNot(contains('entityMap')));
      expect(raw, isNot(contains('test-session')));
      final other = await reopened.read(
        const Identity(
          id: 'other',
          name: '另一账号',
          schoolId: '3',
          role: 'student',
        ),
        system: false,
      );
      expect(other.items, isEmpty);
    },
  );

  test(
    'serialized merges retain older messages and read-state updates',
    () async {
      await Future.wait([
        cache.merge(identity, [sampleMessage('a')], system: false),
        cache.merge(identity, [sampleMessage('b')], system: false),
      ]);
      final a = sampleMessage('a')..read = true;
      await cache.merge(identity, [a], system: false);
      final snapshot = await cache.read(identity, system: false);
      expect(snapshot.items.length, 2);
      expect(snapshot.items.firstWhere((m) => m.id == 'a').read, true);
    },
  );

  test(
    'notices preload all history and images without marking messages read',
    () async {
      final nextPage = Completer<MessagePage>();
      final api = FakeApi(
        (page) async => page == 1
            ? MessagePage([sampleMessage('a', rich: true)], true)
            : nextPage.future,
      );
      final images = FakeImages();
      final controller = CampusController(
        api: api,
        mac: FakeMac(),
        cache: cache,
        images: images,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.notices.prefetching, true);
      expect(controller.notices.items.single.id, 'a');
      nextPage.complete(MessagePage([sampleMessage('b')], false));
      await backgroundDone(controller);
      expect(api.pages, [1, 2]);
      expect(images.received, containsAll(['a', 'b']));
      expect(api.readIds, isEmpty);
      expect(controller.notices.hasMore, false);
      expect((await cache.read(identity, system: false)).complete, true);
      await controller.logout();
      expect((await cache.read(identity, system: false)).items.length, 2);
    },
  );

  test(
    'offline restart displays cached text and does not erase the archive',
    () async {
      await cache.merge(
        identity,
        [sampleMessage('saved')],
        system: false,
        complete: true,
      );
      final controller = CampusController(
        api: FakeApi((_) async => const MessagePage([], false), offline: true),
        mac: FakeMac(),
        cache: cache,
        images: FakeImages(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.notices.items.single.id, 'saved');
      expect(controller.notices.items.single.cached, true);
      expect(controller.notices.error, contains('已保留本地文字'));
      expect(
        (await cache.read(identity, system: false)).items.single.content,
        '正文 saved',
      );
    },
  );

  test(
    'late preload response cannot repopulate the screen after logout',
    () async {
      final nextPage = Completer<MessagePage>();
      final controller = CampusController(
        api: FakeApi(
          (page) async => page == 1
              ? MessagePage([sampleMessage('a')], true)
              : nextPage.future,
        ),
        mac: FakeMac(),
        cache: cache,
        images: FakeImages(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.logout();
      nextPage.complete(MessagePage([sampleMessage('late')], false));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.notices.items, isEmpty);
      expect(
        (await cache.read(identity, system: false)).items.map((m) => m.id),
        ['a'],
      );
    },
  );

  test('an interrupted archive resumes through cached pages', () async {
    await cache.merge(identity, [
      sampleMessage('a'),
      sampleMessage('b'),
    ], system: false);
    final api = FakeApi(
      (page) async => MessagePage([
        sampleMessage(['a', 'b', 'c'][page - 1]),
      ], page < 3),
    );
    final controller = CampusController(
      api: api,
      mac: FakeMac(),
      cache: cache,
      images: FakeImages(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backgroundDone(controller);
    expect(api.pages, [1, 2, 3]);
    expect(controller.notices.items.length, 3);
    expect((await cache.read(identity, system: false)).complete, true);
  });
}
