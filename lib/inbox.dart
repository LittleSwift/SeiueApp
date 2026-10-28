import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'main.dart' show SmallTag, StatusPanel;
import 'models.dart';
import 'rich_document.dart';
import 'theme.dart';

class InboxView extends StatelessWidget {
  const InboxView({
    super.key,
    required this.controller,
    required this.query,
    required this.selected,
    required this.onSelect,
    required this.onBack,
  });
  final CampusController controller;
  final String query;
  final CampusMessage? selected;
  final ValueChanged<CampusMessage> onSelect;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final c = controller, state = c.inbox, p = CampusPalette.of(context);
    final needle = query.toLowerCase().trim();
    final messages = state.items
        .where(
          (message) =>
              (!state.unreadOnly || !message.read) &&
              '${message.title} ${message.sender} ${message.preview}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 20, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 860;
          final showList = twoColumns || selected == null;
          return Row(
            children: [
              if (showList)
                SizedBox(
                  width: twoColumns ? 328 : constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: false, label: Text('全部')),
                              ButtonSegment(value: true, label: Text('未读')),
                            ],
                            selected: {state.unreadOnly},
                            onSelectionChanged: (value) =>
                                c.toggleUnread(value.first),
                          ),
                          const Spacer(),
                          Text(
                            '${messages.length} 条已加载',
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (state.error != null || state.cacheError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  state.error ?? state.cacheError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: c.expired
                                    ? null
                                    : () => c.loadInbox(
                                        c.destination == Destination.system,
                                      ),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: state.loading && messages.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : messages.isEmpty
                            ? StatusPanel(
                                title: needle.isNotEmpty
                                    ? '没有找到相关消息'
                                    : state.unreadOnly
                                    ? '未读消息已处理完'
                                    : '暂时没有消息',
                                subtitle: needle.isNotEmpty
                                    ? '搜索范围为已加载消息，可加载更多历史消息。'
                                    : state.unreadOnly
                                    ? '新的校园动态会出现在这里。'
                                    : '刷新试试，或稍后再来。',
                                icon: CupertinoIcons.tray,
                              )
                            : ListView.builder(
                                key: PageStorageKey(
                                  'inbox-${c.destination}-${state.unreadOnly}',
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: EdgeInsets.zero,
                                  child: _MessageTile(
                                    message: messages[index],
                                    selected:
                                        selected?.id == messages[index].id,
                                    onTap: () => onSelect(messages[index]),
                                  ),
                                ),
                              ),
                      ),
                      if (state.hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed:
                                  state.loading ||
                                      state.moreLoading ||
                                      state.prefetching
                                  ? null
                                  : () => c.loadInbox(
                                      c.destination == Destination.system,
                                      more: true,
                                    ),
                              child: Text(
                                state.prefetching
                                    ? '正在后台预加载通知…'
                                    : state.moreLoading
                                    ? '正在加载…'
                                    : '加载更多历史消息',
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        c.demo
                            ? '演示消息 · 非真实校园数据'
                            : state.synced == null
                            ? '本地文字缓存 · 联网后同步'
                            : '上次同步 ${clockTime(state.synced!)} · 文字已本地保留',
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              if (twoColumns) const SizedBox(width: 16),
              if (twoColumns || selected != null)
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.line),
                    ),
                    child: selected == null
                        ? const StatusPanel(
                            title: '留一点空间，专注阅读',
                            subtitle: '从左侧选择一条消息，查看完整内容。',
                            icon: CupertinoIcons.doc_text,
                          )
                        : _MessageReader(
                            key: ValueKey(selected!.id),
                            message: selected!,
                            controller: c,
                            showBack: !twoColumns,
                            onBack: onBack,
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.selected,
    required this.onTap,
  });
  final CampusMessage message;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context), m = message;
    return Semantics(
      selected: selected,
      label: m.read ? '已读' : '未读',
      child: Material(
        color: selected ? p.selected : p.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: p.line),
                left: BorderSide(
                  color: selected ? p.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.important)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 5),
                        child: Icon(
                          CupertinoIcons.bolt_fill,
                          size: 13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: m.read
                              ? FontWeight.w500
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!m.read)
                      Padding(
                        padding: const EdgeInsets.only(top: 7, left: 8),
                        child: Icon(
                          CupertinoIcons.circle_fill,
                          size: 6,
                          color: p.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  m.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
                ),
                const SizedBox(height: 8),
                Text(
                  '${m.created.month}月${m.created.day}日 ${clockTime(m.created)}   ${m.sender}',
                  style: TextStyle(color: p.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageReader extends StatelessWidget {
  const _MessageReader({
    super.key,
    required this.message,
    required this.controller,
    required this.showBack,
    required this.onBack,
  });
  final CampusMessage message;
  final CampusController controller;
  final bool showBack;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context), m = message;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  tooltip: '返回消息列表（Esc）',
                  onPressed: onBack,
                  icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                ),
              Icon(
                m.system ? CupertinoIcons.bell : CupertinoIcons.doc_text,
                size: 16,
                color: p.muted,
              ),
              const SizedBox(width: 8),
              Text(
                m.system ? '系统消息' : '校园通知',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              const Spacer(),
              if (m.read)
                Icon(
                  CupertinoIcons.checkmark_circle,
                  color: p.primary,
                  size: 16,
                ),
              const SizedBox(width: 6),
              Text(
                m.read ? '已读' : '未读',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
              IconButton(
                tooltip: '在希悦官网查看完整消息',
                onPressed: () async {
                  final url = m.system
                      ? 'https://chalk-c3.seiue.com/'
                      : noticeWebUrl(m.id);
                  try {
                    await controller.mac.openUrl(url);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('无法打开浏览器，请稍后重试。')),
                      );
                    }
                  }
                },
                icon: const Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 17,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.cached) ...[
                      const SmallTag('本地文字缓存'),
                      const SizedBox(height: 12),
                    ],
                    if (m.important) ...[
                      SmallTag('重要通知', color: p.warm),
                      const SizedBox(height: 16),
                    ],
                    SelectableText(
                      m.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          m.sender,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        Text(
                          '${m.created.year}年${m.created.month}月${m.created.day}日 ${clockTime(m.created)}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 28),
                    RichDocument(
                      content: m.content,
                      mac: controller.mac,
                      plainText: m.cached,
                    ),
                    if (m.system &&
                        m.url != null &&
                        safeDocumentUrl(m.url) != null) ...[
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () => controller.mac.openUrl(m.url!),
                        child: const Text('查看相关内容'),
                      ),
                    ],
                    const SizedBox(height: 40),
                    const Divider(),
                    const SizedBox(height: 20),
                    Text(
                      '内容来自希悦校园系统。需要回执、审批或其他操作时，请在官网完成。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 11,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
