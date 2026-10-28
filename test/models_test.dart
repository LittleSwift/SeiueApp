import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/rich_document.dart';
import 'package:seiue_mac/schedule.dart';

void main() {
  test(
    'selects active normal identity and never falls back to archived identity',
    () {
      final identities = [
        {
          'id': 1,
          'name': '历史身份',
          'school_id': 3,
          'role': 'student',
          'status': 'archived',
        },
        {
          'id': 2,
          'name': '当前身份',
          'school_id': 3,
          'role': 'student',
          'status': 'normal',
          'is_default': 1,
        },
      ];
      expect(selectIdentity(identities, 1).id, '2');
      expect(selectIdentity(identities, 2).id, '2');
      expect(
        () => selectIdentity([identities.first], null),
        throwsFormatException,
      );
    },
  );

  test('parses campus calendar payload and rejects invalid times', () {
    final json = <String, dynamic>{
      'title': '数学',
      'start_time': '2026-10-23 08:00:00',
      'end_time': '2026-10-23 08:40:00',
      'address': {'name': 'W614'},
      'initiators': [
        {'name': '教师'},
      ],
      'subject': {'class_name': '高三1班'},
      'custom': {'id': 123},
    };
    final lesson = Lesson.fromJson(json)!;
    expect(lesson.location, 'W614');
    expect(lesson.teachers, '教师');
    expect(lesson.group, '高三1班');
    expect(lesson.end.difference(lesson.start).inMinutes, 40);
    expect(
      Lesson.fromJson({...json, 'end_time': '2026-10-23 07:00:00'}),
      isNull,
    );
  });

  test('week boundaries handle Sunday and year transitions', () {
    expect(dayKey(mondayOf(DateTime(2027, 1, 3))), '2026-12-28');
    expect(dayKey(mondayOf(DateTime(2026, 10, 23))), '2026-10-19');
  });

  test(
    'Draft content preserves blocks and links while rejecting executable links',
    () {
      final content = jsonEncode({
        'blocks': [
          {
            'text': '阅读材料',
            'type': 'unstyled',
            'inlineStyleRanges': [
              {'offset': 0, 'length': 2, 'style': 'BOLD'},
            ],
            'entityRanges': [
              {'offset': 0, 'length': 4, 'key': 0},
            ],
          },
          {
            'text': ' ',
            'type': 'atomic',
            'entityRanges': [
              {'offset': 0, 'length': 1, 'key': 1},
            ],
          },
        ],
        'entityMap': {
          '0': {
            'type': 'LINK',
            'data': {'url': 'https://example.com/article'},
          },
          '1': {
            'type': 'IMAGE',
            'data': {'src': 'javascript:alert(1)'},
          },
        },
      });
      final blocks = parseDocument(content);
      expect(blocks.first.text, '阅读材料');
      expect(blocks.first.links.single.url, 'https://example.com/article');
      expect(blocks.last.media, isEmpty);
      expect(safeDocumentUrl('file:///etc/passwd'), isNull);
      expect(safeDocumentUrl('https://example.com/a.pdf'), isNotNull);
    },
  );

  test('overlapping courses occupy separate columns; non-overlapping courses regain full width', () {
    Lesson lesson(String id, int start, int end) => Lesson(
      id: id,
      title: id,
      start: DateTime(2026, 10, 23, 8, start),
      end: DateTime(2026, 10, 23, 8, end),
    );
    final positioned = layoutLessons([
      lesson('a', 0, 40),
      lesson('b', 10, 30),
      lesson('c', 50, 90),
    ]);
    expect(positioned[0].columns, 2);
    expect(positioned[1].column, 1);
    expect(positioned.last.columns, 1);
  });

  test('message parsing uses Mongo ID and searchable Draft text', () {
    final message = CampusMessage.fromJson({
      '_id': 'abc',
      'title': '通知',
      'content': jsonEncode({
        'blocks': [
          {'text': '可搜索正文'},
        ],
      }),
      'published_at': '2026-10-22 18:30:00',
      'readed': false,
    }, system: false);
    expect(message.id, 'abc');
    expect(message.preview, '可搜索正文');
    expect(message.read, false);
  });

  test('HTML image URLs are available for preloading without loading executable schemes', () {
    final blocks = parseDocument(
      '<p>正文</p><img src="https://example.com/photo.png"><img src="javascript:alert(1)">',
    );
    final images = blocks.expand((block) => block.media).toList();
    expect(images.single.url, 'https://example.com/photo.png');
  });

  test(
    'touching short appointments stay full-width with readable overlay height',
    () {
      final a = Lesson(
        id: 'a',
        title: '入校',
        start: DateTime(2026, 10, 23, 7, 55),
        end: DateTime(2026, 10, 23, 8),
      );
      final b = Lesson(
        id: 'b',
        title: '第一节',
        start: a.end,
        end: DateTime(2026, 10, 23, 8, 40),
      );
      final positions = layoutLessons([a, b]);
      expect(positions.map((p) => p.columns), everyElement(1));
      expect(positions.map((p) => p.column), everyElement(0));
      expect(lessonTileHeight(a, 72), 24);
      expect(lessonTileHeight(a, 72), greaterThan(5 * 72 / 60));
      expect(lessonTileHeight(b, 72), greaterThan(40));
    },
  );

  test(
    'real overlaps still share columns while adjacent long courses do not',
    () {
      final a = Lesson(
        id: 'a',
        title: 'a',
        start: DateTime(2026, 10, 23, 8),
        end: DateTime(2026, 10, 23, 8, 40),
      );
      final b = Lesson(
        id: 'b',
        title: 'b',
        start: DateTime(2026, 10, 23, 8, 10),
        end: DateTime(2026, 10, 23, 8, 30),
      );
      final c = Lesson(
        id: 'c',
        title: 'c',
        start: a.end,
        end: DateTime(2026, 10, 23, 9, 20),
      );
      expect(layoutLessons([a, b, c]).map((p) => p.columns), [2, 2, 1]);
      expect(lessonTileHeight(a, 72), greaterThan(40));
    },
  );
}
