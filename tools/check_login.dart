import 'dart:io';

import 'package:seiue_mac/api.dart';
import 'package:seiue_mac/models.dart';
import 'package:seiue_mac/approval_models.dart';

Future<void> main(List<String> arguments) async {
  stdout.write('Account: ');
  final account = stdin.readLineSync() ?? '';
  stdout.write('Password: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  final api = SeiueApi();
  try {
    final session = await api.login(account, password);
    stdout.writeln('Login success. Current identity: ${session.identity.id}');
    final lessons = await api.lessons(mondayOf(DateTime.now()));
    final notices = await api.messages(system: false);
    final system = await api.messages(system: true);
    stdout.writeln(
      'Lessons: ${lessons.length}; Notices: ${notices.items.length}; System: ${system.items.length}',
    );
    stdout.writeln(
      'More notices: ${notices.hasMore}; More system messages: ${system.hasMore}',
    );
    if (arguments.contains('--renew-session')) {
      stdout.writeln(
        'Passport renewal available: ${api.canRenew}; cookies: ${api.session!.passportCookies.length}',
      );
      final before = api.session!;
      api.session = CampusSession(
        token: before.token,
        tokenType: before.tokenType,
        identity: before.identity,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        passportCookies: before.passportCookies,
      );
      var changes = 0;
      api.onSessionChanged = (_) async {
        changes++;
      };
      await Future.wait([
        api.messages(system: false),
        api.messages(system: true),
        api.lessons(mondayOf(DateTime.now())),
      ]);
      stdout.writeln(
        'Expired access deadline renewed: ${api.session!.expiresAt.isAfter(DateTime.now())}; renewal events: $changes',
      );
      stdout.writeln(
        'Renewed token lifetime in minutes: ${api.session!.expiresAt.difference(DateTime.now()).inMinutes}',
      );
      // Simulate restarting the data layer with only a serialized remembered
      // session. The temporary payload stays in process memory, never on disk.
      final payload = api.session!.toJson();
      final restarted = SeiueApi()..session = CampusSession.fromJson(payload);
      try {
        await restarted.ensureSession(force: true);
        await restarted.messages(system: false);
        stdout.writeln(
          'Serialized-session reauthorization and business request succeeded.',
        );
      } finally {
        restarted.close();
      }
    }
    if (arguments.contains('--approvals')) {
      final templates = await api.approvalTemplates();
      stdout.writeln('Available approval templates: ${templates.length}');
      for (final tab in [
        ApprovalTab.initiated,
        ApprovalTab.handling,
        ApprovalTab.copied,
      ]) {
        final result = await api.approvals(tab);
        stdout.writeln(
          '${tab.name}: ${result.items.length}/${result.total}; more: ${result.hasMore}',
        );
        for (final record in result.items) {
          final detail = await api.approvalDetail(record);
          stdout.writeln(
            'Detail: ${detail.displayedFields.length} visible fields; ${detail.nodes.length} nodes; template resolved: ${detail.template != null}',
          );
        }
      }
    }
    if (arguments.contains('--subjects')) {
      final subjects = await api.subjects();
      stdout.writeln('Current-term subjects: ${subjects.length}');
      for (final subject in subjects) {
        final grades = await api.subjectGrades(subject);
        final tasks = await api.subjectTasks(subject);
        final attendance = await api.subjectAttendance(subject);
        final members = await api.subjectMembers(subject);
        stdout.writeln(
          'Subject ${subject.id}: grade entries ${grades.entries.length}; tasks ${tasks.items.length}; attendance ${attendance.items.length}; members ${members.items.length}',
        );
      }
    }
  } catch (error) {
    stdout.writeln(error);
    exitCode = 1;
  } finally {
    api.close();
  }
}
