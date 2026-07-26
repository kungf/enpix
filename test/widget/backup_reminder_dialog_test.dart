import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/screens/settings/dialogs/backup_reminder_dialog.dart';

void main() {
  /// Helper: pump a MaterialApp with the dialog showing.
  /// Does NOT await the dialog result — rendering tests don't need it.
  Future<void> pumpReminderDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    // Fire-and-forget: the dialog future is intentionally not awaited here
    // so rendering tests don't hang. Button-tap tests capture the future
    // separately.
    unawaited(
      showBackupReminderDialog(
        tester.element(find.byType(SizedBox)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('showBackupReminderDialog', () {
    testWidgets('renders title and explanation', (tester) async {
      await pumpReminderDialog(tester);

      expect(find.text('备份恢复密钥'), findsOneWidget);
      expect(
        find.text(
          '恢复密钥是一组 24 个英文单词，'
          '它是你忘记密码时唯一能找回加密数据的方式。',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders warning content', (tester) async {
      await pumpReminderDialog(tester);

      expect(find.textContaining('端到端加密'), findsOneWidget);
      expect(find.textContaining('永久无法恢复'), findsOneWidget);
      expect(find.textContaining('密码管理器'), findsOneWidget);
    });

    testWidgets('renders action buttons', (tester) async {
      await pumpReminderDialog(tester);

      expect(find.text('稍后再说'), findsOneWidget);
      expect(find.text('立即备份'), findsOneWidget);
    });

    testWidgets('立即备份 returns true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      final future = showBackupReminderDialog(
        tester.element(find.byType(SizedBox)),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('立即备份'));
      await tester.pump();
      await tester.pump();

      expect(await future, isTrue);
    });

    testWidgets('稍后再说 returns false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      final future = showBackupReminderDialog(
        tester.element(find.byType(SizedBox)),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('稍后再说'));
      await tester.pump();
      await tester.pump();

      expect(await future, isFalse);
    });

    testWidgets('barrier tap does not dismiss', (tester) async {
      await pumpReminderDialog(tester);

      await tester.tapAt(const Offset(1, 1));
      await tester.pump();
      await tester.pump();

      // Dialog should still be visible since barrierDismissible is false.
      expect(find.text('备份恢复密钥'), findsOneWidget);
    });
  });
}
