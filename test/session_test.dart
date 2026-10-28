import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/controller.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/platform_services.dart';

final now = DateTime(2026, 10, 25, 10);
const identity = Identity(
  id: 'student',
  name: '同学',
  schoolId: '3',
  role: 'student',
);
const authCookie = PassportCookie(
  name: 'session',
  value: 'cookie',
  domain: 'passport.seiue.com',
);
CampusSession saved({
  String token = 'old',
  int minutes = 5,
  List<PassportCookie> cookies = const [authCookie],
}) => CampusSession(
  token: token,
  identity: identity,
  expiresAt: now.add(Duration(minutes: minutes)),
  passportCookies: cookies,
);

class Headers extends Fake implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = '$value';
  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  set contentType(ContentType? value) {}
}

class Reply extends StreamView<List<int>> implements HttpClientResponse {
  Reply(Object body, {this.statusCode = 200, this.cookies = const []})
    : super(Stream.value(utf8.encode(jsonEncode(body))));
  @override
  final int statusCode;
  @override
  final List<Cookie> cookies;
  @override
  final headers = Headers();
  @override
  bool get isRedirect => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request extends Fake implements HttpClientRequest {
  Request(this.method, this.uri, this.respond);
  @override
  final String method;
  @override
  final Uri uri;
  final Future<Reply> Function(Request) respond;
  final body = StringBuffer();
  @override
  final headers = Headers();
  @override
  final cookies = <Cookie>[];
  @override
  set followRedirects(bool value) {}
  @override
  void write(Object? value) => body.write(value);
  @override
  Future<HttpClientResponse> close() => respond(this);
}

class Client extends Fake implements HttpClient {
  Client(this.respond);
  final Future<Reply> Function(Request) respond;
  final requests = <Request>[];
  @override
  set connectionTimeout(Duration? value) {}
  @override
  set userAgent(String? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final r = Request(method, url, respond);
    requests.add(r);
    return r;
  }

  @override
  void close({bool force = false}) {}
}

Reply renewed({List<Cookie> cookies = const []}) => Reply({
  'access_token': 'new',
  'expires_in': 7200,
  'token_type': 'Bearer',
}, cookies: cookies);

class SessionMac extends MacServices {
  CampusSession? restored;
  final savedSessions = <CampusSession>[];
  final operations = <String>[];
  Completer<void>? blockedSave;
  bool failSave = false;
  late String supportPath;
  @override
  Future<CampusSession?> restoreSession() async => restored;
  @override
  Future<void> saveSession(CampusSession s) async {
    operations.add('save');
    if (failSave) throw StateError('Keychain unavailable');
    savedSessions.add(s);
    await blockedSave?.future;
  }

  @override
  Future<void> clearSession() async {
    operations.add('clear');
  }

