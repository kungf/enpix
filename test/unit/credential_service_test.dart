import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/services/biometric/biometric_service.dart';
import 'package:enpix/services/crypto/credential_service.dart';
import 'package:enpix/services/crypto/crypto_service.dart';

class _FakeSecureStorage extends Mock implements FlutterSecureStorage {}

/// Scriptable biometric gate for auto-unlock tests.
class _FakeBiometric implements BiometricAuth {
  _FakeBiometric({this.available = true, this.authResult = true});

  bool available;
  bool authResult;
  int authCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    authCalls++;
    return authResult;
  }
}

/// Backs the mock with a real map so reads return what was written,
/// mimicking actual Keychain behavior across calls.
void main() {
  late _FakeSecureStorage storage;
  late Map<String, String> backing;
  late CredentialService cred;

  const slow = Timeout(Duration(minutes: 2));

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
  });

  group('auto-unlock after setup', () {
    test(
      'setupPassphrase persists passphrase so autoUnlock restores session',
      () async {
        // Opted-in user — auto-unlock flag set before setup.
        backing['auto_unlock_enabled'] = 'true';
        await cred.setupPassphrase('correct horse battery staple');
        cred.endSession();
        expect(cred.isSessionActive, isFalse);

        final unlocked = await cred.autoUnlock();

        expect(unlocked, isTrue);
        expect(cred.isSessionActive, isTrue);
      },
      timeout: slow,
    );

    test(
      'session is fully active (with master key) right after setupPassphrase',
      () async {
        await cred.setupPassphrase('correct horse battery staple');

        expect(cred.isSessionActive, isTrue);
        expect(cred.sessionMasterKey, isNotNull);
      },
      timeout: slow,
    );
  });

  group('stable S3 path prefix', () {
    test(
      'path prefix stays the same across passphrase changes',
      () async {
        await cred.setupPassphrase('old password 123');
        final before = await cred.getPathPrefix();

        await cred.changePassphrase('old password 123', 'new password 456');
        final after = await cred.getPathPrefix();

        expect(before, isNot(equals('shared')));
        expect(after, equals(before));
      },
      timeout: slow,
    );

    test(
      'path prefix stays the same across recovery + resetPassphrase',
      () async {
        await cred.setupPassphrase('forgotten password 1');
        final before = await cred.getPathPrefix();
        await cred.unlockWithPassphrase('forgotten password 1');
        final mk = Uint8List.fromList(cred.sessionMasterKey!);
        cred.endSession();

        cred.restoreWithRecoveryKey(Uint8List.fromList(mk));
        await cred.resetPassphrase('brand new password 2');

        expect(await cred.getPathPrefix(), equals(before));
      },
      timeout: slow,
    );
  });

  group('resetPassphrase (recovery flow)', () {
    test(
      'preserves master key; new password unlocks, old one is rejected',
      () async {
        await cred.setupPassphrase('forgotten password 1');
        await cred.unlockWithPassphrase('forgotten password 1');
        final mk = Uint8List.fromList(cred.sessionMasterKey!);
        cred.endSession();

        // Simulate recovery-key restore, then reset the password.
        cred.restoreWithRecoveryKey(Uint8List.fromList(mk));
        await cred.resetPassphrase('brand new password 2');

        expect(cred.isSessionActive, isTrue);
        expect(cred.sessionMasterKey, equals(mk));

        cred.endSession();
        await expectLater(
          cred.unlockWithPassphrase('forgotten password 1'),
          throwsA(isA<WrongPassphraseException>()),
        );
        await cred.unlockWithPassphrase('brand new password 2');
        expect(cred.sessionMasterKey, equals(mk));
      },
      timeout: slow,
    );

    test(
      'autoUnlock works after resetPassphrase',
      () async {
        // Opted-in user — auto-unlock flag set before setup.
        backing['auto_unlock_enabled'] = 'true';
        await cred.setupPassphrase('forgotten password 1');
        await cred.unlockWithPassphrase('forgotten password 1');
        final mk = Uint8List.fromList(cred.sessionMasterKey!);
        cred.endSession();

        cred.restoreWithRecoveryKey(Uint8List.fromList(mk));
        await cred.resetPassphrase('brand new password 2');
        cred.endSession();

        expect(await cred.autoUnlock(), isTrue);
        expect(cred.sessionMasterKey, equals(mk));
      },
      timeout: slow,
    );

    test(
      'throws without an active master-key session',
      () async {
        expect(
          () => cred.resetPassphrase('whatever pass 1'),
          throwsStateError,
        );
      },
    );
  });

  group('changePassphrase session lifecycle', () {
    test(
      'keeps session active and saves new passphrase for auto-unlock',
      () async {
        // Opted-in user — auto-unlock flag set before setup.
        backing['auto_unlock_enabled'] = 'true';
        await cred.setupPassphrase('old password 123');
        await cred.unlockWithPassphrase('old password 123');
        final mk = Uint8List.fromList(cred.sessionMasterKey!);

        await cred.changePassphrase('old password 123', 'new password 456');

        expect(cred.isSessionActive, isTrue);
        expect(cred.sessionMasterKey, equals(mk));

        cred.endSession();
        expect(await cred.autoUnlock(), isTrue);
        expect(cred.sessionMasterKey, equals(mk));
      },
      timeout: slow,
    );
  });

  group('auto-unlock opt-in (default off)', () {
    test(
      'fresh setup persists no unlock material; autoUnlock returns false',
      () async {
        await cred.setupPassphrase('correct horse battery staple');
        cred.endSession();

        expect(await cred.isAutoUnlockEnabled(), isFalse);
        expect(backing.containsKey('saved_passphrase'), isFalse);
        expect(backing.containsKey('wrapped_kek_v1'), isFalse);

        expect(await cred.autoUnlock(), isFalse);
        expect(cred.isSessionActive, isFalse);
      },
      timeout: slow,
    );

    test(
      'manual unlock works without persisting material',
      () async {
        await cred.setupPassphrase('correct horse battery staple');
        cred.endSession();

        await cred.unlockWithPassphrase('correct horse battery staple');
        expect(cred.isSessionActive, isTrue);
        expect(backing.containsKey('saved_passphrase'), isFalse);
        expect(backing.containsKey('wrapped_kek_v1'), isFalse);
      },
      timeout: slow,
    );

    test(
      'changePassphrase with flag off does not persist new passphrase',
      () async {
        await cred.setupPassphrase('old password 123');
        await cred.changePassphrase('old password 123', 'new password 456');

        expect(backing.containsKey('saved_passphrase'), isFalse);

        cred.endSession();
        await cred.unlockWithPassphrase('new password 456');
        expect(cred.isSessionActive, isTrue);
      },
      timeout: slow,
    );
  });

  group('auto-unlock migration (legacy users)', () {
    test(
      'legacy saved_passphrase without flag is treated as enabled',
      () async {
        await cred.setupPassphrase('correct horse battery staple');
        cred.endSession();
        // Simulate a pre-toggle Keychain: material present, flag absent.
        backing['saved_passphrase'] = 'correct horse battery staple';

        expect(await cred.isAutoUnlockEnabled(), isTrue);
        expect(await cred.autoUnlock(), isTrue);
        expect(cred.isSessionActive, isTrue);
      },
      timeout: slow,
    );
  });

  group('enableAutoUnlock / disableAutoUnlock', () {
    test(
      'enable from active session persists KEK + flag; fast path restores',
      () async {
        await cred.setupPassphrase('correct horse battery staple');
        await cred.enableAutoUnlock();
        cred.endSession();

        expect(await cred.isAutoUnlockEnabled(), isTrue);
        expect(backing.containsKey('wrapped_kek_v1'), isTrue);
        expect(await cred.autoUnlock(), isTrue);
        expect(cred.isSessionActive, isTrue);
      },
      timeout: slow,
    );

    test('enable without an active session throws StateError', () async {
      await expectLater(cred.enableAutoUnlock(), throwsA(isA<StateError>()));
    });

    test(
      'disable clears materials; manual unlock still works',
      () async {
        await cred.setupPassphrase('correct horse battery staple');
        await cred.enableAutoUnlock();
        await cred.disableAutoUnlock();

        expect(await cred.isAutoUnlockEnabled(), isFalse);
        expect(backing.containsKey('saved_passphrase'), isFalse);
        expect(backing.containsKey('wrapped_kek_v1'), isFalse);

        cred.endSession();
        expect(await cred.autoUnlock(), isFalse);
        await cred.unlockWithPassphrase('correct horse battery staple');
        expect(cred.isSessionActive, isTrue);
      },
      timeout: slow,
    );
  });

  group('biometric gate on autoUnlock', () {
    test(
      'gate blocks auto-unlock when authentication fails',
      () async {
        final bio = _FakeBiometric(authResult: false);
        final gated =
            CredentialService(CryptoService(), storage, biometric: bio);
        await gated.setupPassphrase('correct horse battery staple');
        await gated.enableAutoUnlock();
        gated.endSession();

        expect(await gated.autoUnlock(), isFalse);
        expect(gated.isSessionActive, isFalse);
        expect(bio.authCalls, 1);
        // Materials untouched — a retry after successful biometrics works.
        expect(backing.containsKey('wrapped_kek_v1'), isTrue);
      },
      timeout: slow,
    );

    test(
      'gate passes when authentication succeeds',
      () async {
        final bio = _FakeBiometric();
        final gated =
            CredentialService(CryptoService(), storage, biometric: bio);
        await gated.setupPassphrase('correct horse battery staple');
        await gated.enableAutoUnlock();
        gated.endSession();

        expect(await gated.autoUnlock(), isTrue);
        expect(gated.isSessionActive, isTrue);
        expect(bio.authCalls, 1);
      },
      timeout: slow,
    );

    test(
      'gate skipped when biometrics unavailable',
      () async {
        final bio = _FakeBiometric(available: false);
        final gated =
            CredentialService(CryptoService(), storage, biometric: bio);
        await gated.setupPassphrase('correct horse battery staple');
        await gated.enableAutoUnlock();
        gated.endSession();

        expect(await gated.autoUnlock(), isTrue);
        expect(bio.authCalls, 0);
      },
      timeout: slow,
    );
  });
}
