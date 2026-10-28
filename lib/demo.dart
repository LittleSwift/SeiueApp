import 'models.dart';
import 'subject_models.dart';

List<Lesson> demoLessons(DateTime week) {
  final monday = mondayOf(week);
  final courses = [
    ('现代文学研读', '西楼 W504', '林老师'),
    ('Linear Algebra', '西楼 W614', '陈老师'),
    ('Physics & Energy', '西楼 W613', '王老师'),
    ('世界历史专题', '西楼 W507', '李老师'),
    ('College & Beyond', '西楼 W614', '刘老师'),
  ];
  return [
    for (int day = 0; day < 5; day++)
      for (int slot = 0; slot < 4; slot++)
        Lesson(
          id: '$day-$slot',
          title: courses[(day + slot) % courses.length].$1,
          start: monday.add(
            Duration(
              days: day,
              hours: [8, 9, 11, 14][slot],
              minutes: slot == 1 ? 50 : 30,
            ),
          ),
          end: monday.add(
            Duration(
              days: day,
              hours: [9, 10, 12, 15][slot],
              minutes: slot == 1 ? 30 : 10,
            ),
          ),
          location: courses[(day + slot) % courses.length].$2,
          teachers: courses[(day + slot) % courses.length].$3,
          group: '示例班级',
        ),
  ];
}

List<CampusMessage> demoMessages(bool system) {
  final now = DateTime.now();
  final values = system
      ? [
          ('课表已更新', '新一周的课表已更新。请在课表中查看具体课程、上课时间及地点。', '课表服务'),
          ('你有一条新的校园通知', '校园通知已发布，前往通知页面查看完整内容。', '通知服务'),
          (
            '欢迎使用 Seiue Mac',
            '课表、通知和系统消息，现已汇聚到你的 Mac。此处是演示数据，登录后将显示真实校园数据。',
            '希悦系统',
          ),
        ]
      : [
          (
            '把好奇心带进校园：秋季读书分享会',
            '同学们：\n\n新一期校园读书分享会即将开始。欢迎带上你最近读到的一本好书，与同学们分享阅读中的思考和发现。\n\n活动时间：本周五 16:30\n活动地点：图书馆一层阅览室\n\n每一次阅读，都是看见更大世界的开始。期待与你相见。\n\n本内容仅用于展示客户端界面。',
            '图书馆',
          ),
          (
            '关于本周校园活动安排的通知',
            '本周校园活动安排已发布，请同学们合理规划时间，留意各活动的地点与时间。\n\n这是演示通知，登录后会显示你的真实通知。',
            '学生成长中心',
          ),
          (
            '秋季学期课程学习指南',
            '在新学期里，继续保持好奇，主动提问，和老师、同学共同探索。\n\n课程详情请查看课表。',
            '学业管理中心',
          ),
          ('校园图书馆开放时间调整', '图书馆周一至周五开放时间为 08:00—18:00。欢迎同学们前来阅读。', '图书馆'),
        ];
  return [
    for (int i = 0; i < values.length; i++)
      CampusMessage(
        id: 'demo-${system ? 's' : 'n'}-$i',
        title: values[i].$1,
        content: values[i].$2,
        sender: values[i].$3,
        created: now.subtract(Duration(hours: i * 17 + 1)),
        read: i > 1,
        important: !system && i == 0,
        system: system,
      ),
  ];
}

Object demoSubjectSection(SubjectTab tab) => switch (tab) {
  SubjectTab.grades => const GradeReport(
    score: '92',
    fullScore: '100',
    status: 'published',
    entries: [
      GradeEntry(
        id: 'demo-grade',
        name: '课堂小测',
        score: '18',
        fullScore: '20',
        status: 'published',
        review: '思路清楚，继续保持。',
      ),
    ],
  ),
  SubjectTab.tasks => SubjectPage([
    SubjectTask(
      id: 'demo-task',
      title: '本周阅读与思考',
      content: '阅读本周材料，记录你最感兴趣的一个问题。',
      status: 'pending',
      creator: '任课教师',
      due: DateTime.now().add(const Duration(days: 2)),
    ),
  ], false),
  SubjectTab.attendance => AttendancePage(
    [
      AttendanceRecord(
        id: 'demo-attendance',
        result: '正常',
        start: DateTime.now(),
        lesson: '第 1 节',
      ),
    ],
    false,
    const {'正常': 12, '迟到': 0},
  ),
  SubjectTab.members => const SubjectPage([
    SubjectMember(id: 'demo-teacher', name: '任课教师', role: 'teacher'),
    SubjectMember(
      id: 'demo-student',
      name: '体验同学',
      role: 'student',
      number: 'DEMO',
    ),
  ], false),
};