  @override
  Future<String?> applicationSupportPath() async => supportPath;
  @override
  Future<Json> notificationPreferences({bool request = false}) async => {
    'permission': 'denied',
    'classes': false,
    'messages': false,
  };
  @override
  Future<void> activateNotifications(String account) async {}
  @override
  Future<void> notificationsReady() async {}
  @override
  Future<void> clearNotifications() async {}
  @override
  void onNotificationOpened(Future<void> Function(Json)? callback) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'session payload restores renewal cookies and reads legacy sessions',
    () {
      final original = saved();
      final restored = CampusSession.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Json,
      );
      expect(restored.passportCookies.single.value, 'cookie');
      final legacy = original.toJson()..remove('passport_cookies');
      expect(CampusSession.fromJson(legacy).passportCookies, isEmpty);
      expect(
        const PassportCookie(
          name: 'cookie',
          value: 'value',
          domain: 'evil.example',
        ).allowed,
        isFalse,
      );
      expect(
        PassportCookie(
          name: 'cookie',
          value: 'value',
          domain: '.seiue.com',
          expiresAt: now,
        ).validAt(now),
        isFalse,
      );
    },
  );
  test('parallel requests share one renewal, rotate cookies and never send them to business APIs', () async {
    final gate = Completer<Reply>();
    var count = 0;
    final client = Client((r) async {
      if (r.uri.host == 'passport.seiue.com') {
        count++;
        return gate.future;
      }
      expect(r.headers.value('authorization'), 'Bearer new');
      expect(r.cookies, isEmpty);
      return Reply([]);
    });
    final api = SeiueApi(client: client, now: () => now)..session = saved();
    CampusSession? updated;
    api.onSessionChanged = (s) async {
      updated = s;
    };
    final requests = List.generate(4, (_) => api.messages(system: false));
    await Future<void>.delayed(Duration.zero);
    expect(count, 1);
    expect(client.requests.length, 1);
    expect(client.requests.single.cookies.single.value, 'cookie');
    expect(
      Uri.splitQueryString(client.requests.single.body.toString())['client_id'],
      'GpxvnjhVKt56qTmnPWH1sA',
    );
    gate.complete(
      renewed(
        cookies: [
          Cookie('session', 'rotated')
            ..path = '/'
            ..maxAge = 86400,
        ],
      ),
    );
    await Future.wait(requests);
    expect(api.session!.token, 'new');
    expect(updated!.passportCookies.single.value, 'rotated');
    expect(api.session!.expiresAt, now.add(const Duration(hours: 2)));
    api.close();
  });
  test(
    'a delayed 401 reuses an already renewed token instead of refreshing again',
    () async {
      var oldRequests = 0, renewals = 0;
      final delayed = Completer<Reply>();
      final client = Client((r) async {
        if (r.uri.host == 'passport.seiue.com') {
          renewals++;
          return renewed();
        }
        if (r.headers.value('authorization') == 'Bearer old') {
          oldRequests++;
          return oldRequests == 1 ? Reply({}, statusCode: 401) : delayed.future;
        }
        return Reply([]);
      });
      final api = SeiueApi(client: client, now: () => now)
        ..session = saved(minutes: 60);
      final first = api.messages(system: false),
          second = api.messages(system: true);
      await first;
      delayed.complete(Reply({}, statusCode: 401));
      await second;
      expect(renewals, 1);
      expect(
        client.requests.where((r) => r.uri.host == 'api.seiue.com').length,
        4,
      );
      api.close();
    },
  );
  test(
    'a renewed token rejected again expires without an infinite retry loop',
    () async {
      var renewals = 0, requests = 0;
      final api = SeiueApi(
        client: Client((r) async {
          if (r.uri.host == 'passport.seiue.com') {
            renewals++;
            return renewed();
          }
          requests++;
          return Reply({}, statusCode: 401);
        }),
        now: () => now,
      )..session = saved(minutes: 60);
      await expectLater(
        api.messages(system: false),
        throwsA(
          isA<CampusException>().having((e) => e.expired, 'expired', true),
        ),
      );
      expect(renewals, 1);
      expect(requests, 2);
      api.close();
    },
  );
  for (final offline in [false, true]) {
    test(
      'temporary renewal ${offline ? 'network' : 'server'} failure preserves cookies and allows retry',
      () async {
        var attempts = 0;
        final api = SeiueApi(
          client: Client((r) async {
            if (r.uri.host == 'passport.seiue.com') {
              if (++attempts == 1) {
                if (offline) throw const SocketException('offline');
                return Reply({}, statusCode: 503);
              }
              return renewed();
            }
            return Reply([]);
          }),
          now: () => now,
        )..session = saved();
        await expectLater(
          api.messages(system: false),
          throwsA(
            isA<CampusException>().having((e) => e.expired, 'expired', false),
          ),
        );
        expect(api.canRenew, isTrue);
        expect(api.session!.token, 'old');
        await api.messages(system: false);
        expect(attempts, 2);
        api.close();
      },
    );
  }
  test(
    'Passport rejecting the login cookie is a genuine session expiration',
    () async {
      final api = SeiueApi(
        client: Client(
          (r) async => Reply({'error': 'invalid_session'}, statusCode: 400),
        ),
        now: () => now,
      )..session = saved();
      await expectLater(
        api.ensureSession(),
        throwsA(
          isA<CampusException>().having((e) => e.expired, 'expired', true),
        ),
      );
      api.close();
    },
  );
  test(
    'logout during renewal cannot restore credentials or emit a new session',
    () async {
      final gate = Completer<Reply>();
      var updates = 0;
      final api = SeiueApi(client: Client((r) => gate.future), now: () => now)
        ..session = saved();
      api.onSessionChanged = (_) async {
        updates++;
      };
      final pending = api.ensureSession();
      final expectation = expectLater(pending, throwsA(isA<CampusException>()));
      await Future<void>.delayed(Duration.zero);
      api.session = null;
      gate.complete(renewed(cookies: [Cookie('session', 'rotated')]));
      await expectation;
      expect(api.session, isNull);
      expect(api.canRenew, isFalse);
      expect(updates, 0);
      api.close();
    },
  );
  test(
    'an old account response never retries using a new account session',
    () async {
      final gate = Completer<Reply>();
      final client = Client((r) => gate.future);
      final api = SeiueApi(client: client, now: () => now)
        ..session = saved(minutes: 60);
      final pending = api.messages(system: false);
      final expectation = expectLater(pending, throwsA(isA<CampusException>()));
      await Future<void>.delayed(Duration.zero);
      api.session = saved(token: 'another-account', minutes: 60);
      gate.complete(Reply({}, statusCode: 401));
      await expectation;
      expect(client.requests.length, 1);
      expect(api.session!.token, 'another-account');
      api.close();
    },
  );
  for (final remember in [false, true]) {
    test(
      'renewed session updates controller and persists only when remember=$remember',
      () async {
        final mac = SessionMac();
        final api = SeiueApi(
          client: Client(
            (r) async =>
                r.uri.host == 'passport.seiue.com' ? renewed() : Reply([]),
          ),
          now: () => now,
        )..session = saved();
        final c = CampusController(api: api, mac: mac)
          ..session = api.session
          ..remember = remember;
        await api.ensureSession();
        expect(c.session!.token, 'new');
        expect(mac.savedSessions.length, remember ? 1 : 0);
        c.dispose();
      },
    );
  }
  test('logout waits for the last Keychain update then deletes it', () async {
    final mac = SessionMac()..blockedSave = Completer<void>();
    final api = SeiueApi(client: Client((r) async => renewed()), now: () => now)
      ..session = saved();
    final c = CampusController(api: api, mac: mac)
      ..session = api.session
      ..remember = true;
    final pending = api.ensureSession();
    final expectation = expectLater(pending, throwsA(isA<CampusException>()));
    await Future<void>.delayed(Duration.zero);
    expect(mac.operations, ['save']);
    final logout = c.logout();
    mac.blockedSave!.complete();
    await logout;
    await expectation;
    expect(mac.operations, ['save', 'clear']);
    expect(c.session, isNull);
    expect(api.session, isNull);
    c.dispose();
  });
  test(
    'startup renews an expired remembered token instead of deleting it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'seiue-session-test',
      );
      final mac = SessionMac()
        ..restored = saved(minutes: -1)
        ..supportPath = directory.path;
      var renewals = 0;
      final api = SeiueApi(
        client: Client((r) async {
          if (r.uri.host == 'passport.seiue.com') {
            renewals++;
            return renewed();
          }
          if (r.uri.path.endsWith('/semesters/current')) {
            return Reply({'id': 1});
          }
          return Reply([]);
        }),
        now: () => now,
      );
      final c = CampusController(api: api, mac: mac);
      await c.initialize();
      expect(c.signedIn, isTrue);
      expect(c.expired, isFalse);
      expect(c.session!.token, 'new');
      expect(renewals, 1);
      expect(mac.operations, ['save']);
      c.dispose();
      await directory.delete(recursive: true);
    },
  );
  test('web-login cookie payload is retained for subsequent Passport authorization', () async {
    final client = Client((r) async {
      if (r.uri.host == 'passport.seiue.com') {
        expect(r.cookies.single.value, 'web-cookie');
        return renewed();
      }
      return Reply({
        'reflections': [
          {
            'id': 'student',
            'name': '同学',
            'school_id': '3',
            'role': 'student',
            'is_default': 1,
          },
        ],
      });
    });
    final api = SeiueApi(client: client, now: () => now);
    final result = await api.acceptToken({
      'access_token': 'web-token',
      'token_type': 'Bearer',
      'expires_in': 86400,
      'passport_cookies': [
        {
          'name': 'session',
          'value': 'web-cookie',
          'domain': '.seiue.com',
          'path': '/',
          'secure': true,
          'http_only': true,
        },
      ],
    });
    expect(result.passportCookies.single.value, 'web-cookie');
    await api.ensureSession(force: true);
    expect(api.session!.token, 'new');
    api.close();
  });
  test('an offline startup preserves the expired remembered session for a later retry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'seiue-session-offline',
    );
    final mac = SessionMac()
      ..restored = saved(minutes: -1)
      ..supportPath = directory.path;
    final api = SeiueApi(
      client: Client((r) async => throw const SocketException('offline')),
      now: () => now,
    );
    final c = CampusController(api: api, mac: mac);
    await c.initialize();
    expect(c.signedIn, isTrue);
    expect(c.expired, isFalse);
    expect(c.session!.token, 'old');
    expect(mac.operations, isEmpty);
    c.dispose();
    await directory.delete(recursive: true);
  });
  test('a Keychain write failure leaves the renewed session usable and can be retried', () async {
    final mac = SessionMac()..failSave = true;
    final api = SeiueApi(client: Client((r) async => renewed()), now: () => now)
      ..session = saved();
    final c = CampusController(api: api, mac: mac)
      ..session = api.session
      ..remember = true;
    await api.ensureSession();
    expect(c.session!.token, 'new');
    expect(c.expired, isFalse);
    expect(c.sessionStorageError, isNotNull);
    mac.failSave = false;
    await c.retrySessionSave();
    expect(c.sessionStorageError, isNull);
    expect(mac.savedSessions.single.token, 'new');
    c.dispose();
  });
}
