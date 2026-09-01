import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';

/// Supplies the current set of active network types.
///
/// Abstracted from `connectivity_plus` so tests can script connectivity
/// changes without platform channels.
abstract interface class NetworkProbe {
  Future<Set<ConnectivityResult>> check();
}

/// Production probe backed by `connectivity_plus`.
class ConnectivityPlusProbe implements NetworkProbe {
  ConnectivityPlusProbe([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<Set<ConnectivityResult>> check() async {
    final results = await _connectivity.checkConnectivity();
    return results.toSet();
  }
}

/// Decides whether uploads may proceed on the current network.
///
/// When the user's `wifiOnly` setting is on, uploads are allowed only on
/// WiFi or Ethernet (desktop); mobile / VPN-only / offline all block.
/// The [wifiOnly] callback is invoked on every check so toggling the
/// setting mid-backup takes effect immediately.
class NetworkGuard {
  final Logger _log = Logger('NetworkGuard');
  final NetworkProbe _probe;
  final bool Function() _wifiOnly;

  /// How often to re-check connectivity while waiting for WiFi.
  /// Injectable (zero in tests).
  final Duration pollInterval;

  NetworkGuard({
    required NetworkProbe probe,
    required bool Function() wifiOnly,
    this.pollInterval = const Duration(seconds: 2),
  })  : _probe = probe,
        _wifiOnly = wifiOnly;

  Future<bool> get isUploadAllowed async {
    if (!_wifiOnly()) return true;
    try {
      final results = await _probe.check();
      // Known limitation: with an active VPN some platforms (notably iOS)
      // may report only ConnectivityResult.vpn even when traffic rides on
      // WiFi. We intentionally stay conservative (block) rather than risk
      // uploading over a cellular-backed VPN.
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } on Exception catch (e) {
      // Fail-open: a broken connectivity plugin must not stall backups.
      _log.warning('Connectivity check failed, allowing upload: $e');
      return true;
    }
  }

  /// Polls until uploads are allowed or [isCancelled] returns true.
  /// Returns true if the network became available, false if cancelled.
  Future<bool> waitForUploadAllowed({
    required bool Function() isCancelled,
  }) async {
    while (!isCancelled()) {
      if (await isUploadAllowed) return true;
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
}
