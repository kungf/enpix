import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/shared/widgets/backup_progress_widgets.dart';
import 'package:enpix/services/upload/backup_task.dart';

void main() {
  Future<void> pumpHeader(WidgetTester tester, BackupTask task) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ProgressHeader(task: task)),
      ),
    );
  }

  BackupTask taskWith(BackupStatus status) => BackupTask(
        status: status,
        totalCount: 10,
        startedAt: DateTime(2026, 1, 1),
      );

  group('ProgressHeader', () {
    testWidgets('shows uploading state while running', (tester) async {
      await pumpHeader(tester, taskWith(BackupStatus.running));

      expect(find.text('正在备份...'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
    });

    testWidgets('shows WiFi waiting state when paused for WiFi',
        (tester) async {
      await pumpHeader(tester, taskWith(BackupStatus.waitingForWifi));

      expect(find.text('等待 WiFi...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('正在备份...'), findsNothing);
    });

    testWidgets('shows done state when completed', (tester) async {
      await pumpHeader(tester, taskWith(BackupStatus.completed));

      expect(find.text('备份完成'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });
}
