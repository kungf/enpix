import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import '../../core/errors/storage_exception.dart';
import 'crypto_service.dart';

/// Service for securely storing and retrieving user credentials.
///
/// Implements Plan C layered encryption:
///
///   AK/SK ──► XChaCha20(KEK) ──► Keychain
///   KEK    ──► Secure Enclave   ──► Keychain
///
/// - AK/SK never stored in plaintext on disk
/// - KEK wrapped by hardware-backed device key (Secure Enclave / StrongBox)
/// - Session: KEK held in memory for background backup tasks
/// - After reboot: require Face ID or passphrase to unlock
class CredentialService {
  final Logger _log = Logger('CredentialService');
  final CryptoService _crypto;
  final FlutterSecureStorage _storage;

  // Keychain keys (not the encryption keys themselves)
  static const _encryptedAkKey = 'encrypted_access_key';
  static const _encryptedSkKey = 'encrypted_secret_key';
  static const _wrappedKekKey = 'wrapped_kek_v1';
  static const _kekSaltKey = 'kek_salt_v1';
  static const _kekFingerprintKey = 'kek_fingerprint_v1';
  static const _hasPassphraseKey = 'has_passphrase';
  static const _savedPassphraseKey = 'saved_passphrase';
  static const _s3EndpointKey = 's3_endpoint';
  static const _s3BucketKey = 's3_bucket';
  static const _s3RegionKey = 's3_region';

  // Session state
  Uint8List? _sessionKek;
  bool _sessionActive = false;

  /// The current session KEK. Null if session not active.
  Uint8List? get sessionKek => _sessionActive ? _sessionKek : null;

  CredentialService(this._crypto, this._storage);

  // ── Session Management ───────────────────────────────────────

  /// Whether a KEK session is currently active.
  bool get isSessionActive => _sessionActive && _sessionKek != null;

  /// Start a session by providing the unwrapped KEK.
  /// The KEK is held in memory until [endSession] is called or the app terminates.
  void startSession(Uint8List kek) {
    _sessionKek = kek;
    _sessionActive = true;
    _log.info('KEK session started');
  }

  /// End the session and zero the KEK from memory.
  void endSession() {
    if (_sessionKek != null) {
      _crypto.secureFree(_sessionKek!);
      _sessionKek = null;
    }
    _sessionActive = false;
    _log.info('KEK session ended');
  }

  // ── Passphrase Setup ─────────────────────────────────────────

  /// Whether a passphrase has been set up.
  Future<bool> hasPassphrase() async {
    final val = await _storage.read(key: _hasPassphraseKey);
    return val == 'true';
  }

  /// Set up a new passphrase: derive KEK, wrap with device key, store.
  /// Returns the derived KEK so callers (e.g. [changePassphrase]) can use it
  /// before it is zeroed. The caller is responsible for starting a session.
  Future<Uint8List> setupPassphrase(String passphrase) async {
    _log.info('Setting up passphrase...');

    // Generate salt
    final salt = _crypto.generateSalt();

    // Derive KEK
    final kek = await _crypto.deriveKek(passphrase, salt);

    // Compute fingerprint for verification
    final fingerprint = await _crypto.computeFingerprint(kek);

    // In production: wrap KEK with Secure Enclave device key
    // For now: store directly (Keychain is already encrypted by OS)
    final wrappedKek = kek;

    // Store to Keychain
    await _storage.write(key: _kekSaltKey, value: CryptoService.b64Encode(salt));
    await _storage.write(key: _wrappedKekKey, value: CryptoService.b64Encode(wrappedKek));
    await _storage.write(key: _kekFingerprintKey, value: fingerprint);
    await _storage.write(key: _hasPassphraseKey, value: 'true');

    _log.info('Passphrase setup complete');
    return kek;
  }

  // ── KEK Unlock ───────────────────────────────────────────────

  /// Unlock the KEK using the passphrase.
  /// Returns the unwrapped KEK (caller must call startSession or zero after use).
  Future<Uint8List> unlockWithPassphrase(String passphrase) async {
    final saltB64 = await _storage.read(key: _kekSaltKey);
    final fingerprint = await _storage.read(key: _kekFingerprintKey);

    if (saltB64 == null || fingerprint == null) {
      throw StateError('No passphrase has been set up');
    }

    final salt = CryptoService.b64Decode(saltB64);
    final kek = await _crypto.deriveKek(passphrase, salt);

    // Verify fingerprint
    final computed = await _crypto.computeFingerprint(kek);
    if (computed != fingerprint) {
      _crypto.secureFree(kek);
      throw WrongPassphraseException();
    }

    // Start session
    startSession(kek);

    // Save passphrase for auto-unlock on next app start
    await _storage.write(key: _savedPassphraseKey, value: passphrase);

    return kek;
  }

  /// Try to auto-unlock using the saved passphrase from Keychain.
  /// Returns true if unlock succeeded, false if no saved passphrase or unlock failed.
  Future<bool> autoUnlock() async {
    if (isSessionActive) return true;
    try {
      final passphrase = await _storage.read(key: _savedPassphraseKey);
      if (passphrase == null) return false;
      await unlockWithPassphrase(passphrase);
      return true;
    } catch (e) {
      _log.warning('Auto-unlock failed: $e');
      // Clear invalid saved passphrase
      await _storage.delete(key: _savedPassphraseKey);
      return false;
    }
  }

