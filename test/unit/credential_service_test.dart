import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/services/crypto/credential_service.dart';
import 'package:enpix/services/crypto/crypto_service.dart';

class _FakeSecureStorage extends Mock implements FlutterSecureStorage {}

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
}
