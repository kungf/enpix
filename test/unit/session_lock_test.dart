import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/services/crypto/credential_service.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/session/session_lock.dart';

class _FakeSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _FakeSecureStorage storage;
  late Map<String, String> backing;
  late CredentialService cred;

  /// Fake wall clock — advanced manually inside tests; never tied to
  /// fakeAsync's timer clock, mirroring real DateTime.now() behavior.
  var fakeNow = DateTime(2026, 1, 1, 10);
  var lockedCount = 0;
  var resumeAfterLockCount = 0;
  var busy = false;

  setUp(() {
    backing = {};
    storage = _FakeSecureStorage();
    when(() => storage.read(key: any(named: 'key'))).thenAnswer(
      (inv) async => backing[inv.namedArguments[#key] as String],
    );
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((inv) async {
      final key = inv.namedArguments[#key] as String;
      final value = inv.namedArguments[#value] as String?;
      if (value == null) {
        backing.remove(key);
      } else {
        backing[key] = value;
      }
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer(
      (inv) async => backing.remove(inv.namedArguments[#key] as String),
    );
    cred = CredentialService(CryptoService(), storage);
    // Restore-path activation: session holds a master key, no Argon2 cost.
    cred.restoreWithRecoveryKey(Uint8List(32));

    fakeNow = DateTime(2026, 1, 1, 10);
    lockedCount = 0;
    resumeAfterLockCount = 0;
    busy = false;
  });

  SessionLock buildLock() {
    return SessionLock(
      credentialService: cred,
      onSessionLocked: () => lockedCount++,
      onResumeAfterLock: () => resumeAfterLockCount++,
      lockDelay: const Duration(minutes: 5),
      isBusy: () => busy,
      now: () => fakeNow,
    );
  }

  group('SessionLock background timeout', () {
    test('locks via timer while still backgrounded (Android path)', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5));

        expect(cred.isSessionActive, isFalse);
        expect(lockedCount, 1);
        // Still in the background — resume callbacks must not fire.
        expect(resumeAfterLockCount, 0);
      });
    });

    test('does not lock before the delay elapses', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(
          const Duration(minutes: 5) - const Duration(milliseconds: 1),
        );

        expect(cred.isSessionActive, isTrue);
        expect(lockedCount, 0);
      });
    });

    test('locks on resume when the process was suspended (iOS path)', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        // No elapse: simulates iOS suspending the process — the Dart timer
        // never fires. Only the wall clock moves.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(cred.isSessionActive, isFalse);
        expect(lockedCount, 1);
        expect(resumeAfterLockCount, 1);
      });
    });

    test('a short background trip keeps the session', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(seconds: 30));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
        // The cancelled timer must never fire later.
        async.elapse(const Duration(hours: 1));

        expect(cred.isSessionActive, isTrue);
        expect(lockedCount, 0);
        expect(resumeAfterLockCount, 0);
      });
    });

    test('defers the lock while a backup is running (timer path)', () {
      fakeAsync((async) {
        busy = true;
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5));
        // Busy — the timer re-arms instead of locking.
        expect(cred.isSessionActive, isTrue);
        expect(lockedCount, 0);

        busy = false;
        async.elapse(const Duration(minutes: 5));

        expect(cred.isSessionActive, isFalse);
        expect(lockedCount, 1);
      });
    });

    test('keeps the session on resume when a backup survived the window', () {
      fakeAsync((async) {
        busy = true;
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(cred.isSessionActive, isTrue);
        expect(lockedCount, 0);
        expect(resumeAfterLockCount, 0);
      });
    });

    test('prompts re-unlock when the timer locked while backgrounded', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5)); // timer locks in background
        fakeNow = fakeNow.add(const Duration(minutes: 7));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(lockedCount, 1); // no double lock
        expect(resumeAfterLockCount, 1);
      });
    });

    test('no-op without an active session', () {
      fakeAsync((async) {
        cred.endSession();
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(minutes: 5));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(lockedCount, 0);
        expect(resumeAfterLockCount, 0);
      });
    });

    test('reset cancels a pending lock', () {
      fakeAsync((async) {
        final lock = buildLock();

        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        lock.reset();
        async.elapse(const Duration(hours: 1));

        expect(cred.isSessionActive, isTrue);
        expect(lockedCount, 0);
      });
    });

    test('each background trip gets a fresh window', () {
      fakeAsync((async) {
        final lock = buildLock();

        // 4-minute trip — under the limit.
        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 4));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(cred.isSessionActive, isTrue);

        // A second 4-minute trip must also survive — the window restarts
        // per trip; trips do not accumulate.
        lock.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 4));
        lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(minutes: 5));

        expect(cred.isSessionActive, isTrue);
      });
    });
  });
}
