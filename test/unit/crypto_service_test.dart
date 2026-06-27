import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:see_photo/services/crypto/crypto_service.dart';

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('Key Derivation (Argon2id)', () {
    test('derives same KEK from same passphrase and salt', () async {
      final salt = crypto.generateSalt();
      final passphrase = 'test-password-123';

      final kek1 = await crypto.deriveKek(passphrase, salt);
      final kek2 = await crypto.deriveKek(passphrase, salt);

      expect(kek1, equals(kek2));
      expect(kek1.length, equals(32)); // 256-bit
    });

    test('different passphrases produce different KEKs', () async {
      final salt = crypto.generateSalt();
      final kek1 = await crypto.deriveKek('password1', salt);
      final kek2 = await crypto.deriveKek('password2', salt);

      expect(kek1, isNot(equals(kek2)));
    });

    test('different salts produce different KEKs', () async {
      final passphrase = 'same-password';
      final salt1 = crypto.generateSalt();
      final salt2 = crypto.generateSalt();

      final kek1 = await crypto.deriveKek(passphrase, salt1);
      final kek2 = await crypto.deriveKek(passphrase, salt2);

      expect(kek1, isNot(equals(kek2)));
    });

    test('fingerprint can verify correct KEK', () async {
      final salt = crypto.generateSalt();
      final kek = await crypto.deriveKek('my-password', salt);
      final fp = await crypto.computeFingerprint(kek);

      // Same password → same fingerprint
      final kek2 = await crypto.deriveKek('my-password', salt);
      final fp2 = await crypto.computeFingerprint(kek2);

      expect(fp, equals(fp2));
    });
  });

  group('Encryption/Decryption (XChaCha20-Poly1305)', () {
    test('encrypt then decrypt returns original data', () async {
      final dek = crypto.generateDek();
      final nonce = crypto.generateNonce();
      final plaintext = Uint8List.fromList(utf8.encode('Hello, See-Photo! 这是一段测试数据。'));

      final encrypted = await crypto.encrypt(plaintext, dek, nonce);
      final decrypted = await crypto.decrypt(encrypted, dek);

      expect(decrypted, equals(plaintext));
    });

    test('encrypted data includes nonce + ciphertext + MAC', () async {
      final dek = crypto.generateDek();
      final nonce = crypto.generateNonce();
      final plaintext = Uint8List(100);

      final encrypted = await crypto.encrypt(plaintext, dek, nonce);

      // nonce(24) + ciphertext(100) + MAC(16)
      expect(encrypted.length, equals(24 + 100 + 16));
    });

    test('decrypt with wrong key fails', () async {
      final dek = crypto.generateDek();
      final wrongDek = crypto.generateDek();
      final nonce = crypto.generateNonce();
      final plaintext = Uint8List.fromList(utf8.encode('secret'));

      final encrypted = await crypto.encrypt(plaintext, dek, nonce);

      expect(
        () async => await crypto.decrypt(encrypted, wrongDek),
        throwsA(isA<Exception>()),
      );
    });

    test('encrypt large data (10MB)', () async {
      final dek = crypto.generateDek();
      final nonce = crypto.generateNonce();
      final plaintext = Uint8List(10 * 1024 * 1024); // 10 MB

      final sw = Stopwatch()..start();
      final encrypted = await crypto.encrypt(plaintext, dek, nonce);
      final elapsedEncrypt = sw.elapsedMilliseconds;

      sw.reset();
      final decrypted = await crypto.decrypt(encrypted, dek);
      final elapsedDecrypt = sw.elapsedMilliseconds;

      expect(decrypted, equals(plaintext));
      // Should be reasonably fast
      expect(elapsedEncrypt, lessThan(5000));
      expect(elapsedDecrypt, lessThan(5000));
      print('10MB encrypt: ${elapsedEncrypt}ms, decrypt: ${elapsedDecrypt}ms');
    });
  });

  group('Key Wrapping', () {
    test('wrap then unwrap returns original key', () async {
      final kek = crypto.generateDek();
      final dek = crypto.generateDek();

      final wrapped = await crypto.wrapKey(dek, kek);
      final unwrapped = await crypto.unwrapKey(wrapped, kek);

      expect(unwrapped, equals(dek));
    });

    test('unwrap with wrong KEK fails', () async {
      final kek = crypto.generateDek();
      final wrongKek = crypto.generateDek();
      final dek = crypto.generateDek();

      final wrapped = await crypto.wrapKey(dek, kek);

      expect(
        () async => await crypto.unwrapKey(wrapped, wrongKek),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('BLAKE2b Hashing', () {
    test('same data produces same hash', () async {
      final data = Uint8List.fromList(utf8.encode('hello world'));
      final h1 = await crypto.hash(data);
      final h2 = await crypto.hash(data);

      expect(h1, equals(h2));
      expect(h1.length, equals(32)); // 256-bit
    });

    test('different data produces different hash', () async {
      final h1 = await crypto.hash(Uint8List.fromList(utf8.encode('hello')));
      final h2 = await crypto.hash(Uint8List.fromList(utf8.encode('world')));

      expect(h1, isNot(equals(h2)));
    });
  });

  group('Security properties', () {
    test('secureFree zeros the buffer', () {
      final buffer = Uint8List.fromList(List.generate(32, (_) => 0xFF));
      crypto.secureFree(buffer);
      for (final b in buffer) {
        expect(b, equals(0));
      }
    });

    test('secureCompare detects differences', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      final c = Uint8List.fromList([1, 2, 3, 5]);

      expect(crypto.secureCompare(a, b), isTrue);
      expect(crypto.secureCompare(a, c), isFalse);
    });

    test('random keys are unique', () {
      final keys = List.generate(100, (_) => crypto.generateDek());
      final unique = keys.map((k) => CryptoService.b64Encode(k)).toSet();
      expect(unique.length, equals(100)); // All 100 should be unique
    });
  });
}
