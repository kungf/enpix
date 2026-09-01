import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/services/network/network_guard.dart';

/// Fake probe returning a scripted sequence of connectivity results.
class FakeProbe implements NetworkProbe {
  FakeProbe(List<Set<ConnectivityResult>> script) : _script = List.of(script);

  final List<Set<ConnectivityResult>> _script;
  int calls = 0;

  @override
  Future<Set<ConnectivityResult>> check() async {
    calls++;
    if (_script.isEmpty) return {ConnectivityResult.none};
    // Repeat the last scripted result once the script is exhausted.
    return _script.length > 1 ? _script.removeAt(0) : _script.first;
  }
}

void main() {
  group('NetworkGuard.isUploadAllowed', () {
    test('allows any network when wifiOnly is off', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.mobile},
        ]),
        wifiOnly: () => false,
      );
      expect(await guard.isUploadAllowed, isTrue);
    });

    test('allows no network when wifiOnly is off', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.none},
        ]),
        wifiOnly: () => false,
      );
      expect(await guard.isUploadAllowed, isTrue);
    });

    test('allows WiFi when wifiOnly is on', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.wifi},
        ]),
        wifiOnly: () => true,
      );
      expect(await guard.isUploadAllowed, isTrue);
    });

    test('allows Ethernet when wifiOnly is on (desktop)', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.ethernet},
        ]),
        wifiOnly: () => true,
      );
      expect(await guard.isUploadAllowed, isTrue);
    });

    test('blocks mobile-only when wifiOnly is on', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.mobile},
        ]),
        wifiOnly: () => true,
      );
      expect(await guard.isUploadAllowed, isFalse);
    });

    test('blocks no-network when wifiOnly is on', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.none},
        ]),
        wifiOnly: () => true,
      );
      expect(await guard.isUploadAllowed, isFalse);
    });

    test('allows when WiFi is present alongside mobile', () async {
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.mobile, ConnectivityResult.wifi},
        ]),
        wifiOnly: () => true,
      );
      expect(await guard.isUploadAllowed, isTrue);
    });

    test('reads the wifiOnly setting at check time, not construction time',
        () async {
      var wifiOnly = true;
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.mobile},
        ]),
        wifiOnly: () => wifiOnly,
      );
      expect(await guard.isUploadAllowed, isFalse);
      wifiOnly = false;
      expect(await guard.isUploadAllowed, isTrue);
    });
  });

  group('NetworkGuard.waitForUploadAllowed', () {
    test('returns true immediately when already allowed', () async {
      final probe = FakeProbe([
        {ConnectivityResult.wifi},
      ]);
      final guard = NetworkGuard(
        probe: probe,
        wifiOnly: () => true,
        pollInterval: Duration.zero,
      );
      final allowed = await guard.waitForUploadAllowed(
        isCancelled: () => false,
      );
      expect(allowed, isTrue);
      expect(probe.calls, 1);
    });

    test('polls until WiFi becomes available', () async {
      final probe = FakeProbe([
        {ConnectivityResult.mobile},
        {ConnectivityResult.mobile},
        {ConnectivityResult.wifi},
      ]);
      final guard = NetworkGuard(
        probe: probe,
        wifiOnly: () => true,
        pollInterval: Duration.zero,
      );
      final allowed = await guard.waitForUploadAllowed(
        isCancelled: () => false,
      );
      expect(allowed, isTrue);
      expect(probe.calls, 3);
    });

    test('returns false when cancelled while waiting', () async {
      var checks = 0;
      final guard = NetworkGuard(
        probe: FakeProbe([
          {ConnectivityResult.mobile},
        ]),
        wifiOnly: () => true,
        pollInterval: Duration.zero,
      );
      // Cancel after the third failed check.
      final allowed = await guard.waitForUploadAllowed(
        isCancelled: () => ++checks > 3,
      );
      expect(allowed, isFalse);
    });
  });
}
