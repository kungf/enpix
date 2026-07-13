import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import '../../core/errors/storage_exception.dart';
import 'crypto_service.dart';

/// Service for securely storing and retrieving user credentials.
///
/// Keychain stores:
///   - AK/SK — plaintext (iOS Keychain / Android EncryptedSharedPreferences
///     provide hardware-backed encryption at rest — no per-user KEK wrapping
///     needed for local credential storage)
///   - KEK — derived from passphrase via Argon2id, held in memory during
///     active session, used to wrap/unwrap per-photo DEKs for end-to-end
///     photo encryption
///
/// Session model:
///   - On app start: autoUnlock() re-derives KEK from saved passphrase
///   - Session KEK must be in memory to upload new photos or decrypt cloud photos
///   - S3 connection (AK/SK) does NOT require a session — credentials are
///     always readable from Keychain
class CredentialService {
  final Logger _log = Logger('CredentialService');
  final CryptoService _crypto;
  final FlutterSecureStorage _storage;

  // Keychain keys
  static const _akKey = 'access_key_v2';
  static const _skKey = 'secret_key_v2';
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

  /// Change the passphrase: set up new KEK (old KEK no longer wraps S3
  /// credentials — they are stored plaintext in Keychain).
  Future<void> changePassphrase(String oldPassphrase, String newPassphrase) async {
    _log.info('Changing passphrase...');

    // Read existing S3 credentials before ending the old session.
    final creds = await loadS3Credentials();

    // Unlock with old KEK to verify the old password is correct.
    final oldKek = await unlockWithPassphrase(oldPassphrase);

    // End old session, then zero the local reference. The KEK bytes are shared
    // with _sessionKek, so we must null _sessionKek first (in endSession)
    // before freeing the memory.
    endSession();
    _crypto.secureFree(oldKek);

    // Set up new passphrase.
    final newKek = await setupPassphrase(newPassphrase);
    startSession(newKek);

    // Re-save S3 credentials (now as plaintext under the new session).
    if (creds != null) {
      await saveS3Credentials(creds.accessKey, creds.secretKey);
    }

    endSession();
    _log.info('Passphrase changed successfully');
  }

  // ── S3 Credential Storage ────────────────────────────────────

  /// Save S3 credentials to Keychain (hardware-encrypted by the platform).
  Future<void> saveS3Credentials(String accessKey, String secretKey) async {
    await _storage.write(key: _akKey, value: accessKey);
    await _storage.write(key: _skKey, value: secretKey);
    _log.info('S3 credentials saved');
  }

  /// Load S3 credentials directly from Keychain.
  Future<({String accessKey, String secretKey})?> loadS3Credentials() async {
    final ak = await _storage.read(key: _akKey);
    final sk = await _storage.read(key: _skKey);
    if (ak == null || sk == null) return null;
    return (accessKey: ak, secretKey: sk);
  }

  /// Get the KEK fingerprint (12-char prefix used for S3 path isolation).
  Future<String?> getKekFingerprint() async {
    return _storage.read(key: _kekFingerprintKey);
  }

  /// Whether S3 credentials have been saved.
  Future<bool> hasS3Credentials() async {
    final ak = await _storage.read(key: _akKey);
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
    await _storage.delete(key: _akKey);
    await _storage.delete(key: _skKey);
    _log.warning('S3 credentials deleted');
  }

  Future<void> resetAll() async {
    endSession();
    await _storage.delete(key: _akKey);
    await _storage.delete(key: _skKey);
    await _storage.delete(key: _wrappedKekKey);
    await _storage.delete(key: _kekSaltKey);
    await _storage.delete(key: _kekFingerprintKey);
    await _storage.delete(key: _hasPassphraseKey);
    await _storage.delete(key: _savedPassphraseKey);
    _log.warning('All credentials and keys deleted');
  }
}
