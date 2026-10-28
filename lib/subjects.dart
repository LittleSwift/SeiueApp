import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'main.dart' show SmallTag, StatusPanel;
import 'models.dart';
import 'rich_document.dart';
import 'subject_models.dart';
import 'theme.dart';

class SubjectsView extends StatelessWidget {
  const SubjectsView({super.key, required this.controller, this.query = ''});
  final CampusController controller;
  final String query;
  @override
  Widget build(BuildContext context) {
    final c = controller,
        p = CampusPalette.of(context),
        subject = c.selectedSubject;
    final filter = query.toLowerCase().trim();
    bool matches(String text) => text.toLowerCase().contains(filter);
    if (subject == null) {
      if (c.subjectsLoading && c.subjects.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.subjectsError != null && c.subjects.isEmpty) {
        return StatusPanel(
          title: '科目暂时无法加载',
          subtitle: c.subjectsError!,
          icon: CupertinoIcons.book,
          retry: c.loadSubjects,
        );
      }
      final subjects = c.subjects.where((s) => matches(s.label)).toList();
      if (subjects.isEmpty) {
        return StatusPanel(
          title: filter.isEmpty ? '当前学期暂无科目' : '没有找到相关科目',
          subtitle: '可以刷新，或使用科目名称搜索。',
          icon: CupertinoIcons.book,
          retry: c.loadSubjects,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        itemCount: subjects.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = subjects[index];
          return Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(6),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: Icon(CupertinoIcons.book, color: p.primary, size: 20),
              title: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  item.className,
                  item.tag,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: () => c.selectSubject(item),
            ),
          );
        },
      );
    }
    final state = c.subjectSection;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                subject.className,
                                subject.tag,
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: c.clearSelectedSubject,
                        child: const Text('全部科目'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DefaultTabController(
                    key: ValueKey(subject.id),
                    length: 4,
                    initialIndex: c.subjectTab.index,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 20),
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      onTap: (index) =>
                          c.selectSubjectTab(SubjectTab.values[index]),
                      tabs: [
                        for (final label in subjectTabLabels) Tab(text: label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (state.error != null && state.data != null)
            MaterialBanner(
              content: Text(state.error!),
              actions: [
                TextButton(
                  onPressed: () => c.loadSubjectSection(force: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(6),
              clipBehavior: Clip.antiAlias,
              child: state.loading && state.data == null
                  ? const Center(child: CircularProgressIndicator())
                  : state.error != null && state.data == null
                  ? StatusPanel(
                      title: '${subjectTabLabels[c.subjectTab.index]}暂时无法加载',
                      subtitle: state.error!,
                      icon: CupertinoIcons.exclamationmark_circle,
                      retry: () => c.loadSubjectSection(force: true),
                    )
                  : _section(context, state, matches),
            ),
          ),
          if (state.loading && state.data != null)
            const LinearProgressIndicator(minHeight: 2),
          if (state.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: state.loading
                    ? null
                    : () => c.loadSubjectSection(more: true),
                child: const Text('加载更多'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(String title) => StatusPanel(
    title: title,
    subtitle: '当前页没有符合条件的记录。',
    icon: CupertinoIcons.doc_text,
  );
  Widget _section(
    BuildContext context,
    SubjectSectionState state,
    bool Function(String) matches,
  ) {
    final data = state.data;
    switch (controller.subjectTab) {
      case SubjectTab.grades:
        if (data is! GradeReport) return _empty('暂无成绩');
        return _Grades(report: data, matches: matches);
      case SubjectTab.tasks:
        final rows = data is SubjectPage<SubjectTask>
            ? data.items
                  .where(
                    (t) => matches(
                      '${t.title} ${t.content} ${t.creator} ${t.outline}',
                    ),
                  )
                  .toList()
            : <SubjectTask>[];
        if (rows.isEmpty) return _empty('暂无任务');
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final item = rows[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    item.outline,
                    item.creator,
                    item.due == null
                        ? '无截止时间'
                        : '截止 ${dayKey(item.due!)} ${clockTime(item.due!)}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
              ),
              trailing: SmallTag(item.statusLabel),
              onTap: () => _showTask(context, item),
            );
          },
        );
      case SubjectTab.attendance:
        if (data is! AttendancePage) return _empty('暂无考勤记录');
        final rows = data.items
            .where(
              (r) => matches(
                '${r.result} ${r.lesson} ${r.reason} ${r.start == null ? '' : dayKey(r.start!)}',
              ),
            )
            .toList();
        return Column(
          children: [
            if (data.statistics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final entry in data.statistics.entries)
                        SmallTag('${entry.key} ${entry.value}'),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: rows.isEmpty
                  ? _empty('暂无考勤记录')
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          title: Text(
                            item.start == null
                                ? item.lesson
                                : '${dayKey(item.start!)} · ${clockTime(item.start!)}${item.end == null ? '' : '–${clockTime(item.end!)}'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            [
                              item.lesson,
                              item.reason,
                            ].where((s) => s.isNotEmpty).join(' · '),
                          ),
                          trailing: SmallTag(item.result),
                        );
                      },
                    ),
            ),
          ],
        );
      case SubjectTab.members:
        final rows = data is SubjectPage<SubjectMember>
            ? data.items
                  .where((m) => matches('${m.name} ${m.number} ${m.roleLabel}'))
                  .toList()
            : <SubjectMember>[];
        if (rows.isEmpty) return _empty('暂无成员');
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final item = rows[index], p = CampusPalette.of(context);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 5,
              ),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: p.selected,
                child: Icon(
                  item.roleLabel == '教师'
                      ? CupertinoIcons.person_crop_rectangle
                      : CupertinoIcons.person,
                  size: 18,
                  color: p.primary,
                ),
              ),
              title: Text(item.name, style: const TextStyle(fontSize: 13)),
              subtitle: item.number.isEmpty ? null : Text(item.number),
              trailing: SmallTag(item.roleLabel),
            );
          },
        );
    }
  }

  void _showTask(BuildContext context, SubjectTask task) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(CupertinoIcons.xmark, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          SmallTag(task.statusLabel),
                          Text(task.creator),
                          if (task.due != null)
                            Text(
                              '截止 ${dayKey(task.due!)} ${clockTime(task.due!)}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      RichDocument(content: task.content, mac: controller.mac),
                      if (task.url != null && task.url!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: OutlinedButton.icon(
                            onPressed: () => controller.mac.openUrl(task.url!),
                            icon: const Icon(CupertinoIcons.link, size: 16),
                            label: const Text('打开任务资料'),
                          ),
                        ),
                      for (final attachment in task.attachments)
                        Builder(
                          builder: (context) {
                            final url = field(
                              attachment['url'] ?? attachment['download_url'],
                            );
                            return url.isEmpty
                                ? const SizedBox()
                                : TextButton.icon(
                                    onPressed: () =>
                                        controller.mac.openUrl(url),
                                    icon: const Icon(
                                      CupertinoIcons.paperclip,
                                      size: 16,
                                    ),
                                    label: Text(
                                      field(
                                        attachment['name'] ??
                                            attachment['filename'],
                                        '附件',
                                      ),
                                    ),
                                  );
                          },
                        ),
                      if (task.subTasks.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          '子任务',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final child in task.subTasks)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(child.title),
                            trailing: const Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                            ),
                            onTap: () => _showTask(context, child),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grades extends StatelessWidget {
  const _Grades({required this.report, required this.matches});
  final GradeReport report;
  final bool Function(String) matches;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context),
        rows = report.entries
            .where((e) => matches('${e.name} ${e.review}'))
            .toList();
    if (report.entries.isEmpty && report.score == '—') {
      return const StatusPanel(
        title: '暂无成绩',
        subtitle: '该科目尚未提供成绩。',
        icon: CupertinoIcons.chart_bar,
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('总成绩', style: TextStyle(color: p.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(
                    '${report.score} / ${report.fullScore}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SmallTag(report.status == 'published' ? '已发布' : '未发布'),
              if (report.level.isNotEmpty) Text('等级 ${report.level}'),
              if (report.review.isNotEmpty) Text(report.review),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('评价项成绩', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('没有找到相关成绩')),
        for (final item in rows)
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20 + item.depth.clamp(0, 3) * 12,
                  12,
                  20,
                  12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: item.isGroup
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (item.review.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                item.review,
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.isGroup && item.score == '—'
                                ? (item.fullScore == '—'
                                      ? ''
                                      : '占分 ${item.fullScore}')
                                : '${item.score} / ${item.fullScore}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!item.isGroup && item.status != 'published')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '未发布',
                                style: TextStyle(color: p.muted, fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
            ],
          ),
      ],
    );
  }
}