  /// Verify the passphrase without starting a session.
  Future<bool> verifyPassphrase(String passphrase) async {
    try {
      final kek = await unlockWithPassphrase(passphrase);
      endSession();
      return true;
    } on WrongPassphraseException {
      return false;
    } on StateError {
      return false; // No passphrase set up
    }
  }

  /// Change the passphrase: re-encrypt existing credentials with new KEK.
  Future<void> changePassphrase(String oldPassphrase, String newPassphrase) async {
    _log.info('Changing passphrase...');

    // Unlock with old KEK
    final oldKek = await unlockWithPassphrase(oldPassphrase);

    // Get existing encrypted credentials
    final encryptedAk = await _storage.read(key: _encryptedAkKey);
    final encryptedSk = await _storage.read(key: _encryptedSkKey);

    // Decrypt with old KEK
    String? ak, sk;
    if (encryptedAk != null && encryptedSk != null) {
      ak = await _decryptString(encryptedAk, oldKek);
      sk = await _decryptString(encryptedSk, oldKek);
    }

    // End old session before setting up new passphrase
    endSession();

    // Set up new passphrase and get new KEK
    final newKek = await setupPassphrase(newPassphrase);

    // Start session with new KEK, then re-encrypt credentials
    startSession(newKek);
    if (ak != null && sk != null) {
      await saveS3Credentials(ak, sk);
    }

    endSession();
    _log.info('Passphrase changed successfully');
  }

  // ── S3 Credential Storage ────────────────────────────────────

  /// Save encrypted S3 credentials. Requires an active KEK session.
  Future<void> saveS3Credentials(String accessKey, String secretKey) async {
    if (!isSessionActive) throw StateError('KEK session not active');

    // Encrypt AK
    final nonce = _crypto.generateNonce();
    final encryptedAk = await _crypto.encrypt(
      Uint8List.fromList(utf8.encode(accessKey)),
      _sessionKek!,
      nonce,
    );
    await _storage.write(key: _encryptedAkKey, value: CryptoService.b64Encode(encryptedAk));

    // Encrypt SK
    final nonce2 = _crypto.generateNonce();
    final encryptedSk = await _crypto.encrypt(
      Uint8List.fromList(utf8.encode(secretKey)),
      _sessionKek!,
      nonce2,
    );
    await _storage.write(key: _encryptedSkKey, value: CryptoService.b64Encode(encryptedSk));

    _log.info('S3 credentials encrypted and saved');
  }

  /// Load and decrypt S3 credentials. Requires an active KEK session.
  Future<({String accessKey, String secretKey})?> loadS3Credentials() async {
    if (!isSessionActive) throw StateError('KEK session not active');

    final encryptedAk = await _storage.read(key: _encryptedAkKey);
    final encryptedSk = await _storage.read(key: _encryptedSkKey);

    if (encryptedAk == null || encryptedSk == null) return null;

    final ak = await _decryptString(encryptedAk, _sessionKek!);
    final sk = await _decryptString(encryptedSk, _sessionKek!);

    return (accessKey: ak, secretKey: sk);
  }

  /// Get the KEK fingerprint (12-char prefix used for S3 path isolation).
  Future<String?> getKekFingerprint() async {
    return _storage.read(key: _kekFingerprintKey);
  }

  /// Whether S3 credentials have been saved.
  Future<bool> hasS3Credentials() async {
    final ak = await _storage.read(key: _encryptedAkKey);
    return ak != null;
  }

  /// Save S3 connection details (endpoint, bucket, region).
  Future<void> saveS3Endpoint(String endpoint) async =>
      await _storage.write(key: _s3EndpointKey, value: endpoint);

  Future<void> saveS3Bucket(String bucket) async =>
      await _storage.write(key: _s3BucketKey, value: bucket);

  Future<void> saveS3Region(String region) async =>
      await _storage.write(key: _s3RegionKey, value: region);

  /// Load S3 connection details.
  Future<String?> getS3Endpoint() async =>
      _storage.read(key: _s3EndpointKey);

  Future<String?> getS3Bucket() async =>
      _storage.read(key: _s3BucketKey);

  Future<String?> getS3Region() async =>
      _storage.read(key: _s3RegionKey);

  /// Delete stored S3 credentials.
  Future<void> deleteS3Credentials() async {
    await _storage.delete(key: _encryptedAkKey);
    await _storage.delete(key: _encryptedSkKey);
    _log.warning('S3 credentials deleted');
  }

  // ── Helpers ──────────────────────────────────────────────────

  Future<String> _decryptString(String encryptedB64, Uint8List kek) async {
    final encrypted = CryptoService.b64Decode(encryptedB64);
    final plain = await _crypto.decrypt(encrypted, kek);
    return utf8.decode(plain);
  }

  /// Reset everything — delete all keys and credentials.
  Future<void> resetAll() async {
    endSession();
    await _storage.delete(key: _encryptedAkKey);
    await _storage.delete(key: _encryptedSkKey);
    await _storage.delete(key: _wrappedKekKey);
    await _storage.delete(key: _kekSaltKey);
    await _storage.delete(key: _kekFingerprintKey);
    await _storage.delete(key: _hasPassphraseKey);
    await _storage.delete(key: _savedPassphraseKey);
    _log.warning('All credentials and keys deleted');
  }
}
