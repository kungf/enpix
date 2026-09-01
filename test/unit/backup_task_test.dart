import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/services/upload/backup_task.dart';

void main() {
  BackupTask taskWith(BackupStatus status) =>
      BackupTask(status: status, startedAt: DateTime(2026, 1, 1));

  group('BackupTask status semantics', () {
    test('running counts as running and not done', () {
      final task = taskWith(BackupStatus.running);
      expect(task.isRunning, isTrue);
      expect(task.isDone, isFalse);
      expect(task.isWaitingForWifi, isFalse);
    });

    test('waitingForWifi counts as running (mutex held) but not done', () {
      final task = taskWith(BackupStatus.waitingForWifi);
      expect(task.isRunning, isTrue);
      expect(task.isDone, isFalse);
      expect(task.isWaitingForWifi, isTrue);
    });

    test('idle is neither running nor done', () {
      final task = taskWith(BackupStatus.idle);
      expect(task.isRunning, isFalse);
      expect(task.isDone, isFalse);
    });

    test('completed and stopped are done, not running', () {
      for (final status in [BackupStatus.completed, BackupStatus.stopped]) {
        final task = taskWith(status);
        expect(task.isRunning, isFalse, reason: '$status');
        expect(task.isDone, isTrue, reason: '$status');
      }
    });

    test('copyWith can transition to waitingForWifi and back', () {
      final running = taskWith(BackupStatus.running);
      final waiting = running.copyWith(status: BackupStatus.waitingForWifi);
      expect(waiting.isWaitingForWifi, isTrue);
      final resumed = waiting.copyWith(status: BackupStatus.running);
      expect(resumed.isRunning, isTrue);
      expect(resumed.isWaitingForWifi, isFalse);
    });
  });
}
