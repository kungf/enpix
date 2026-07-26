import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../../core/constants/crypto_constants.dart';

class CryptoService {
  final Cipher _aead = Xchacha20.poly1305Aead();
  final Blake2b _blake2b =
      Blake2b(hashLengthInBytes: CryptoConstants.blake2bHashLength);

  /// Max time (ms) for a single Argon2id probe attempt.
  static const int _argon2ProbeTimeoutMs = 3000;

  /// Derive KEK with specific Argon2id params (used for adaptive probing
  /// and for reading old entries with legacy params).
  Future<Uint8List> deriveKekWithParams(
    String passphrase,
    Uint8List salt, {
    required int memory,
    required int iterations,
  }) async {
    final argon2id = Argon2id(
      parallelism: CryptoConstants.argon2Parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: CryptoConstants.argon2HashLength,
    );
    final key = await argon2id.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Derive KEK with legacy fixed params (for existing users).
  Future<Uint8List> deriveKek(String passphrase, Uint8List salt) async {
    return deriveKekWithParams(
      passphrase,
      salt,
      memory: CryptoConstants.argon2MemorySize,
      iterations: CryptoConstants.argon2Iterations,
    );
  }

  /// Probe the device to find the strongest Argon2id params it can handle.
  /// Returns (memory, ops) that complete within ~2 seconds.
  Future<({int memory, int ops})> probeArgon2Params(
    String passphrase,
    Uint8List salt,
  ) async {
    var memory = CryptoConstants.argon2MemoryStart;
    var ops = CryptoConstants.argon2OpsStart;

    while (memory >= CryptoConstants.argon2MemoryFloor) {
      final sw = Stopwatch()..start();
      try {
        await deriveKekWithParams(
          passphrase,
          salt,
          memory: memory,
          iterations: ops,
        );
        sw.stop();
        if (sw.elapsedMilliseconds < _argon2ProbeTimeoutMs) {
          return (memory: memory, ops: ops);
        }
      } catch (_) {
        // Any failure (Exception or Error, e.g. OOM on devices with limited
        // memory) — fall through to next tier.
      }
      memory ~/= 2;
      ops *= 2;
    }

    // Fallback: floor params.
    return (
      memory: CryptoConstants.argon2MemoryFloor,
      ops: CryptoConstants.argon2OpsFloor
    );
  }

  Future<String> computeFingerprint(List<int> kek) async {
    final h = await _blake2b.hash(kek);
    return base64Url.encode(h.bytes);
  }

  Uint8List generateSalt() => _random(CryptoConstants.argon2SaltLength);
  Uint8List generateDek() => _random(CryptoConstants.xchacha20KeyLength);
  Uint8List generateNonce() => _random(CryptoConstants.xchacha20NonceLength);
  Uint8List generateMasterKey() => _random(CryptoConstants.xchacha20KeyLength);
  Uint8List generateRecoveryKey() =>
      _random(CryptoConstants.xchacha20KeyLength);

  Future<Uint8List> wrapKey(Uint8List key, Uint8List kek) async {
    final nonce = _random(CryptoConstants.keyWrapNonceLength);
    final box =
        await _aead.encrypt(key, secretKey: SecretKey(kek), nonce: nonce);
    return _concat(nonce, box.cipherText, box.mac.bytes);
  }

  Future<Uint8List> unwrapKey(Uint8List wrapped, Uint8List kek) async {
    final nonce = wrapped.sublist(0, CryptoConstants.keyWrapNonceLength);
    final macStart = wrapped.length - 16;
    final ct = wrapped.sublist(CryptoConstants.keyWrapNonceLength, macStart);
    final mac = Mac(wrapped.sublist(macStart));
    final clear = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: SecretKey(kek),
    );
    return Uint8List.fromList(clear);
  }

  Future<Uint8List> encrypt(
    Uint8List plain,
    Uint8List dek,
    Uint8List nonce,
  ) async {
    final box =
        await _aead.encrypt(plain, secretKey: SecretKey(dek), nonce: nonce);
    return _concat(nonce, box.cipherText, box.mac.bytes);
  }

  Future<Uint8List> decrypt(Uint8List data, Uint8List dek) async {
    final nonce = data.sublist(0, CryptoConstants.xchacha20NonceLength);
    final macStart = data.length - 16;
    final ct = data.sublist(CryptoConstants.xchacha20NonceLength, macStart);
    final mac = Mac(data.sublist(macStart));
    final clear = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: SecretKey(dek),
    );
    return Uint8List.fromList(clear);
  }

  Future<Uint8List> hash(List<int> data) async {
    final r = await _blake2b.hash(data);
    return Uint8List.fromList(r.bytes);
  }

  /// Zero the buffer contents. Note: Dart's GC may have copied the [Uint8List]
  /// to a new heap location, so the original sensitive bytes could persist in
  /// freed memory. This is a known Dart/Flutter limitation — there is no
  /// equivalent of `SecureZeroMemory` or `mlock`. Calling this is still
  /// worthwhile: it zeros the most recent live copy and reduces the window
  /// where sensitive data is readable.
  void secureFree(Uint8List b) {
    for (int i = 0; i < b.length; i++) {
      b[i] = 0;
    }
  }

  bool secureCompare(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int d = 0;
    for (int i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  Uint8List _random(int len) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(len, (_) => rng.nextInt(256)));
  }

  Uint8List _concat(Uint8List a, List<int> b, List<int> c) {
    final r = Uint8List(a.length + b.length + c.length);
    r.setAll(0, a);
    r.setAll(a.length, b);
    r.setAll(a.length + b.length, c);
    return r;
  }

  static String b64Encode(Uint8List b) => base64Url.encode(b);
  static Uint8List b64Decode(String s) =>
      Uint8List.fromList(base64Url.decode(s));
}
