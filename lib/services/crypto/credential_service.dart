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
  // NOTE: KEK is stored plaintext (Keychain is hardware-encrypted at rest).
  static const _kekKey = 'wrapped_kek_v1'; // key name kept for backward compat
  static const _kekSaltKey = 'kek_salt_v1';
  static const _kekFingerprintKey = 'kek_fingerprint_v1';
  static const _hasPassphraseKey = 'has_passphrase';
  static const _savedPassphraseKey = 'saved_passphrase';
  static const _s3EndpointKey = 's3_endpoint';
  static const _s3BucketKey = 's3_bucket';
  static const _s3RegionKey = 's3_region';

  // Master Key chain keys (v2 — introduced with recovery key support)
  static const _wrappedMasterKeyKey = 'wrapped_master_key_v1';
  static const _argon2MemoryKey = 'argon2_memory_v1';
  static const _argon2OpsKey = 'argon2_ops_v1';

  // Session state
  Uint8List? _sessionKek;
  Uint8List? _sessionMasterKey;
  bool _sessionActive = false;

  /// The current session KEK. Null if session not active.
  Uint8List? get sessionKek => _sessionActive ? _sessionKek : null;

  /// The current session Master Key. Null if session not active.
  Uint8List? get sessionMasterKey => _sessionActive ? _sessionMasterKey : null;

  CredentialService(this._crypto, this._storage);

  // ── Session Management ───────────────────────────────────────

  /// Whether a session is currently active (either via password unlock or recovery key).
  bool get isSessionActive => _sessionActive && _sessionMasterKey != null;

  /// Start a session by providing the unwrapped KEK.
  /// The KEK is held in memory until [endSession] is called or the app terminates.
  void startSession(Uint8List kek) {
    _sessionKek = kek;
    _sessionActive = true;
    _log.info('KEK session started');
  }

  /// End the session and zero KEK + Master Key from memory.
  void endSession() {
    if (_sessionKek != null) {
      _crypto.secureFree(_sessionKek!);
      _sessionKek = null;
    }
    if (_sessionMasterKey != null) {
      _crypto.secureFree(_sessionMasterKey!);
      _sessionMasterKey = null;
    }
    _sessionActive = false;
    _log.info('Session ended (KEK + Master Key zeroed)');
  }

  // ── Passphrase Setup ─────────────────────────────────────────

  /// Whether a passphrase has been set up.
  Future<bool> hasPassphrase() async {
    final val = await _storage.read(key: _hasPassphraseKey);
    return val == 'true';
  }

  /// Set up a new passphrase: derive KEK (adaptive params), generate Master Key,
  /// wrap Master Key with KEK, store everything. Returns the derived KEK so
  /// callers (e.g. [changePassphrase]) can use it before it is zeroed.
  Future<Uint8List> setupPassphrase(String passphrase) async {
    _log.info('Setting up passphrase...');

    // Generate salt
    final salt = _crypto.generateSalt();

    // Probe adaptive Argon2id params
    final params = await _crypto.probeArgon2Params(passphrase, salt);
    _log.info('Adaptive Argon2id: memory=${params.memory} KiB, ops=${params.ops}');

    // Derive KEK with probed params
    final kek = await _crypto.deriveKekWithParams(
      passphrase, salt,
      memory: params.memory,
      iterations: params.ops,
    );

    // Compute fingerprint for verification
    final fingerprint = await _crypto.computeFingerprint(kek);

    // Generate Master Key (random, never changes)
    final masterKey = _crypto.generateMasterKey();

    // Wrap Master Key with KEK
    final wrappedMk = await _crypto.wrapKey(masterKey, kek);

    // Store to Keychain
    await _storage.write(key: _kekSaltKey, value: CryptoService.b64Encode(salt));
    await _storage.write(key: _kekKey, value: CryptoService.b64Encode(kek));
    await _storage.write(key: _kekFingerprintKey, value: fingerprint);
    await _storage.write(key: _hasPassphraseKey, value: 'true');
    await _storage.write(key: _wrappedMasterKeyKey, value: CryptoService.b64Encode(wrappedMk));
    await _storage.write(key: _argon2MemoryKey, value: params.memory.toString());
    await _storage.write(key: _argon2OpsKey, value: params.ops.toString());

    _log.info('Passphrase setup complete (adaptive params, Master Key generated)');
    return kek;
  }

  // ── KEK Unlock ───────────────────────────────────────────────

  /// Unlock the KEK and Master Key using the passphrase.
  /// Returns the unwrapped KEK (caller must call startSession or zero after use).
  Future<Uint8List> unlockWithPassphrase(String passphrase) async {
    final saltB64 = await _storage.read(key: _kekSaltKey);
    final fingerprint = await _storage.read(key: _kekFingerprintKey);

    if (saltB64 == null || fingerprint == null) {
      throw StateError('No passphrase has been set up');
    }

    final salt = CryptoService.b64Decode(saltB64);

    // Try adaptive params first, fall back to legacy fixed params.
    final memStr = await _storage.read(key: _argon2MemoryKey);
    final opsStr = await _storage.read(key: _argon2OpsKey);

    Uint8List kek;
    if (memStr != null && opsStr != null) {
      kek = await _crypto.deriveKekWithParams(
        passphrase, salt,
        memory: int.parse(memStr),
        iterations: int.parse(opsStr),
      );
    } else {
      // Legacy user — use fixed params.
      kek = await _crypto.deriveKek(passphrase, salt);
    }

    // Verify fingerprint
    final computed = await _crypto.computeFingerprint(kek);
    if (computed != fingerprint) {
      _crypto.secureFree(kek);
      throw WrongPassphraseException();
    }

    // Unwrap Master Key
    final wrappedMkB64 = await _storage.read(key: _wrappedMasterKeyKey);
    Uint8List? masterKey;
    if (wrappedMkB64 != null) {
      final wrappedMk = CryptoService.b64Decode(wrappedMkB64);
      masterKey = await _crypto.unwrapKey(wrappedMk, kek);
    }

    // Start session
    startSession(kek);
    _sessionMasterKey = masterKey;

    // Save passphrase for auto-unlock on next app start
    await _storage.write(key: _savedPassphraseKey, value: passphrase);

    return kek;
  }

  /// Restore access using a Master Key recovered from the recovery key.
  /// After calling this, the user should set a new passphrase via [changePassphrase].
  void restoreWithRecoveryKey(Uint8List masterKey) {
    _sessionMasterKey = masterKey;
    _sessionActive = true;
    _log.info('Session restored from recovery key (Master Key only, no KEK)');
  }

  /// Whether the session has a Master Key (either from normal unlock or recovery).
  bool get hasMasterKey => _sessionActive && _sessionMasterKey != null;

  /// Try to auto-unlock using the saved passphrase from Keychain.
  /// Returns true if unlock succeeded, false if no saved passphrase or unlock failed.
  Future<bool> autoUnlock() async {
    if (isSessionActive) return true;
    try {
      final passphrase = await _storage.read(key: _savedPassphraseKey);
      if (passphrase == null) return false;
      await unlockWithPassphrase(passphrase);
      return true;
    } on Exception catch (e) {
      _log.warning('Auto-unlock failed: $e');
      // Clear invalid saved passphrase
      await _storage.delete(key: _savedPassphraseKey);
      return false;
    }
  }

  /// Verify the passphrase without starting a session.
  Future<bool> verifyPassphrase(String passphrase) async {
    try {
      await unlockWithPassphrase(passphrase);
      endSession();
      return true;
    } on WrongPassphraseException {
      return false;
    } on StateError {
      return false; // No passphrase set up
    } on Exception catch (_) {
      // Corrupted Keychain data or other unexpected failure.
      return false;
    }
  }

  /// Change the passphrase: re-derive KEK with new password, re-wrap the
  /// existing Master Key. Master Key itself never changes.
  Future<void> changePassphrase(String oldPassphrase, String newPassphrase) async {
    _log.info('Changing passphrase...');

    // Read existing S3 credentials before ending the old session.
    final creds = await loadS3Credentials();

    // Unlock with old KEK to verify the old password is correct.
    final oldKek = await unlockWithPassphrase(oldPassphrase);

    // Preserve the Master Key before ending the old session.
    // Deep copy — endSession() will zero the original buffer.
    final masterKey = _sessionMasterKey != null
        ? Uint8List.fromList(_sessionMasterKey!)
        : null;

    // End old session, then zero the local reference.
    endSession();
    _crypto.secureFree(oldKek);

    // Derive new KEK with adaptive params.
    final salt = _crypto.generateSalt();
    final params = await _crypto.probeArgon2Params(newPassphrase, salt);
    final newKek = await _crypto.deriveKekWithParams(
      newPassphrase, salt,
      memory: params.memory,
      iterations: params.ops,
    );
    final fingerprint = await _crypto.computeFingerprint(newKek);

    // Re-wrap the same Master Key with the new KEK.
    Uint8List? wrappedMk;
    if (masterKey != null) {
      wrappedMk = await _crypto.wrapKey(masterKey, newKek);
    }

    // Store updated Keychain entries.
    await _storage.write(key: _kekSaltKey, value: CryptoService.b64Encode(salt));
    await _storage.write(key: _kekKey, value: CryptoService.b64Encode(newKek));
    await _storage.write(key: _kekFingerprintKey, value: fingerprint);
    await _storage.write(key: _argon2MemoryKey, value: params.memory.toString());
    await _storage.write(key: _argon2OpsKey, value: params.ops.toString());
    if (wrappedMk != null) {
      await _storage.write(key: _wrappedMasterKeyKey, value: CryptoService.b64Encode(wrappedMk));
    }

    // Re-save S3 credentials.
    if (creds != null) {
      await saveS3Credentials(creds.accessKey, creds.secretKey);
    }

    // Zero the new KEK (it's in Keychain now).
    _crypto.secureFree(newKek);
    if (masterKey != null) {
      _crypto.secureFree(masterKey);
    }

    _log.info('Passphrase changed successfully (Master Key preserved)');
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
    await _storage.delete(key: _kekKey);
    await _storage.delete(key: _kekSaltKey);
    await _storage.delete(key: _kekFingerprintKey);
    await _storage.delete(key: _hasPassphraseKey);
    await _storage.delete(key: _savedPassphraseKey);
    await _storage.delete(key: _wrappedMasterKeyKey);
    await _storage.delete(key: _argon2MemoryKey);
    await _storage.delete(key: _argon2OpsKey);
    _log.warning('All credentials and keys deleted');
  }
}
