import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/services/background/backup_keepalive.dart';
import 'package:enpix/services/upload/backup_task.dart';

class _FakeKeepalivePlatform implements KeepalivePlatform {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

BackupTask _task(BackupStatus status) =>
    BackupTask(status: status, startedAt: DateTime(2026, 1, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeKeepalivePlatform platform;
  var stopBackupCalls = 0;

  setUp(() {
    platform = _FakeKeepalivePlatform();
    stopBackupCalls = 0;
  });

  BackupKeepalive buildKeepalive({Duration? graceTimeout}) {
    return BackupKeepalive(
      platform: platform,
      onStopBackup: () => stopBackupCalls++,
      graceTimeout: graceTimeout,
    );
  }

  group('BackupKeepalive state mapping', () {
    test('starts the keepalive when a backup begins', () {
      final keepalive = buildKeepalive();

      keepalive.onTaskChanged(_task(BackupStatus.running));

      expect(platform.startCalls, 1);
      expect(platform.stopCalls, 0);
    });

    test('ignores progress updates while running', () {
      final keepalive = buildKeepalive();
      keepalive.onTaskChanged(_task(BackupStatus.running));

      keepalive.onTaskChanged(
        _task(BackupStatus.running).copyWith(completedCount: 1),
      );
      keepalive.onTaskChanged(
        _task(BackupStatus.running).copyWith(completedCount: 2),
      );

      expect(platform.startCalls, 1);
      expect(platform.stopCalls, 0);
    });

    test('stops the keepalive when the backup completes', () {
      final keepalive = buildKeepalive();
      keepalive.onTaskChanged(_task(BackupStatus.running));

      keepalive.onTaskChanged(_task(BackupStatus.completed));

      expect(platform.stopCalls, 1);
    });

    test('stops the keepalive when the backup is stopped', () {
      final keepalive = buildKeepalive();
      keepalive.onTaskChanged(_task(BackupStatus.running));

      keepalive.onTaskChanged(_task(BackupStatus.stopped));

      expect(platform.stopCalls, 1);
    });

    test('stays active while waiting for WiFi', () {
      final keepalive = buildKeepalive();
      keepalive.onTaskChanged(_task(BackupStatus.running));

      keepalive.onTaskChanged(_task(BackupStatus.waitingForWifi));
      expect(platform.stopCalls, 0);

      // WiFi returns — still the same keepalive session, no restart.
      keepalive.onTaskChanged(_task(BackupStatus.running));
      expect(platform.startCalls, 1);
    });

    test('starts again for a second backup', () {
      final keepalive = buildKeepalive();
      keepalive.onTaskChanged(_task(BackupStatus.running));
      keepalive.onTaskChanged(_task(BackupStatus.completed));

      keepalive.onTaskChanged(_task(BackupStatus.running));

      expect(platform.startCalls, 2);
      expect(platform.stopCalls, 1);
    });
  });

  group('BackupKeepalive iOS background grace', () {
    test('stops the backup when the grace period expires in background', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));
        keepalive.onTaskChanged(_task(BackupStatus.running));
        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);

        async.elapse(const Duration(seconds: 24));
        expect(stopBackupCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(stopBackupCalls, 1);
        // Grace expiry releases the platform keepalive itself — idempotent
        // with the stop that arrives via the task-change listener.
        expect(platform.stopCalls, 1);
      });
    });

    test('cancels the grace timer when the app resumes', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));
        keepalive.onTaskChanged(_task(BackupStatus.running));
        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);

        keepalive.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(minutes: 10));

        expect(stopBackupCalls, 0);
      });
    });

    test('no grace stop when the backup finished before expiry', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));
        keepalive.onTaskChanged(_task(BackupStatus.running));
        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);

        keepalive.onTaskChanged(_task(BackupStatus.completed));
        async.elapse(const Duration(seconds: 25));

        expect(stopBackupCalls, 0);
        expect(platform.stopCalls, 1);
      });
    });

    test('does not arm the grace timer without an active backup', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));

        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 1));

        expect(stopBackupCalls, 0);
      });
    });

    test('no grace stop without a grace timeout (Android path)', () {
      fakeAsync((async) {
        final keepalive = buildKeepalive(); // graceTimeout: null
        keepalive.onTaskChanged(_task(BackupStatus.running));

        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 10));

        expect(stopBackupCalls, 0);
        expect(platform.startCalls, 1);
      });
    });

    test('re-arms the grace timer on a second background trip', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));
        keepalive.onTaskChanged(_task(BackupStatus.running));

        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);
        keepalive.didChangeAppLifecycleState(AppLifecycleState.resumed);
        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);

        async.elapse(const Duration(seconds: 24));
        expect(stopBackupCalls, 0);
        async.elapse(const Duration(seconds: 1));
        expect(stopBackupCalls, 1);
      });
    });

    test('detach cancels a pending grace timer', () {
      fakeAsync((async) {
        final keepalive =
            buildKeepalive(graceTimeout: const Duration(seconds: 25));
        keepalive.onTaskChanged(_task(BackupStatus.running));
        keepalive.didChangeAppLifecycleState(AppLifecycleState.paused);

        keepalive.detach(TestWidgetsFlutterBinding.instance);
        async.elapse(const Duration(minutes: 1));

        expect(stopBackupCalls, 0);
      });
    });
  });

  group('MethodChannelKeepalive', () {
    const channel = MethodChannel('enpix/keepalive');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('forwards start to the keepalive channel on mobile', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await MethodChannelKeepalive().start();

      expect(calls.map((c) => c.method), ['start']);
    });

    test('is a no-op on non-mobile platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await MethodChannelKeepalive().start();
      await MethodChannelKeepalive().stop();

      expect(calls, isEmpty);
    });

    test('swallows channel errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });

      // Must complete without throwing — keepalive failure degrades the
      // backup to foreground-only rather than crashing it.
      await MethodChannelKeepalive().start();
      await MethodChannelKeepalive().stop();
    });
  });
}
