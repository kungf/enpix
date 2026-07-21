import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/crypto/recovery_service.dart';

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('Recovery Key Mnemonic', () {
    test('generateRecoveryKey produces 32 bytes', () {
      final key = crypto.generateRecoveryKey();
      expect(key.length, equals(32));
    });

    test('two generated keys are different', () {
      final key1 = crypto.generateRecoveryKey();
      final key2 = crypto.generateRecoveryKey();
      expect(key1, isNot(equals(key2)));
    });
  });

  group('Master Key wrapping with Recovery Key', () {
    test('wrap then unwrap returns original master key', () async {
      final masterKey = crypto.generateMasterKey();
      final recoveryKey = crypto.generateRecoveryKey();

      // Wrap master key with recovery key
      final wrapped = await crypto.wrapKey(masterKey, recoveryKey);

      // Unwrap
      final unwrapped = await crypto.unwrapKey(wrapped, recoveryKey);

      expect(unwrapped, equals(masterKey));
    });

    test('unwrap with wrong recovery key fails', () async {
      final masterKey = crypto.generateMasterKey();
      final recoveryKey = crypto.generateRecoveryKey();
      final wrongKey = crypto.generateRecoveryKey();

      final wrapped = await crypto.wrapKey(masterKey, recoveryKey);

      expect(
        () => crypto.unwrapKey(wrapped, wrongKey),
        throwsA(anything),
      );
    });

    test('master key is 32 bytes', () {
      final mk = crypto.generateMasterKey();
      expect(mk.length, equals(32));
    });
  });

  group('Secure operations', () {
    test('secureFree zeros the buffer', () {
      final key = crypto.generateRecoveryKey();
      expect(key.any((b) => b != 0), isTrue);

      crypto.secureFree(key);
      expect(key.every((b) => b == 0), isTrue);
    });

    test('secureCompare detects equal keys', () {
      final key1 = Uint8List.fromList([1, 2, 3, 4]);
      final key2 = Uint8List.fromList([1, 2, 3, 4]);
      expect(crypto.secureCompare(key1, key2), isTrue);
    });

    test('secureCompare detects different keys', () {
      final key1 = Uint8List.fromList([1, 2, 3, 4]);
      final key2 = Uint8List.fromList([1, 2, 3, 5]);
      expect(crypto.secureCompare(key1, key2), isFalse);
    });
  });

  group('Adaptive Argon2id', () {
    test('probeArgon2Params returns valid params', () async {
      final salt = crypto.generateSalt();
      final params = await crypto.probeArgon2Params('test-password', salt);

      expect(params.memory, greaterThanOrEqualTo(65536)); // >= 64 MiB
      expect(params.ops, greaterThanOrEqualTo(3));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('deriveKekWithParams produces 32 bytes', () async {
      final salt = crypto.generateSalt();
      final kek = await crypto.deriveKekWithParams(
        'test-password',
        salt,
        memory: 65536,
        iterations: 3,
      );

      expect(kek.length, equals(32));
    });

    test(
        'deriveKek and deriveKekWithParams with same params produce same result',
        () async {
      final salt = crypto.generateSalt();
      final passphrase = 'same-password';

      final kek1 = await crypto.deriveKek(passphrase, salt);
      final kek2 = await crypto.deriveKekWithParams(
        passphrase,
        salt,
        memory: 65536,
        iterations: 3,
      );

      expect(kek1, equals(kek2));
    });
  });

  group('Full recovery flow (without S3)', () {
    test('end-to-end: generate → wrap → unwrap → verify', () async {
      // 1. Generate master key and recovery key
      final masterKey = crypto.generateMasterKey();
      final recoveryKey = crypto.generateRecoveryKey();

      // 2. Wrap master key with recovery key (simulates S3 upload)
      final wrappedMk = await crypto.wrapKey(masterKey, recoveryKey);

      // 3. Unwrap (simulates recovery)
      final recoveredKey = await crypto.unwrapKey(wrappedMk, recoveryKey);

      // 4. Verify
      expect(recoveredKey, equals(masterKey));
    });

    test('end-to-end: KEK wraps MK, RK wraps MK, both can unwrap', () async {
      // Simulates the real architecture: MK wrapped by both KEK and RK
      final masterKey = crypto.generateMasterKey();
      final kek = Uint8List.fromList(List.generate(32, (i) => i));
      final recoveryKey = crypto.generateRecoveryKey();

      // Wrap with KEK (stored in Keychain)
      final wrappedWithKek = await crypto.wrapKey(masterKey, kek);
      // Wrap with RK (stored in S3)
      final wrappedWithRk = await crypto.wrapKey(masterKey, recoveryKey);

      // Normal unlock: unwrap with KEK
      final fromKek = await crypto.unwrapKey(wrappedWithKek, kek);
      expect(fromKek, equals(masterKey));

      // Recovery: unwrap with RK
      final fromRk = await crypto.unwrapKey(wrappedWithRk, recoveryKey);
      expect(fromRk, equals(masterKey));

      // Both produce the same master key
      expect(fromKek, equals(fromRk));
    });
  });
}
