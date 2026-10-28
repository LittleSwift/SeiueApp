import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'theme.dart';

Future<void> showNotificationSettings(
  BuildContext context,
  CampusController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final prefs = controller.notifications.preferences,
          p = CampusPalette.of(context);
      final windows = controller.mac.isWindows;
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '通知与提醒',
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
                const SizedBox(height: 16),
                Text(
                  controller.demo
                      ? '演示模式不会发送系统提醒'
                      : prefs.permission == 'systemManaged'
                      ? 'Windows 通知服务已接入，横幅与权限由 Windows 设置 → 系统 → 通知管理。'
                      : prefs.allowed
                      ? '${controller.mac.systemName} 通知已允许'
                      : prefs.permission == 'denied'
                      ? 'macOS 通知已关闭。请在系统设置 → 通知 → Seiue 中允许通知。'
                      : '允许 macOS 通知后，即可接收课前和消息提醒。',
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
                if ((!prefs.allowed || windows) && !controller.demo)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: windows
                          ? () => controller.mac.openNotificationSettings()
                          : () => controller.updateNotificationPreferences(
                              classes: prefs.classes,
                              messages: prefs.messages,
                              request: true,
                            ),
                      child: Text(windows ? '打开 Windows 通知设置' : '允许通知'),
                    ),
                  ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('课前提醒', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('每节课开始前 10 分钟提醒'),
                  value: prefs.classes,
                  onChanged: controller.demo
                      ? null
                      : (v) => controller.updateNotificationPreferences(
                          classes: v,
                          messages: prefs.messages,
                        ),
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('新消息提醒', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('校园通知和系统消息'),
                  value: prefs.messages,
                  onChanged: controller.demo
                      ? null
                      : (v) => controller.updateNotificationPreferences(
                          classes: prefs.classes,
                          messages: v,
                        ),
                ),
                const SizedBox(height: 16),
                if (prefs.allowed && prefs.classes && !controller.demo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '未来两周已安排 ${prefs.scheduledClasses} 条课前提醒',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ),
                Text(
                  windows
                      ? '最小化窗口可继续每分钟检查新消息。关闭窗口会退出应用并停止同步；已安排的课前提醒由 Windows 发送。退出登录会取消待发送提醒，便携版可能无法清除已送达的通知。'
                      : '关闭窗口后仍会每分钟检查新消息，可从菜单栏重新打开。彻底退出后停止同步；已安排的课前提醒仍由 macOS 发送，直到重新同步或退出登录。',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.6),
                ),
                if (controller.notificationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      controller.notificationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (!controller.demo && prefs.allowed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: controller.sendTestNotification,
                      child: const Text('发送测试提醒'),
                    ),
                  ),
                if (!controller.demo &&
                    (prefs.testDelivered ||
                        controller.notificationTestStatus != null))
                  Text(
                    prefs.testDelivered
                        ? '测试提醒已送达通知中心'
                        : controller.notificationTestStatus!,
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  ),
);
