import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:logging/logging.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';

/// Service for managing recovery keys — the user's last-resort backup
/// when they forget their password.
///
/// A recovery key is a random 256-bit value, shown to the user as a
/// 24-word BIP-39 mnemonic.  It encrypts (wraps) the Master Key and
/// the wrapped form is stored on S3.  On password recovery the user
/// provides the mnemonic, which unwraps the Master Key, restoring
/// full access to all encrypted data.
class RecoveryService {
  final Logger _log = Logger('RecoveryService');
  final CryptoService _crypto;
  final S3Service _s3;

  RecoveryService(this._crypto, this._s3);

  /// Generate a new recovery key and set it up:
  /// 1. Generate random Recovery Key
  /// 2. Wrap Master Key with Recovery Key
  /// 3. Upload wrapped Master Key to S3
  /// 4. Return the mnemonic for the user to write down
  Future<String> setupRecovery({
    required Uint8List masterKey,
    required String kekFingerprint,
  }) async {
    _log.info('Setting up recovery key...');

    // 1. Generate recovery key
    final recoveryKey = _crypto.generateRecoveryKey();

    // 2. Wrap master key with recovery key
    final wrappedMk = await _crypto.wrapKey(masterKey, recoveryKey);

    // 3. Upload to S3
    final s3Key = _makeRecoveryKey(kekFingerprint);
    await _s3.putObject(
      s3Key,
      wrappedMk,
      contentType: 'application/octet-stream',
    );

    _log.info('Recovery key uploaded to S3');

    // 4. Convert to mnemonic
    final mnemonic = _recoveryKeyToMnemonic(recoveryKey);

    // 5. Zero the raw key
    _crypto.secureFree(recoveryKey);

    return mnemonic;
  }

  /// Recover the Master Key from a mnemonic provided by the user.
  /// Returns the decrypted Master Key, or throws if the mnemonic is invalid
  /// or the S3 object is missing.
  Future<Uint8List> recoverFromMnemonic({
    required String mnemonic,
    required String kekFingerprint,
  }) async {
    _log.info('Recovering from mnemonic...');

    // 1. Parse mnemonic → recovery key
    final recoveryKey = _mnemonicToRecoveryKey(mnemonic);

    // 2. Download wrapped master key from S3
    final s3Key = _makeRecoveryKey(kekFingerprint);
    final Uint8List wrappedMk;
    try {
      wrappedMk = await _s3.getObject(s3Key);
    } on Exception catch (e) {
      _crypto.secureFree(recoveryKey);
      throw RecoveryException('无法从 S3 下载恢复数据: $e');
    }

    // 3. Unwrap master key
    final Uint8List masterKey;
    try {
      masterKey = await _crypto.unwrapKey(wrappedMk, recoveryKey);
    } on Exception catch (_) {
      _crypto.secureFree(recoveryKey);
      throw const RecoveryException('恢复密钥错误或数据损坏');
    } finally {
      _crypto.secureFree(recoveryKey);
    }

    _log.info('Recovery successful');
    return masterKey;
  }

  /// Check if recovery metadata exists on S3.
  Future<bool> hasRecoveryMetadata(String kekFingerprint) async {
    final s3Key = _makeRecoveryKey(kekFingerprint);
    return _s3.objectExists(s3Key);
  }

  /// Convert a recovery key (32 bytes) to a 24-word BIP-39 mnemonic.
  String _recoveryKeyToMnemonic(Uint8List key) {
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return bip39.entropyToMnemonic(hex);
  }

  /// Convert a 24-word BIP-39 mnemonic back to the recovery key (32 bytes).
  Uint8List _mnemonicToRecoveryKey(String mnemonic) {
    final trimmed = mnemonic.trim().split(RegExp(r'\s+')).join(' ');
    if (!bip39.validateMnemonic(trimmed)) {
      throw const RecoveryException('恢复密钥格式错误，请检查是否为 24 个英文单词');
    }
    final hex = bip39.mnemonicToEntropy(trimmed);
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// S3 path for recovery metadata.
  String _makeRecoveryKey(String kekFingerprint) {
    final prefix = kekFingerprint.length >= 12
        ? kekFingerprint.substring(0, 12)
        : 'shared';
    return '$prefix/.recovery/wrapped_master_key.bin';
  }
}

class RecoveryException implements Exception {
  final String message;
  const RecoveryException(this.message);
  @override
  String toString() => message;
}
