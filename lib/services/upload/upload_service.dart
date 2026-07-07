import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import '../crypto/crypto_service.dart';
import '../crypto/credential_service.dart';
import '../storage/s3_service.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/storage_config.dart';

class UploadService {
  final Logger _log = Logger('UploadService');
  final CryptoService _crypto;
  final CredentialService _credService;
  final S3Service _s3;

  UploadService(this._crypto, this._credService, this._s3);

  /// Full upload pipeline: encrypt file → upload to S3 with metadata.
  /// Also generates, encrypts, and uploads a thumbnail.
  /// Returns [UploadResult] with the decrypted thumbnail JPEG for local caching.
  ///
  /// Uses content hash as the S3 fileId so the key is predictable — a HEAD
  /// check before encryption skips files that already exist on the remote.
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

    // 2. Hash original → use as fileId (content-addressable key).
    final hash = await _crypto.hash(plaintext);
    final hashHex = CryptoService.b64Encode(hash);
    final fileId = hashHex;

    // 3. Build S3 key and check remote existence.
    final key = _s3.makeKey(fileId, createdAt);
    try {
      if (await _s3.objectExists(key)) {
        _log.info('Remote exists, skipped: $key');
        return UploadResult.remoteExists(key, hashHex);
      }
    } on Exception catch (e) {
      // HEAD failed for a reason other than 404/403 — non-fatal, just upload.
      _log.warning('Remote check failed (non-fatal, will upload): $e');
    }

    // 4. Generate DEK + nonce
    final dek = _crypto.generateDek();
    final nonce = _crypto.generateNonce();

    // 5. Encrypt file
    final encrypted = await _crypto.encrypt(plaintext, dek, nonce);

    // 6. Generate thumbnail
    Uint8List? thumbJpeg;
    try {
      final decoded = img.decodeImage(plaintext);
      if (decoded != null) {
        final thumb = img.copyResize(
          decoded,
          width: AppConstants.thumbnailMaxWidth,
          height: AppConstants.thumbnailMaxHeight,
          interpolation: img.Interpolation.linear,
        );
        thumbJpeg = Uint8List.fromList(img.encodeJpg(thumb, quality: AppConstants.thumbnailQuality));
        _log.fine('Thumbnail generated: ${thumbJpeg.length} bytes');
      }
    } catch (e) {
      _log.warning('Thumbnail generation failed (non-fatal): $e');
    }

    // 7. Wrap DEK with KEK
    Uint8List wrappedDek;
    try {
      wrappedDek = await _crypto.wrapKey(dek, kek);
    } finally {
      _crypto.secureFree(dek);
    }

    // 8. Build thumb key
    final thumbKey = _s3.makeThumbKey(fileId, createdAt);

    // 9. Upload original to S3
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

    // 10. Encrypt and upload thumbnail to S3
    if (thumbJpeg != null) {
      try {
        final thumbNonce = _crypto.generateNonce();
        // Use a fresh DEK for thumbnail, wrapped with same KEK
        final thumbDek = _crypto.generateDek();
        final encryptedThumb = await _crypto.encrypt(thumbJpeg, thumbDek, thumbNonce);
        final wrappedThumbDek = await _crypto.wrapKey(thumbDek, kek);
        _crypto.secureFree(thumbDek);

        _log.info('PUT thumb to S3: $thumbKey (${encryptedThumb.length} bytes)');
        await _s3.putObject(thumbKey, encryptedThumb, metadata: {
          'dek': CryptoService.b64Encode(wrappedThumbDek),
          'nonce': CryptoService.b64Encode(thumbNonce),
        }, contentType: 'image/jpeg');
      } catch (e) {
        // Thumbnail upload failure is non-fatal
        _log.warning('Thumbnail upload failed (non-fatal): $e');
        thumbJpeg = null;
      }
    }

    _log.info('Upload complete: $key');
    return UploadResult.success(key, hashHex, encrypted.length, thumbData: thumbJpeg);
  }
}

class UploadResult {
  final bool success;
  final String? s3Key;
  final String? fileHash;
  final int? size;
  final Uint8List? thumbData;
  final String? error;
  final bool remoteExists;

  UploadResult._({
    required this.success,
    this.s3Key,
    this.fileHash,
    this.size,
    this.thumbData,
    this.error,
    this.remoteExists = false,
  });

  factory UploadResult.success(String key, String hash, int size, {Uint8List? thumbData}) =>
      UploadResult._(success: true, s3Key: key, fileHash: hash, size: size, thumbData: thumbData);

  factory UploadResult.remoteExists(String key, String hash) =>
      UploadResult._(success: true, s3Key: key, fileHash: hash, remoteExists: true);

  factory UploadResult.error(String msg) =>
      UploadResult._(success: false, error: msg);
}
