import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import '../upload/backup_task.dart';

/// iOS grants roughly 30 s of execution after the app is backgrounded.
/// Stop the backup just before the budget expires so it ends cleanly;
/// interrupted files re-upload on the next run (the tracker only records
/// successful uploads).
const Duration kIOSBackgroundGrace = Duration(seconds: 25);

/// Platform boundary for keeping the process alive while a backup runs.
abstract interface class KeepalivePlatform {
  /// Begins keeping the process alive.
  Future<void> start();

  /// Releases the keep-alive.
  Future<void> stop();
}

/// [KeepalivePlatform] over method channel `enpix/keepalive`.
///
/// - **Android**: starts/stops a foreground service whose only job is
///   keeping the process alive — the main isolate keeps running the
///   existing backup with the session keys still in memory.
/// - **iOS**: begins/ends a background task. While the app is foregrounded
///   the task is inert; after backgrounding the system grants ~30 s of
///   execution before suspending the process.
///
/// No-op on desktop/web. Channel failures are logged and swallowed — a
/// failed keep-alive only degrades the backup to foreground-only.
class MethodChannelKeepalive implements KeepalivePlatform {
  MethodChannelKeepalive({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('enpix/keepalive');

  static final _log = Logger('MethodChannelKeepalive');

  final MethodChannel _channel;

  @override
  Future<void> start() => _invoke('start');

  @override
  Future<void> stop() => _invoke('stop');

  Future<void> _invoke(String method) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return; // Desktop/web — nothing to keep alive.
    }
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      _log.warning('Keepalive $method failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      _log.warning('Keepalive $method not implemented natively');
    }
  }
}

/// Keeps the process alive while a backup runs so the backup survives
/// backgrounding.
///
/// The E2E session keys live only in this isolate's memory, so the backup
/// must keep running in THIS process — a fresh background isolate could
/// not decrypt anything. Two OS strategies:
///
/// - **Android**: the keep-alive is a foreground service, so the process
///   (and the backup) runs indefinitely in the background.
/// - **iOS**: there is no long-running background execution. The platform
///   holds a background task granting ~30 s; when the app is backgrounded
///   mid-backup, a grace timer ([graceTimeout]) stops the backup just
///   before the budget expires so it ends cleanly instead of being frozen
///   mid-upload.
///
/// The keep-alive stays active while the backup waits for WiFi: on Android
/// a foreground service cannot be restarted from the background (12+), and
/// on iOS the grace timer handles the suspend. Pass [graceTimeout] only on
/// iOS; null disables the timer (Android path).
class BackupKeepalive with WidgetsBindingObserver {
  BackupKeepalive({
    required KeepalivePlatform platform,
    required this.onStopBackup,
    this.graceTimeout,
  }) : _platform = platform;

  static final _log = Logger('BackupKeepalive');

  final KeepalivePlatform _platform;

  /// Stops the running backup cleanly — wired to `BackupManager.stop()`.
  final VoidCallback onStopBackup;

  /// iOS background budget countdown; null disables the grace timer.
  final Duration? graceTimeout;

  Timer? _graceTimer;
  bool _active = false;

  /// Registers with [WidgetsBinding] — call from StatefulWidget.initState.
  void attach(WidgetsBinding binding) => binding.addObserver(this);

  /// Unregisters and cancels any pending grace timer — call from dispose().
  void detach(WidgetsBinding binding) {
    binding.removeObserver(this);
    _cancelGraceTimer();
  }

  /// Feed every [BackupTask] change here (e.g. via `ref.listenManual`).
  void onTaskChanged(BackupTask task) {
    final active = task.isRunning; // running or waiting for WiFi
    if (active == _active) return;
    _active = active;
    if (active) {
      // Never carry a pending kill timer into a fresh backup.
      _cancelGraceTimer();
      unawaited(_platform.start());
    } else {
      _cancelGraceTimer();
      unawaited(_platform.stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // iOS: the ~30 s background budget starts now — count down to a
        // clean stop before it expires. Android (null timeout) keeps the
        // foreground service alive instead.
        if (_active && graceTimeout != null) {
          _cancelGraceTimer();
          _graceTimer = Timer(graceTimeout!, _onGraceExpired);
        }
      case AppLifecycleState.resumed:
        _cancelGraceTimer(); // back in the foreground — no budget pressure
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break; // transient or terminal — no action
    }
  }

  /// Grace timer fired — the background budget is nearly spent. Stop the
  /// backup cleanly; interrupted files re-upload on the next run.
  ///
  /// Known edge: if the system suspends the process before this fires
  /// (budget ended early), the overdue timer fires on resume and stops the
  /// backup instead of letting it continue in the foreground. Accepted —
  /// restarting is one tap and the tracker skips completed files.
  void _onGraceExpired() {
    _graceTimer = null;
    if (!_active) return;
    _active = false;
    _log.info('Background grace expired — stopping backup cleanly');
    onStopBackup();
    // Release the keepalive here too — the stop that arrives via the
    // task-change listener becomes a no-op (same state).
    unawaited(_platform.stop());
  }

  void _cancelGraceTimer() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}
