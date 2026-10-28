import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'main.dart' show SmallTag, StatusPanel;
import 'models.dart';
import 'theme.dart';

const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key, required this.controller, this.query = ''});
  final CampusController controller;
  final String query;
  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  bool agenda = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        p = CampusPalette.of(context),
        end = c.week.add(const Duration(days: 6));
    final query = widget.query.toLowerCase().trim();
    final lessons = c.lessons
        .where(
          (lesson) => '${lesson.title} ${lesson.location} ${lesson.teachers}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${c.week.year}年 ${c.week.month}月',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${c.week.month}.${c.week.day} — ${end.month}.${end.day}',
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上一周',
                          onPressed: () => c.changeWeek(-1),
                          icon: const Icon(
                            CupertinoIcons.chevron_left,
                            size: 16,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: c.goToday,
                          child: const Text('今天'),
                        ),
                        IconButton(
                          tooltip: '下一周',
                          onPressed: () => c.changeWeek(1),
                          icon: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('周视图')),
                            ButtonSegment(value: true, label: Text('日程')),
                          ],
                          selected: {agenda || compact},
                          onSelectionChanged: compact
                              ? null
                              : (value) => setState(() => agenda = value.first),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (c.scheduleError != null)
                Expanded(
                  child: StatusPanel(
                    title: '课表暂时无法加载',
                    subtitle: c.scheduleError!,
                    icon: CupertinoIcons.wifi_exclamationmark,
                    retry: c.expired ? null : c.loadSchedule,
                  ),
                )
              else if (c.scheduleLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (lessons.isEmpty)
                Expanded(
                  child: StatusPanel(
                    title: query.isEmpty ? '这一周暂无课程' : '没有找到相关课程',
                    subtitle: query.isEmpty
                        ? '换一周看看，或刷新获取最新课表。'
                        : '试试课程名称、教师或教室。',
                    icon: CupertinoIcons.calendar,
                    retry: query.isEmpty ? c.loadSchedule : null,
                  ),
                )
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: p.line),
                          ),
                          child: agenda || compact
                              ? _Agenda(controller: c, lessons: lessons)
                              : _WeekGrid(controller: c, lessons: lessons),
                        ),
                      ),
                      if (constraints.maxWidth >= 1100) ...[
                        const SizedBox(width: 16),
                        SizedBox(width: 254, child: _TodayPanel(controller: c)),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.checkmark_shield,
                    size: 13,
                    color: p.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      c.demo
                          ? '演示课表 · 登录后同步真实课程'
                          : c.scheduleSynced == null
                          ? '尚未同步'
                          : '同步于 ${clockTime(c.scheduleSynced!)} · 本周 ${c.lessons.length} 项日程',
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ),
                  Text(
                    '点击课程查看详情',
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.controller, required this.lessons});
  final CampusController controller;
  final List<Lesson> lessons;
  static const hourHeight = 72.0;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context), now = DateTime.now();
    final earliest = lessons
        .map((lesson) => lesson.start.hour)
        .fold(7, (a, b) => a < b ? a : b);
    final latest = lessons
        .map((lesson) => lesson.end.hour + (lesson.end.minute > 0 ? 1 : 0))
        .fold(18, (a, b) => a > b ? a : b)
        .clamp(0, 24);
    final hours = latest - earliest;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 52),
            for (int day = 0; day < 7; day++)
              Expanded(
                child: _DayHeader(
                  date: controller.week.add(Duration(days: day)),
                  selected: sameDay(
                    controller.week.add(Duration(days: day)),
                    now,
                  ),
                  onTap: () => controller.selectDay(
                    controller.week.add(Duration(days: day)),
                  ),
                ),
              ),
          ],
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: hours * hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Stack(
                      children: [
                        for (int hour = earliest; hour < latest; hour++)
                          Positioned(
                            top: (hour - earliest) * hourHeight + 8,
                            left: 9,
                            child: Text(
                              '${pad(hour)}:00',
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 10,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (int day = 0; day < 7; day++)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final date = controller.week.add(Duration(days: day));
                          final dayLessons = lessons
                              .where((lesson) => sameDay(lesson.start, date))
                              .toList();
                          // Paint short entries last so their readable minimum
                          // height can cover the following course, as on Seiue.
                          final positions = layoutLessons(dayLessons)
                            ..sort((a, b) {
                              final duration = b.lesson.end
                                  .difference(b.lesson.start)
                                  .compareTo(
                                    a.lesson.end.difference(a.lesson.start),
                                  );
                              return duration != 0
                                  ? duration
                                  : a.lesson.start.compareTo(b.lesson.start);
                            });
                          return Container(
                            decoration: BoxDecoration(
                              color: sameDay(date, now)
                                  ? p.primary.withValues(alpha: .025)
                                  : null,
                              border: Border(left: BorderSide(color: p.line)),
                            ),
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                for (int hour = 0; hour < hours; hour++)
                                  Positioned(
                                    top: hour * hourHeight,
                                    left: 0,
                                    right: 0,
                                    child: Divider(
                                      color: p.line.withValues(alpha: .65),
                                    ),
                                  ),
                                for (final position in positions)
                                  Positioned(
                                    top:
                                        ((position.lesson.start.hour -
                                                        earliest) *
                                                    60 +
                                                position.lesson.start.minute) *
                                            hourHeight /
                                            60 +
                                        2,
                                    left:
                                        4 +
                                        position.column *
                                            (constraints.maxWidth - 8) /
                                            position.columns,
                                    width:
                                        (constraints.maxWidth - 8) /
                                            position.columns -
                                        2,
                                    height: lessonTileHeight(
                                      position.lesson,
                                      hourHeight,
                                      minimumHeight:
                                          MediaQuery.textScalerOf(context)
                                              .scale(14) +
                                          10,
                                    ),
                                    child: _LessonTile(
                                      key: ValueKey(
                                        'week-lesson-${position.lesson.id}',
                                      ),
                                      lesson: position.lesson,
                                      compact: true,
                                    ),
                                  ),
                                if (sameDay(date, now) &&
                                    now.hour >= earliest &&
                                    now.hour < latest)
                                  Positioned(
                                    top:
                                        ((now.hour - earliest) * 60 +
                                            now.minute) *
                                        hourHeight /
                                        60,
                                    left: 0,
                                    right: 0,
                                    child: IgnorePointer(
                                      child: Container(
                                        height: 2,
                                        color: p.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LessonPosition {
  LessonPosition(this.lesson, this.column, this.columns);
  final Lesson lesson;
  final int column;
  int columns;
}

double lessonTileHeight(
  Lesson lesson,
  double hourHeight, {
  double minimumHeight = 24,
}) {
  return (lesson.end.difference(lesson.start).inMicroseconds /
              Duration.microsecondsPerMinute *
              hourHeight /
              60 -
          4)
      .clamp(minimumHeight, double.infinity);
}

List<LessonPosition> layoutLessons(List<Lesson> lessons) {
  final sorted = [...lessons]..sort((a, b) => a.start.compareTo(b.start));
  final result = <LessonPosition>[], group = <LessonPosition>[];
  final ends = <DateTime>[];
  void flush() {
    for (final position in group) {
      position.columns = ends.length;
    }
    group.clear();
    ends.clear();
  }

  for (final lesson in sorted) {
    if (ends.isNotEmpty && ends.every((end) => !end.isAfter(lesson.start))) {
      flush();
    }
    var column = ends.indexWhere((end) => !end.isAfter(lesson.start));
    if (column < 0) {
      column = ends.length;
      ends.add(lesson.end);
    } else {
      ends[column] = lesson.end;
    }
    final position = LessonPosition(lesson, column, 1);
    group.add(position);
    result.add(position);
  }
  flush();
  return result;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.selected,
    required this.onTap,
  });
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              weekdays[date.weekday - 1],
              style: TextStyle(color: p.muted, fontSize: 11),
            ),
            const SizedBox(height: 5),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.transparent),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: selected ? p.primary : p.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({super.key, required this.lesson, this.compact = false});
  final Lesson lesson;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context);
    final tone =
        p.courseColors[lesson.title.runes.fold(0, (a, b) => a + b) %
            p.courseColors.length];
    final textTone = p.courseText(tone);
    return Tooltip(
      message:
          '${lesson.title}\n${clockTime(lesson.start)}–${clockTime(lesson.end)}\n${lesson.location}  ${lesson.teachers}',
      child: Material(
        color: Color.alphaBlend(tone.withValues(alpha: .15), p.surface),
        borderRadius: BorderRadius.circular(2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showLesson(context, lesson),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: tone.withValues(alpha: .3), width: 1),
              ),
            ),
            padding: EdgeInsets.all(compact ? 4 : 12),
            child: compact
                ? LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            lesson.title,
                            maxLines: constraints.maxHeight < 50 ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textTone,
                              fontSize: 11,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (constraints.maxHeight >
                            MediaQuery.textScalerOf(context).scale(28))
                          Text(
                            '${clockTime(lesson.start)}–${clockTime(lesson.end)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: textTone),
                          ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 62,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              clockTime(lesson.start),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textTone,
                              ),
                            ),
                            Text(
                              clockTime(lesson.end),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lesson.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                lesson.location,
                                lesson.teachers,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(CupertinoIcons.chevron_right, size: 14, color: tone),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Agenda extends StatelessWidget {
  const _Agenda({required this.controller, required this.lessons});
  final CampusController controller;
  final List<Lesson> lessons;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      for (int day = 0; day < 7; day++) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 14),
          child: Text(
            '${weekdays[day]}  ·  ${controller.week.add(Duration(days: day)).month}月${controller.week.add(Duration(days: day)).day}日',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (!lessons.any(
          (lesson) =>
              sameDay(lesson.start, controller.week.add(Duration(days: day))),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              '暂无日程',
              style: TextStyle(color: CampusPalette.of(context).muted),
            ),
          ),
        for (final lesson in lessons.where(
          (lesson) =>
              sameDay(lesson.start, controller.week.add(Duration(days: day))),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LessonTile(lesson: lesson),
          ),
      ],
    ],
  );
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({required this.controller});
  final CampusController controller;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context), c = controller, now = DateTime.now();
    final day = c.selectedDay;
    final items = c.lessons
        .where((lesson) => sameDay(lesson.start, day))
        .toList();
    final next = items.where((lesson) => lesson.end.isAfter(now));
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sameDay(day, now) ? '今天的安排' : '${day.month}月${day.day}日安排',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pad(day.day),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${day.month}月 · ${weekdays[day.weekday - 1]}',
                  style: TextStyle(color: p.muted),
                ),
                const SizedBox(height: 12),
                Text(
                  '共 ${items.length} 项日程',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (sameDay(day, now) && next.isNotEmpty) ...[
            SmallTag(next.first.start.isBefore(now) ? '正在进行' : '接下来'),
            const SizedBox(height: 12),
            Text(
              next.first.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${clockTime(next.first.start)} — ${clockTime(next.first.end)}',
              style: TextStyle(color: p.muted),
            ),
            const SizedBox(height: 6),
            Text(
              next.first.location,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 20),
          ],
          for (final lesson in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () => showLesson(context, lesson),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          CupertinoIcons.circle,
                          size: 10,
                          color: p.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lesson.title,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              clockTime(lesson.start),
                              style: TextStyle(color: p.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (items.isEmpty)
            Text(
              '今天没有安排，留一点时间给自己。',
              style: TextStyle(color: p.muted, height: 1.7),
            ),
        ],
      ),
    );
  }
}

void showLesson(BuildContext context, Lesson lesson) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(lesson.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${lesson.start.month}月${lesson.start.day}日  ${weekdays[lesson.start.weekday - 1]}',
            ),
            const SizedBox(height: 12),
            Text('${clockTime(lesson.start)} — ${clockTime(lesson.end)}'),
            const SizedBox(height: 20),
            if (lesson.location.isNotEmpty) Text('地点  ${lesson.location}'),
            if (lesson.teachers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('教师  ${lesson.teachers}'),
              ),
            if (lesson.group.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('班级  ${lesson.group}'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
