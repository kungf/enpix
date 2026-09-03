import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import '../crypto/credential_service.dart';

/// How long the app may stay in the background before the in-memory
/// KEK + Master Key session is cleared.
const Duration kSessionLockDelay = Duration(minutes: 5);

/// Clears the in-memory key session once the app has been backgrounded
/// for [lockDelay].
///
/// Two paths, because the OSes treat background processes differently:
/// - **Android** keeps the process (and Dart timers) running for a while →
///   a [Timer] locks at exactly [lockDelay] while still in the background.
/// - **iOS** suspends the process within seconds → the timer is frozen, so
///   the decision happens on resume by comparing wall-clock time against
///   the paused timestamp.
///
/// While [isBusy] reports an in-flight backup the lock is deferred: the
/// per-file upload reads `sessionMasterKey`, so clearing mid-run would
/// fail every remaining file.
class SessionLock with WidgetsBindingObserver {
  SessionLock({
    required CredentialService credentialService,
    required this.onSessionLocked,
    this.onResumeAfterLock,
    this.lockDelay = kSessionLockDelay,
    this.isBusy = _neverBusy,
    DateTime Function() now = DateTime.now,
  })  : _cred = credentialService,
        _now = now;

  static bool _neverBusy() => false;

  static final _log = Logger('SessionLock');

  final CredentialService _cred;
  final DateTime Function() _now;

  /// Fires whenever the session keys are actually cleared (either path).
  final VoidCallback onSessionLocked;

  /// Fires once when the app comes back and the keys were cleared during
  /// that background window — the right moment to prompt a re-unlock
  /// (e.g. the biometric gate), now that the app is foregrounded again.
  final VoidCallback? onResumeAfterLock;

  /// How long the app may stay backgrounded before the session is cleared.
  final Duration lockDelay;

  /// Reports whether long-running key-dependent work (a backup) is in
  /// flight; while true the lock is deferred.
  final bool Function() isBusy;

  Timer? _timer;
  DateTime? _backgroundedAt;
  bool _lockedWhileBackgrounded = false;

  /// Registers with [WidgetsBinding] — call from StatefulWidget.initState.
  void attach(WidgetsBinding binding) => binding.addObserver(this);

  /// Unregisters and cancels any pending lock — call from dispose().
  void detach(WidgetsBinding binding) {
    binding.removeObserver(this);
    reset();
  }

  /// Cancels a pending lock and forgets the current background window.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _backgroundedAt = null;
    _lockedWhileBackgrounded = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _onPaused();
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Transient (notification shade, system dialogs) or terminal —
        // only a full background trip counts toward the timeout.
        break;
    }
  }

  void _onPaused() {
    if (!_cred.isSessionActive) return; // nothing in memory to protect
    _backgroundedAt = _now();
    _lockedWhileBackgrounded = false;
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(lockDelay, _onTimerFired);
  }

  /// Timer path — the process stayed alive in the background (Android).
  void _onTimerFired() {
    _timer = null;
    if (!_cred.isSessionActive) return;
    if (isBusy()) {
      _log.info('Backup in flight — deferring session lock');
      _armTimer(); // re-check after another full window
      return;
    }
    _lockedWhileBackgrounded = true;
    _cred.endSession();
    _log.info('Session locked after $lockDelay in background (timer)');
    onSessionLocked();
  }

  /// Resume path — the process may have been suspended with its timers
  /// frozen (iOS), so decide by wall-clock elapsed time instead.
  void _onResumed() {
    _timer?.cancel();
    _timer = null;

    final at = _backgroundedAt;
    final lockedWhileBackgrounded = _lockedWhileBackgrounded;
    _backgroundedAt = null;
    _lockedWhileBackgrounded = false;
    if (at == null) return; // no tracked window

    var lockedNow = false;
    if (!lockedWhileBackgrounded &&
        _now().difference(at) >= lockDelay &&
        !isBusy() &&
        _cred.isSessionActive) {
      _cred.endSession();
      _log.info('Session locked — backgrounded beyond $lockDelay');
      onSessionLocked();
      lockedNow = true;
    }
    if (lockedWhileBackgrounded || lockedNow) {
      onResumeAfterLock?.call();
    }
  }
}
