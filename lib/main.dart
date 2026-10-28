import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'models.dart';
import 'theme.dart';
import 'schedule.dart';
import 'inbox.dart';
import 'subjects.dart';
import 'approvals.dart';
import 'notification_settings.dart';

SingleActivator desktopShortcut(LogicalKeyboardKey key) => SingleActivator(
  key,
  meta: defaultTargetPlatform == TargetPlatform.macOS,
  control: defaultTargetPlatform != TargetPlatform.macOS,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SeiueApp());
}

class SeiueApp extends StatefulWidget {
  const SeiueApp({super.key, this.controller});
  final CampusController? controller;
  @override
  State<SeiueApp> createState() => _SeiueAppState();
}

class _SeiueAppState extends State<SeiueApp> {
  late final CampusController controller;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? CampusController();
    if (widget.controller == null) unawaited(controller.initialize());
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: '希悦 · ${controller.mac.appName}',
      debugShowCheckedModeBanner: false,
      theme: campusTheme(Brightness.light),
      darkTheme: campusTheme(Brightness.dark),
      themeMode: controller.themeMode,
      home: controller.booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : controller.signedIn
          ? CampusShell(controller: controller)
          : LoginScreen(controller: controller),
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final CampusController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final account = TextEditingController(), password = TextEditingController();
  bool visible = false;
  @override
  void dispose() {
    account.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    await widget.controller.login(
      account: account.text,
      password: password.text,
    );
    password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = CampusPalette.of(context);
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: p.line),
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.building_2_fill,
                                      color: p.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        '北大附中（高中本部）',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  '账号登录',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '使用你的希悦账号登录校园',
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                TextFormField(
                                  controller: account,
                                  enabled: !c.authenticating,
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    labelText: '账号',
                                    prefixIcon: Icon(
                                      CupertinoIcons.person,
                                      size: 18,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.next,
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? '请输入你的账号'
                                      : null,
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: password,
                                  enabled: !c.authenticating,
                                  obscureText: !visible,
                                  autofillHints: const [AutofillHints.password],
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    prefixIcon: const Icon(
                                      CupertinoIcons.lock,
                                      size: 18,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: visible ? '隐藏密码' : '显示密码',
                                      onPressed: () =>
                                          setState(() => visible = !visible),
                                      icon: Icon(
                                        visible
                                            ? CupertinoIcons.eye_slash
                                            : CupertinoIcons.eye,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? '请输入密码'
                                      : null,
                                  onFieldSubmitted: (_) =>
                                      c.authenticating ? null : submit(),
                                ),
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text(
                                      '保持登录',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      c.mac.isWindows
                                          ? '会话经 Windows 加密保存，不保存密码'
                                          : '会话存入 Mac 钥匙串，不保存密码',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    value: c.remember,
                                    onChanged: c.authenticating
                                        ? null
                                        : (value) =>
                                              c.setRemember(value ?? false),
                                  ),
                                ),
                                if (c.loginError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        c.loginError!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: c.authenticating ? null : submit,
                                  child: c.authenticating
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('登录校园'),
                                ),
                                const SizedBox(height: 12),
                                if (c.mac.supportsWebLogin)
                                  OutlinedButton(
                                    onPressed: c.authenticating
                                        ? null
                                        : () => c.login(web: true),
                                    child: const Text('使用官方网页登录'),
                                  ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: c.authenticating
                                      ? null
                                      : c.enterDemo,
                                  child: const Text('先体验一下  →'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '${c.mac.appName} · 独立开发的第三方客户端',
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CampusShell extends StatefulWidget {
  const CampusShell({super.key, required this.controller});
  final CampusController controller;
  @override
  State<CampusShell> createState() => _CampusShellState();
}

class _CampusShellState extends State<CampusShell> {
  final search = TextEditingController(), searchFocus = FocusNode();
  final scaffold = GlobalKey<ScaffoldState>();
  CampusMessage? selected;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_notificationOpened);
    _notificationOpened();
  }

  void _notificationOpened() {
    final message = widget.controller.notificationMessage;
    if (message == null) return;
    widget.controller.notificationMessage = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        search.clear();
        openMessage(message);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_notificationOpened);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void navigate(Destination destination) {
    search.clear();
    setState(() => selected = null);
    widget.controller.navigate(destination);
    scaffold.currentState?.closeDrawer();
  }

  Future<void> openMessage(CampusMessage message) async {
    setState(() => selected = message);
    final prepared = await widget.controller.prepareMessage(message);
    if (!mounted || selected?.id != message.id) return;
    setState(() => selected = prepared);
    final error = await widget.controller.markRead(prepared);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> logout() async {
    try {
      await widget.controller.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法清除登录状态，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = CampusPalette.of(context);
    final titles = ['我的课表', '校园通知', '系统消息', '科目', '审批中心'];
    return CallbackShortcuts(
      bindings: {
        desktopShortcut(LogicalKeyboardKey.digit1): () =>
            navigate(Destination.schedule),
        desktopShortcut(LogicalKeyboardKey.digit2): () =>
            navigate(Destination.notices),
        desktopShortcut(LogicalKeyboardKey.digit3): () =>
            navigate(Destination.system),
        desktopShortcut(LogicalKeyboardKey.digit4): () =>
            navigate(Destination.subjects),
        desktopShortcut(LogicalKeyboardKey.digit5): () =>
            navigate(Destination.approvals),
        desktopShortcut(LogicalKeyboardKey.keyR): () => c.refreshCurrent(),
        desktopShortcut(LogicalKeyboardKey.keyF): () =>
            searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (c.destination == Destination.approvals &&
              c.approvals.selected != null) {
            c.approvals.closeDetail();
          }
          setState(() => selected = null);
          searchFocus.unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1050;
            return Scaffold(
              key: scaffold,
              drawer: wide ? null : Drawer(width: 240, child: sidebar()),
              body: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (wide)
                          Container(
                            width: 232,
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: p.line)),
                            ),
                            child: sidebar(),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.sessionStorageError != null)
                                MaterialBanner(
                                  content: Text(c.sessionStorageError!),
                                  actions: [
                                    TextButton(
                                      onPressed: c.retrySessionSave,
                                      child: const Text('重试保存'),
                                    ),
                                  ],
                                ),
                              if (c.expired)
                                MaterialBanner(
                                  content: const Text('登录已过期，重新登录后即可继续同步。'),
                                  actions: [
                                    TextButton(
                                      onPressed: logout,
                                      child: const Text('重新登录'),
                                    ),
                                  ],
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  18,
                                  20,
                                  18,
                                ),
                                child: Row(
                                  children: [
                                    if (!wide)
                                      IconButton(
                                        tooltip: '打开导航',
                                        onPressed: () =>
                                            scaffold.currentState?.openDrawer(),
                                        icon: const Icon(
                                          CupertinoIcons.sidebar_left,
                                          size: 19,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        titles[c.destination.index],
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ),
                                    if (c.demo)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: SmallTag('演示模式'),
                                      ),
                                    SizedBox(
                                      width: constraints.maxWidth < 900
                                          ? 172
                                          : 240,
                                      child: TextField(
                                        controller: search,
                                        focusNode: searchFocus,
                                        style: const TextStyle(fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText:
                                              c.destination ==
                                                  Destination.schedule
                                              ? '搜索课程'
                                              : c.destination ==
                                                    Destination.subjects
                                              ? '搜索科目或当前页'
                                              : c.destination ==
                                                    Destination.approvals
                                              ? '搜索已加载审批'
                                              : '搜索已加载消息',
                                          prefixIcon: const Icon(
                                            CupertinoIcons.search,
                                            size: 16,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          suffixIcon: search.text.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: '清除搜索',
                                                  onPressed: () =>
                                                      setState(search.clear),
                                                  icon: const Icon(
                                                    CupertinoIcons.xmark,
                                                    size: 13,
                                                  ),
                                                ),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: c.mac.isWindows
                                          ? '刷新（Ctrl+R）'
                                          : '刷新（⌘R）',
                                      onPressed: c.expired
                                          ? null
                                          : c.refreshCurrent,
                                      icon: const Icon(
                                        CupertinoIcons.arrow_clockwise,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: c.destination == Destination.schedule
                                    ? ScheduleView(
                                        controller: c,
                                        query: search.text,
                                      )
                                    : c.destination == Destination.approvals
                                    ? ApprovalsView(
                                        controller: c,
                                        query: search.text,
                                      )
                                    : c.destination == Destination.subjects
                                    ? SubjectsView(
                                        controller: c,
                                        query: search.text,
                                      )
                                    : InboxView(
                                        controller: c,
                                        query: search.text,
                                        selected:
                                            selected?.system ==
                                                (c.destination ==
                                                    Destination.system)
                                            ? selected
                                            : null,
                                        onSelect: openMessage,
                                        onBack: () =>
                                            setState(() => selected = null),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget sidebar() {
    final c = widget.controller, p = CampusPalette.of(context);
    final courses = c.subjects;
    return Material(
      color: p.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final item in [
                    (Destination.schedule, CupertinoIcons.calendar, '课表'),
                    (Destination.notices, CupertinoIcons.bubble_left, '通知'),
                    (Destination.system, CupertinoIcons.bell, '系统消息'),
                    (Destination.subjects, CupertinoIcons.book, '科目'),
                    (Destination.approvals, CupertinoIcons.doc_text, '审批中心'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Semantics(
                        selected: c.destination == item.$1,
                        child: Material(
                          color: c.destination == item.$1
                              ? p.selected
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          child: ListTile(
                            dense: true,
                            minVerticalPadding: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            minLeadingWidth: 18,
                            leading: Icon(
                              item.$2,
                              size: 17,
                              color: c.destination == item.$1
                                  ? p.primary
                                  : p.muted,
                            ),
                            title: Text(
                              item.$3,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: c.destination == item.$1
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: c.destination == item.$1
                                    ? p.primary
                                    : p.ink,
                              ),
                            ),
                            trailing:
                                (item.$1 == Destination.notices ||
                                        item.$1 == Destination.system) &&
                                    (item.$1 == Destination.notices
                                            ? c.notices
                                            : c.system)
                                        .items
                                        .any((m) => !m.read)
                                ? Semantics(
                                    label: '有未读消息',
                                    child: Icon(
                                      CupertinoIcons.circle_fill,
                                      size: 6,
                                      color: p.primary,
                                    ),
                                  )
                                : null,
                            onTap: () => navigate(item.$1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 24, bottom: 12),
                      child: Text(
                        '本学期科目（${courses.length}）',
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ),
                    for (final lesson in courses)
                      Tooltip(
                        message: lesson.label,
                        child: ListTile(
                          dense: true,
                          selected:
                              c.destination == Destination.subjects &&
                              c.selectedSubject?.id == lesson.id,
                          selectedTileColor: p.selected,
                          minLeadingWidth: 18,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          leading: Icon(
                            CupertinoIcons.doc_text,
                            size: 16,
                            color: p.muted,
                          ),
                          title: Text(
                            lesson.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () {
                            search.clear();
                            setState(() => selected = null);
                            c.selectSubject(lesson);
                            scaffold.currentState?.closeDrawer();
                          },
                        ),
                      ),
                    if (courses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          c.subjectsLoading ? '正在同步科目…' : '刷新后显示本学期科目',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: PopupMenuButton<ThemeMode>(
                      tooltip: '外观',
                      initialValue: c.themeMode,
                      onSelected: c.setTheme,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: ThemeMode.system,
                          child: Text('跟随系统'),
                        ),
                        const PopupMenuItem(
                          value: ThemeMode.light,
                          child: Text('浅色'),
                        ),
                        const PopupMenuItem(
                          value: ThemeMode.dark,
                          child: Text('深色'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.circle_lefthalf_fill,
                              size: 16,
                              color: p.muted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '外观',
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '通知与提醒',
                    onPressed: () async {
                      await c.refreshNotificationStatus();
                      if (mounted) showNotificationSettings(context, c);
                    },
                    icon: Icon(
                      CupertinoIcons.bell,
                      size: 17,
                      color: c.notificationError == null
                          ? p.muted
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  IconButton(
                    tooltip: c.demo ? '退出演示，前往登录' : '退出登录',
                    onPressed: logout,
                    icon: const Icon(
                      CupertinoIcons.square_arrow_right,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: p.background,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '北大附中（高中本部）',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${c.mac.appName}  ·  0.4.1',
                    style: TextStyle(fontSize: 10, color: p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SmallTag extends StatelessWidget {
  const SmallTag(this.label, {super.key, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context), ink = color ?? p.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = CupertinoIcons.tray,
    this.retry,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) {
    final p = CampusPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: p.muted),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: p.muted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (retry != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton(
                  onPressed: retry,
                  child: const Text('重新加载'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
