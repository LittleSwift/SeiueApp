import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'approval_models.dart';
import 'controller.dart';
import 'main.dart' show SmallTag, StatusPanel;
import 'models.dart';
import 'rich_document.dart';
import 'subject_models.dart';
import 'theme.dart';

class ApprovalsView extends StatelessWidget {
  const ApprovalsView({super.key, required this.controller, this.query = ''});
  final CampusController controller;
  final String query;
  bool matches(String value) =>
      value.toLowerCase().contains(query.trim().toLowerCase());
  @override
  Widget build(BuildContext context) {
    final c = controller, a = c.approvals, p = CampusPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(6),
            child: DefaultTabController(
              key: ValueKey(a.tab),
              length: ApprovalTab.values.length,
              initialIndex: a.tab.index,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                onTap: (i) => a.selectTab(ApprovalTab.values[i]),
                tabs: [for (final label in approvalTabLabels) Tab(text: label)],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!c.mac.embeddedApprovalPortal)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '填写和处理申请将在默认浏览器打开，需在浏览器单独登录。完成后返回此处刷新。',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
          if (c.approvalPortalError != null)
            MaterialBanner(
              content: Text(c.approvalPortalError!),
              actions: [
                TextButton(
                  onPressed: () => c.openApprovalPortal(approvalWebUrl(a.tab)),
                  child: const Text('重试'),
                ),
              ],
            ),
          if (c.approvalPortalOpening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                c.mac.embeddedApprovalPortal
                    ? '官方表单窗口已打开，关闭后将刷新审批记录。'
                    : '正在打开默认浏览器…',
              ),
            ),
          Expanded(
            child: Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(6),
              clipBehavior: Clip.antiAlias,
              child: a.selected != null
                  ? _ApprovalDetail(controller: c)
                  : a.tab == ApprovalTab.templates
                  ? _templates(context)
                  : _records(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templates(BuildContext context) {
    final a = controller.approvals;
    if (a.templatesLoading && a.templates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (a.templatesError != null && a.templates.isEmpty) {
      return StatusPanel(
        title: '申请类型暂时无法加载',
        subtitle: a.templatesError!,
        icon: CupertinoIcons.doc_text,
        retry: () => a.load(force: true),
      );
    }
    final rows = a.templates
        .where((t) => matches('${t.name} ${t.category} ${t.description}'))
        .toList();
    final groups = <String, List<ApprovalTemplate>>{};
    for (final t in rows) {
      groups.putIfAbsent(t.category, () => []).add(t);
    }
    final entries = <Object>[];
    for (final entry in groups.entries) {
      entries.add(entry.key);
      entries.addAll(entry.value);
    }
    return Column(
      children: [
        if (a.templatesError != null)
          _error(a.templatesError!, () => a.load(force: true)),
        if (a.templatesLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: entries.isEmpty
              ? _empty(
                  query.isEmpty ? '暂无可发起的申请' : '没有找到相关申请',
                  '这里只显示当前身份可用的审批类型。',
                )
              : ListView.builder(
                  key: const PageStorageKey('approval-templates'),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final item = entries[i];
                    if (item is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Text(
                          item,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      );
                    }
                    final template = item as ApprovalTemplate;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: Icon(
                        CupertinoIcons.doc_text,
                        size: 22,
                        color: CampusPalette.of(context).primary,
                      ),
                      title: Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: template.description.isEmpty
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                parseDocument(template.description)
                                    .map((b) => b.text)
                                    .join('\n'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 15,
                      ),
                      onTap: () => _showTemplate(context, template),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _records(BuildContext context) {
    final c = controller, a = c.approvals, state = a.list;
    final rows = state.items
        .where(
          (r) =>
              (state.status.isEmpty || r.status == state.status) &&
              matches(
                '${r.title} ${r.initiator} ${approvalStatus(r.status)} ${r.displayedFields.map((f) => f.text).join(' ')}',
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '共 ${state.total} 项审批',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              DropdownButton<String>(
                value: state.status,
                underline: const SizedBox(),
                onChanged: (value) {
                  if (value != null) a.filterStatus(value);
                },
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部状态')),
                  for (final e in approvalStatuses.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
              ),
              TextButton.icon(
                onPressed: c.demo || c.expired || c.approvalPortalOpening
                    ? null
                    : () => c.openApprovalPortal(approvalWebUrl(a.tab)),
                icon: const Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 16,
                ),
                label: const Text('打开官方审批中心'),
              ),
            ],
          ),
        ),
        const Divider(),
        if (state.error != null && state.items.isNotEmpty)
          _error(state.error!, () => a.load(force: true)),
        if (state.loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: state.loading && state.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null && state.items.isEmpty
              ? StatusPanel(
                  title: '审批记录暂时无法加载',
                  subtitle: state.error!,
                  icon: CupertinoIcons.doc_text,
                  retry: () => a.load(force: true),
                )
              : rows.isEmpty
              ? _empty(
                  query.isNotEmpty ? '没有找到相关审批' : '暂无审批记录',
                  query.isNotEmpty
                      ? '搜索范围为已加载记录，可以继续加载或清除搜索。'
                      : '可以切换页签或更换状态筛选。',
                )
              : ListView.separated(
                  key: PageStorageKey('approval-${a.tab.name}-${state.status}'),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final record = rows[i], p = CampusPalette.of(context);
                    return InkWell(
                      onTap: () => a.openDetail(record),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    record.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SmallTag(approvalStatus(record.status)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              [
                                record.initiator,
                                if (record.created != null)
                                  '${dayKey(record.created!)} ${clockTime(record.created!)}',
                                if (record.pendingPeople.isNotEmpty)
                                  '待 ${record.pendingPeople} 处理',
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                            if (record.displayedFields.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  record.displayedFields
                                      .take(2)
                                      .map((f) => '${f.label}：${f.text}')
                                      .join('\n'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              onPressed: state.loading ? null : () => a.load(more: true),
              child: Text(state.loading ? '加载中…' : '加载更多审批'),
            ),
          ),
      ],
    );
  }

  Widget _error(String text, VoidCallback retry) => MaterialBanner(
    content: Text(text),
    actions: [TextButton(onPressed: retry, child: const Text('重试'))],
  );
  Widget _empty(String title, String text) =>
      StatusPanel(title: title, subtitle: text, icon: CupertinoIcons.doc_text);
  void _showTemplate(BuildContext context, ApprovalTemplate template) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.name,
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
                      SmallTag(template.category),
                      const SizedBox(height: 16),
                      if (template.description.isNotEmpty)
                        RichDocument(
                          content: template.description,
                          mac: controller.mac,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        '申请表内容',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final f in template.fields.where(
                        (f) => jsonMap(f['container'])['hidden'] != true,
                      ))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: f['type'] == 'paragraph'
                              ? RichDocument(
                                  content: field(f['description']),
                                  mac: controller.mac,
                                )
                              : Text(
                                  '${field(f['label'])}${f['required'] == true ? ' *' : ''}',
                                ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        controller.mac.embeddedApprovalPortal
                            ? '在应用内的希悦官方表单中填写和提交，支持附件及学校设置的审批流程。'
                            : '在默认浏览器的希悦官方表单中填写和提交，需在浏览器单独登录。完成后返回应用刷新。',
                      ),
                      if (controller.demo)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('演示模式不会发起真实申请。'),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        controller.demo ||
                            controller.expired ||
                            controller.approvalPortalOpening
                        ? null
                        : () {
                            Navigator.pop(context);
                            controller.openApprovalPortal(template.createUrl);
                          },
                    icon: const Icon(CupertinoIcons.square_pencil, size: 17),
                    label: const Text('填写申请'),
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

class _ApprovalDetail extends StatelessWidget {
  const _ApprovalDetail({required this.controller});
  final CampusController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller,
        a = c.approvals,
        record = a.selected!,
        p = CampusPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回审批列表',
                onPressed: a.closeDetail,
                icon: const Icon(CupertinoIcons.chevron_left, size: 18),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  record.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              SmallTag(approvalStatus(record.status)),
            ],
          ),
        ),
        const Divider(),
        if (a.detailLoading) const LinearProgressIndicator(minHeight: 2),
        if (a.detailError != null)
          MaterialBanner(
            content: Text(a.detailError!),
            actions: [
              TextButton(
                onPressed: () => a.openDetail(record),
                child: const Text('重试'),
              ),
            ],
          ),
        Expanded(
          child: SelectionArea(
            child: ListView(
              key: const ValueKey('approval-detail'),
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    Text('申请人 ${record.initiator}'),
                    if (record.created != null)
                      Text(
                        '发起于 ${dayKey(record.created!)} ${clockTime(record.created!)}',
                      ),
                    if (record.finished != null)
                      Text(
                        '结束于 ${dayKey(record.finished!)} ${clockTime(record.finished!)}',
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('申请内容', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (record.displayedFields.isEmpty)
                  const Text('暂无可显示字段，可打开官方表单查看完整内容。'),
                for (final f in record.displayedFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.label,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          f.text,
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                        for (final attachment in f.attachments)
                          TextButton.icon(
                            onPressed: () => c.mac.openUrl(attachment.url),
                            icon: const Icon(
                              CupertinoIcons.paperclip,
                              size: 16,
                            ),
                            label: Text(attachment.name),
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 20),
                Text('审批流程', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (record.nodes.isEmpty) const Text('暂无处理记录。'),
                for (final node in record.nodes) _node(context, node),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: c.demo || c.expired || c.approvalPortalOpening
                    ? null
                    : () => c.openApprovalPortal(record.url(a.tab)),
                icon: const Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 16,
                ),
                label: const Text('在官方表单中查看 / 处理'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _node(BuildContext context, Json node) {
    final p = CampusPalette.of(context), stages = jsonRows(node['stages']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 12),
            child: Icon(
              node['status'] == 'approved'
                  ? CupertinoIcons.checkmark_circle
                  : CupertinoIcons.circle,
              size: 18,
              color: p.primary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${field(node['node_label'], '审批节点')} · ${approvalStatus(field(node['status']))}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                for (final stage in stages)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            field(jsonMap(stage['reflection'])['name']),
                            approvalStatus(field(stage['status'])),
                            field(stage['reviewed_at']),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        if (field(stage['remark']).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              field(stage['remark']),
                              style: const TextStyle(fontSize: 13, height: 1.6),
                            ),
                          ),
                        for (final attachment in ApprovalFieldValue(
                          '',
                          stage['attachments'],
                        ).attachments)
                          TextButton.icon(
                            onPressed: () =>
                                controller.mac.openUrl(attachment.url),
                            icon: const Icon(
                              CupertinoIcons.paperclip,
                              size: 16,
                            ),
                            label: Text(attachment.name),
                          ),
                      ],
                    ),
                  ),
                for (final comment in jsonRows(node['comments']))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${field(jsonMap(comment['reflection'])['name'])}：${field(comment['content'])}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
