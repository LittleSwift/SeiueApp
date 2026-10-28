import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'rich_document.dart';

class CachedInbox {
  const CachedInbox(this.items, {this.complete = false});
  final List<CampusMessage> items;
  final bool complete;
}

/// No expiry or automatic eviction. Only text and message metadata reach disk.
class NoticeTextCache {
  NoticeTextCache({required this.directory});
  final Future<Directory> Function() directory;
  Future<void> _pending = Future.value();

  Future<File> _file(Identity identity, bool system) async {
    final root = await directory();
    final folder = Directory('${root.path}/notice-text-v1');
    await folder.create(recursive: true);
    final key = Uri.encodeComponent(
      '${identity.schoolId}:${identity.role}:${identity.id}',
    );
    return File('${folder.path}/$key-${system ? 'system' : 'notices'}.json');
  }

  Future<CachedInbox> read(Identity identity, {required bool system}) async {
    await _pending;
    return _read(await _file(identity, system), system);
  }

  Future<CachedInbox> _read(File file, bool system) async {
    if (!await file.exists()) return const CachedInbox([]);
    final raw = jsonDecode(await file.readAsString()) as Json;
    if (raw['schema'] != 1) {
      throw const FormatException('Unsupported notice cache');
    }
    final messages =
        (raw['messages'] as List)
            .whereType<Map>()
            .map(
              (entry) => CampusMessage.fromJson(
                Map<String, dynamic>.from(entry),
                system: system,
                cached: true,
              ),
            )
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));
    return CachedInbox(messages, complete: raw['complete'] == true);
  }

  Future<void> merge(
    Identity identity,
    List<CampusMessage> messages, {
    required bool system,
    bool? complete,
  }) {
    final operation = _pending.then((_) async {
      final file = await _file(identity, system);
      final existing = await _read(file, system);
      final merged = {
        for (final message in existing.items) message.id: message,
        for (final message in messages) message.id: message,
      };
      final body = jsonEncode({
        'schema': 1,
        'complete': complete ?? existing.complete,
        'messages': merged.values
            .map(
              (message) => {
                '_id': message.id,
                'title': message.title,
                'content': message.cached
                    ? message.content
                    : parseDocument(message.content)
                          .map((block) => block.text)
                          .join('\n')
                          .trim(),
                'sign': message.sender,
                'published_at': message.created.toIso8601String(),
                'readed': message.read,
                'is_important': message.important,
                'type': message.type,
              },
            )
            .toList(),
      });
      final temporary = File('${file.path}.pending');
      await temporary.writeAsString(body, flush: true);
      await temporary.rename(file.path);
    });
    // Keep future writes possible after a storage failure; callers receive it.
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
