import 'models.dart';

Json jsonMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> jsonRows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
String field(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';
String numberText(dynamic value) {
  if (value == null || '$value'.isEmpty) return '—';
  final n = double.tryParse('$value');
  return n == null
      ? '$value'
      : n.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class CampusSubject {
  const CampusSubject({
    required this.id,
    required this.groupId,
    required this.name,
    this.className = '',
    this.tag = '',
    this.semesterId = '',
  });
  final String id, groupId, name, className, tag, semesterId;
  String get label => className.isEmpty ? name : '$name · $className';
  factory CampusSubject.fromGroup(Json json) {
    final extra = jsonMap(json['extra_fields']);
    final grades = field(extra['grade_names']),
        group = field(extra['class_name']);
    return CampusSubject(
      id: field(json['biz_id']),
      groupId: field(json['id']),
      name: field(extra['name'], field(json['name'], '科目')),
      className: grades.isEmpty || group.contains(grades)
          ? group
          : '$grades$group',
      tag: field(extra['tag']),
      semesterId: field(jsonMap(json['labels'])['semester_id']),
    );
  }
}

enum SubjectTab { grades, tasks, attendance, members }

const subjectTabLabels = ['成绩', '任务', '考勤', '成员'];

class SubjectPage<T> {
  const SubjectPage(this.items, this.hasMore);
  final List<T> items;
  final bool hasMore;
}

class GradeEntry {
  const GradeEntry({
    required this.id,
    required this.name,
    required this.score,
    required this.fullScore,
    this.parentId = '',
    this.status = '',
    this.review = '',
    this.type = '',
    this.depth = 0,
    this.isGroup = false,
  });
  final String id, name, score, fullScore, parentId, status, review, type;
  final int depth;
  final bool isGroup;
}

class GradeReport {
  const GradeReport({
    required this.score,
    required this.fullScore,
    required this.status,
    required this.entries,
    this.level = '',
    this.review = '',
  });
  final String score, fullScore, status, level, review;
  final List<GradeEntry> entries;
  factory GradeReport.fromJson(Json assessment, List<Json> scores) {
    final grade = jsonMap(assessment['grade']);
    final byItem = {for (final score in scores) field(score['item_id']): score};
    final items = jsonRows(assessment['items']);
    items.sort(
      (a, b) => (num.tryParse(field(a['sort'])) ?? 0).compareTo(
        num.tryParse(field(b['sort'])) ?? 0,
      ),
    );
    final ids = items.map((e) => field(e['id'])).toSet(), visited = <String>{};
    final children = <String, List<Json>>{};
    for (final item in items) {
      children.putIfAbsent(field(item['pid']), () => []).add(item);
    }
    final ordered = <({Json item, int depth})>[];
    void visit(Json item, int depth) {
      final id = field(item['id']);
      if (!visited.add(id)) return;
      ordered.add((item: item, depth: depth));
      for (final child in children[id] ?? <Json>[]) {
        visit(child, depth + 1);
      }
    }

    for (final item in items.where(
      (item) => !ids.contains(field(item['pid'])),
    )) {
      visit(item, 0);
    }
    for (final item in items) {
      visit(item, 0);
    }
    return GradeReport(
      score: numberText(
        grade['student_real_score'] ?? grade['real_score'] ?? grade['score'],
      ),
      fullScore: numberText(assessment['full_score']),
      status: field(grade['status'], field(assessment['status'])),
      level: field(grade['level']),
      review: field(grade['review']),
      entries: ordered.map((entry) {
        final item = entry.item;
        final score = byItem[field(item['id'])] ?? <String, dynamic>{};
        return GradeEntry(
          id: field(item['id']),
          name: field(item['name']),
          score: numberText(
            score['score_display'] != null &&
                    '${score['score_display']}'.isNotEmpty
                ? score['score_display']
                : score['score'],
          ),
          fullScore: numberText(item['full_score'] ?? item['within_score']),
          parentId: field(item['pid']),
          status: field(score['status'], field(item['status'])),
          review: field(score['review']),
          type: field(item['type']),
          depth: entry.depth,
          isGroup:
              children[field(item['id'])]?.isNotEmpty == true ||
              field(item['type']).contains('dimension'),
        );
      }).toList(),
    );
  }
}

class SubjectTask {
  const SubjectTask({
    required this.id,
    required this.title,
    this.content = '',
    this.status = '',
    this.creator = '',
    this.outline = '',
    this.due,
    this.url,
    this.attachments = const [],
    this.subTasks = const [],
  });
  final String id, title, content, status, creator, outline;
  final DateTime? due;
  final String? url;
  final List<Json> attachments;
  final List<SubjectTask> subTasks;
  factory SubjectTask.fromJson(Json json) => SubjectTask(
    id: field(json['task_id'] ?? json['id']),
    title: field(json['title'], '任务'),
    content: field(json['content']),
    status: field(json['status']),
    creator: field(jsonMap(json['creator'])['name']),
    outline: field(jsonMap(json['outline'])['name']),
    due: parseDate(json['expired_at']),
    url: jsonMap(json['custom_fields'])['website_url']?.toString(),
    attachments: jsonRows(json['attachments']),
    subTasks: jsonRows(json['sub_tasks']).map(SubjectTask.fromJson).toList(),
  );
  String get statusLabel => switch (status) {
    'done' || 'finished' || 'achieved' || 'submitted' => '已完成',
    'read' => '已查看',
    'pending' || 'todo' || 'unsubmitted' || 'assigned' => '待完成',
    _ => status.isEmpty ? '未完成' : status,
  };
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.result,
    this.start,
    this.end,
    this.lesson = '',
    this.reason = '',
  });
  final String id, result, lesson, reason;
  final DateTime? start, end;
  factory AttendanceRecord.fromJson(Json json) => AttendanceRecord(
    id: field(json['id']),
    result: field(json['result'], field(json['tag'], '未记录')),
    start: parseDate(json['attendance_time_start']),
    end: parseDate(json['attendance_time_end']),
    lesson: field(jsonMap(json['class_lesson'])['lesson_name']),
    reason: field(
      json['updated_reason'] ?? jsonMap(json['absence_info'])['reason'],
    ),
  );
}

class AttendancePage extends SubjectPage<AttendanceRecord> {
  const AttendancePage(super.items, super.hasMore, this.statistics);
  final Map<String, int> statistics;
}

class SubjectMember {
  const SubjectMember({
    required this.id,
    required this.name,
    required this.role,
    this.number = '',
  });
  final String id, name, role, number;
  factory SubjectMember.fromJson(Json json) {
    final reflection = jsonMap(json['reflection']);
    return SubjectMember(
      id: field(reflection['id'] ?? json['member_id']),
      name: field(reflection['name'], '校园成员'),
      role: field(json['member_type'], field(reflection['role'])),
      number: field(reflection['usin'] ?? reflection['account']),
    );
  }
  String get roleLabel => switch (role) {
    'teacher' || 'master' => '教师',
    'student' || 'member' => '学生',
    'assistant' => '助教',
    _ => role,
  };
}
