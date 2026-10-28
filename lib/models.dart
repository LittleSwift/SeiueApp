import 'dart:convert';

typedef Json = Map<String, dynamic>;

String noticeWebUrl(String id) =>
    Uri.https('chalk-c3.seiue.com', '/notices/inbox', {
      'modal': 'InboxNoticeModal',
      'modalQuery': Uri.encodeComponent(jsonEncode({'id': id})),
    }).toString();

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value < 100000000000 ? value * 1000 : value).round(),
    ).toLocal();
  }
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}

String pad(int value) => value.toString().padLeft(2, '0');
String clockTime(DateTime date) => '${pad(date.hour)}:${pad(date.minute)}';
String dayKey(DateTime date) =>
    '${date.year}-${pad(date.month)}-${pad(date.day)}';
DateTime mondayOf(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).subtract(Duration(days: date.weekday - 1));
bool sameDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

class Identity {
  const Identity({
    required this.id,
    required this.name,
    required this.schoolId,
    required this.role,
  });
  final String id, name, schoolId, role;
  factory Identity.fromJson(Json json) => Identity(
    id: '${json['id']}',
    name: json['name']?.toString() ?? '校园用户',
    schoolId: '${json['school_id']}',
    role: json['role']?.toString() ?? 'student',
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'school_id': schoolId,
    'role': role,
  };
}

Identity selectIdentity(List<dynamic> reflections, dynamic activeId) {
  final available = reflections
      .whereType<Map>()
      .where(
        (r) =>
            '${r['school_id']}' == '3' &&
            r['disabled'] != true &&
            r['status'] != 'archived',
      )
      .toList();
  if (available.isEmpty) throw const FormatException('没有可用的校园身份');
  final active = available.where((r) => '${r['id']}' == '$activeId');
  final defaults = available.where(
    (r) => r['is_default'] == true || r['is_default'] == 1,
  );
  return Identity.fromJson(
    Map<String, dynamic>.from(
      active.isNotEmpty
          ? active.first
          : defaults.isNotEmpty
          ? defaults.first
          : available.first,
    ),
  );
}

// Authentication cookies stay in memory, or in OS-protected session storage
// only when the user opted to remember their login.
class PassportCookie {
  const PassportCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = true,
    this.httpOnly = true,
    this.expiresAt,
  });
  final String name, value, domain, path;
  final bool secure, httpOnly;
  final DateTime? expiresAt;
  bool get allowed =>
      name.isNotEmpty &&
      [
        'passport.seiue.com',
        'seiue.com',
      ].contains(domain.replaceFirst(RegExp(r'^\.'), '')) &&
      path.startsWith('/');
  bool validAt(DateTime now) =>
      allowed && (expiresAt == null || expiresAt!.isAfter(now));
  factory PassportCookie.fromJson(Json raw) => PassportCookie(
    name: '${raw['name'] ?? ''}',
    value: '${raw['value'] ?? ''}',
    domain: '${raw['domain'] ?? 'passport.seiue.com'}',
    path: '${raw['path'] ?? '/'}',
    secure: raw['secure'] != false,
    httpOnly: raw['http_only'] != false,
    expiresAt: parseDate(raw['expires_at']),
  );
  Json toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'http_only': httpOnly,
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
  };
}

class CampusSession {
  const CampusSession({
    required this.token,
    required this.identity,
    required this.expiresAt,
    this.tokenType = 'Bearer',
    this.passportCookies = const [],
  });
  final String token, tokenType;
  final List<PassportCookie> passportCookies;
  final Identity identity;
  final DateTime expiresAt;
  factory CampusSession.fromJson(Json json) => CampusSession(
    token: json['access_token'] as String,
    tokenType: json['token_type'] as String? ?? 'Bearer',
    identity: Identity.fromJson(json['identity'] as Json),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    passportCookies: (json['passport_cookies'] as List? ?? [])
        .whereType<Map>()
        .map((c) => PassportCookie.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.allowed)
        .toList(),
  );
  Json toJson() => {
    'access_token': token,
    'token_type': tokenType,
    'identity': identity.toJson(),
    'expires_at': expiresAt.toIso8601String(),
    if (passportCookies.isNotEmpty)
      'passport_cookies': passportCookies.map((c) => c.toJson()).toList(),
  };
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.teachers = '',
    this.group = '',
    this.kind = '',
  });
  final String id, title, location, teachers, group, kind;
  final DateTime start, end;
  static Lesson? fromJson(Json json) {
    final start = parseDate(json['start_time']);
    final end = parseDate(json['end_time']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    final custom = json['custom'] is Map
        ? Map<String, dynamic>.from(json['custom'])
        : <String, dynamic>{};
    final address = json['address'];
    final subject = json['subject'];
    return Lesson(
      id: '${custom['id'] ?? custom['biz_id'] ?? json['id'] ?? '${json['title']}_${json['start_time']}'}',
      title:
          '${json['title'] ?? (subject is Map ? subject['name'] : null) ?? '校园日程'}',
      start: start,
      end: end,
      kind: '${json['type'] ?? ''}',
      location: address is Map
          ? '${address['name'] ?? address['full_name'] ?? ''}'
          : address?.toString() ?? '',
      teachers: (json['initiators'] is List ? json['initiators'] as List : [])
          .whereType<Map>()
          .map((item) => '${item['name'] ?? ''}')
          .where((name) => name.isNotEmpty)
          .join('、'),
      group:
          '${(subject is Map ? subject['class_name'] : null) ?? custom['class_name'] ?? custom['class_full_name'] ?? ''}',
    );
  }
}

class CampusMessage {
  CampusMessage({
    required this.id,
    required this.title,
    required this.content,
    required this.sender,
    required this.created,
    required this.read,
    this.important = false,
    this.system = false,
    this.type = '',
    this.url,
    this.cached = false,
  });
  final String id, title, content, sender, type;
  final DateTime created;
  bool read;
  final bool important, system;
  final String? url;
  final bool cached;
  factory CampusMessage.fromJson(
    Json json, {
    required bool system,
    bool cached = false,
  }) {
    final sender = json['sender_reflection'] ?? json['sender'];
    final attributes = json['attributes'];
    return CampusMessage(
      id: '${json['id'] ?? json['_id'] ?? ''}',
      title: json['title']?.toString() ?? '校园消息',
      content: json['content'] is String
          ? json['content'] as String
          : jsonEncode(json['content'] ?? ''),
      sender:
          json['sign']?.toString() ??
          (sender is Map ? sender['name']?.toString() : null) ??
          (system ? '希悦系统' : '校园通知'),
      created:
          parseDate(json['published_at'] ?? json['created_at']) ??
          DateTime(1970),
      read: json['readed'] == true || json['readed'] == 1,
      important: json['is_important'] == true,
      system: system,
      cached: cached,
      type: '${json['type'] ?? ''}',
      url: attributes is Map ? attributes['url']?.toString() : null,
    );
  }
  String get preview {
    if (cached) return content.replaceAll(RegExp(r'\s+'), ' ').trim();
    try {
      final raw = jsonDecode(content);
      if (raw is Map && raw['blocks'] is List) {
        return (raw['blocks'] as List)
            .whereType<Map>()
            .map((block) => block['text'] ?? '')
            .join(' ')
            .trim();
      }
    } catch (_) {
      /* Plain text messages are valid. */
    }
    return content.replaceAll(RegExp('<[^>]*>'), ' ').trim();
  }
}

class MessagePage {
  const MessagePage(this.items, this.hasMore);
  final List<CampusMessage> items;
  final bool hasMore;
}
