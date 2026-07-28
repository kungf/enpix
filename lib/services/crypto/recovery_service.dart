import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:logging/logging.dart';

import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';

/// Service for managing recovery keys — the user's last-resort backup
/// when they forget their password.
///
/// A recovery key is a random 256-bit value, shown to the user as a
/// 24-word BIP-39 mnemonic. It encrypts (wraps) the Master Key and the
/// wrapped form is stored on S3 at a fixed path (enpix/.sys/recovery),
/// so it can be found on any device without relying on Keychain data.
class RecoveryService {
  static const _recoveryPath = 'enpix/.sys/recovery';

  final Logger _log = Logger('RecoveryService');
  final CryptoService _crypto;
  final S3Service _s3;

  RecoveryService(this._crypto, this._s3);

  /// Generate a new recovery key and set it up:
  /// 1. Generate random Recovery Key
  /// 2. Wrap Master Key with Recovery Key
  /// 3. Upload wrapped Master Key to S3 at enpix/.sys/recovery
  /// 4. Return the mnemonic for the user to write down
  Future<String> setupRecovery({
    required Uint8List masterKey,
  }) async {
    _log.info('Setting up recovery key...');

    // 1. Generate recovery key
    final recoveryKey = _crypto.generateRecoveryKey();

    // 2. Wrap master key with recovery key
    final wrappedMk = await _crypto.wrapKey(masterKey, recoveryKey);

    // 3. Upload to S3 at fixed path
    final payload = jsonEncode({
      'v': 1,
      'wrapped_master_key': CryptoService.b64Encode(wrappedMk),
    });
    await _s3.putObject(
      _recoveryPath,
      Uint8List.fromList(utf8.encode(payload)),
      contentType: 'application/json',
    );

    _log.info('Recovery key uploaded to $_recoveryPath');

    // 4. Convert to mnemonic
    final mnemonic = _recoveryKeyToMnemonic(recoveryKey);

    // 5. Zero the raw key
    _crypto.secureFree(recoveryKey);

    return mnemonic;
  }

  /// Recover the Master Key from a mnemonic provided by the user.
  /// Downloads the wrapped Master Key from enpix/.sys/recovery and
  /// unwraps it with the parsed recovery key.
  Future<Uint8List> recoverFromMnemonic({
    required String mnemonic,
  }) async {
    _log.info('Recovering from mnemonic...');

    // 1. Parse mnemonic → recovery key
    final recoveryKey = _mnemonicToRecoveryKey(mnemonic);

    // 2. Download recovery blob from S3
    final Uint8List payload;
    try {
      payload = await _s3.getObject(_recoveryPath);
    } on Exception catch (e) {
      _crypto.secureFree(recoveryKey);
      throw RecoveryException('无法从 S3 下载恢复数据: $e');
    }

    // 3. Parse JSON — switch on type to avoid TypeError (Error, not Exception).
    final Map<String, dynamic> json;
    final decoded = jsonDecode(utf8.decode(payload));
    switch (decoded) {
      case Map<String, dynamic> map:
        json = map;
      default:
        _crypto.secureFree(recoveryKey);
        throw const RecoveryException('恢复数据格式错误');
    }

    final wrappedMkB64 = json['wrapped_master_key'] as String?;
    if (wrappedMkB64 == null) {
      _crypto.secureFree(recoveryKey);
      throw const RecoveryException('恢复数据不完整');
    }
    final wrappedMk = CryptoService.b64Decode(wrappedMkB64);

    // 4. Unwrap master key
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
  Future<bool> hasRecoveryMetadata() async {
    return _s3.objectExists(_recoveryPath);
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
}

class RecoveryException implements Exception {
  final String message;
  const RecoveryException(this.message);
  @override
  String toString() => message;
}
