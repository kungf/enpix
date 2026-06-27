import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import '../crypto/crypto_service.dart';
import '../crypto/credential_service.dart';
import '../storage/s3_service.dart';
import '../../domain/entities/storage_config.dart';

class UploadService {
  final Logger _log = Logger('UploadService');
  final CryptoService _crypto;
  final CredentialService _credService;
  final S3Service _s3;

  UploadService(this._crypto, this._credService, this._s3);

  /// Full upload pipeline: encrypt file → upload to S3 with metadata.
  Future<UploadResult> upload({
    required String localPath,
    required String fileName,
    required String mimeType,
    required DateTime createdAt,
    required Uint8List kek,
  }) async {
    _log.info('Uploading: $fileName');

    // 1. Read file
    final file = File(localPath);
    if (!file.existsSync()) return UploadResult.error('File not found: $localPath');
    final plaintext = await file.readAsBytes();

    // 2. Hash original
    final hash = await _crypto.hash(plaintext);
    final hashHex = CryptoService.b64Encode(hash);

    // 3. Generate DEK + nonce
    final dek = _crypto.generateDek();
    final nonce = _crypto.generateNonce();

    // 4. Encrypt file
    final encrypted = await _crypto.encrypt(plaintext, dek, nonce);

    // 5. Wrap DEK with KEK
    Uint8List wrappedDek;
    try {
      wrappedDek = await _crypto.wrapKey(dek, kek);
    } finally {
      _crypto.secureFree(dek);
    }

    // 6. Build S3 key with fingerprint prefix (use UUID, not content hash)
    final fingerprint = await _credService.getKekFingerprint();
    final fileId = const Uuid().v7();
    final key = S3Service.generateKey(fingerprint ?? 'shared', fileId, createdAt);

    // 7. Upload to S3
    try {
      _log.info('PUT to S3: $key (${encrypted.length} bytes)');
      await _s3.putObject(key, encrypted, metadata: {
        'dek': CryptoService.b64Encode(wrappedDek),
        'nonce': CryptoService.b64Encode(nonce),
        'hash': hashHex,
        'filename': fileName,
      }, contentType: mimeType);
    } catch (e) {
      _log.severe('S3 upload failed: $e');
      return UploadResult.error('Upload failed: $e');
    }

    _log.info('Upload complete: $key');
    return UploadResult.success(key, hashHex, encrypted.length);
  }
}

class UploadResult {
  final bool success;
  final String? s3Key;
  final String? fileHash;
  final int? size;
  final String? error;

  UploadResult._({required this.success, this.s3Key, this.fileHash, this.size, this.error});

  factory UploadResult.success(String key, String hash, int size) =>
      UploadResult._(success: true, s3Key: key, fileHash: hash, size: size);

  factory UploadResult.error(String msg) =>
      UploadResult._(success: false, error: msg);
}
