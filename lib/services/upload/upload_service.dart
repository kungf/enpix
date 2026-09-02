import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import '../crypto/crypto_service.dart';
import '../storage/s3_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/retry.dart';

/// Total attempts for a single S3 PUT: 1 initial + 3 retries,
/// backing off 1s / 2s / 4s (±25% jitter) between attempts.
const int kUploadMaxAttempts = 4;

/// S3 multipart part size: 8MB. S3 requires every part except the last to
/// be ≥5MB — 8MB clears that and keeps a single part well under the 300s
/// receive timeout even on slow links.
const int kMultipartPartSize = 8 * 1024 * 1024;

/// Encrypted files larger than this use multipart upload; anything smaller
/// is a single PUT (a one-part multipart would only add overhead).
const int kMultipartThreshold = kMultipartPartSize;

class UploadService {
  final Logger _log = Logger('UploadService');
  final CryptoService _crypto;
  final S3Service _s3;

  UploadService(this._crypto, this._s3);

  /// Full upload pipeline: encrypt → upload to S3 with metadata.
  /// Also generates, encrypts, and uploads a thumbnail.
  /// Returns [UploadResult] with the decrypted thumbnail JPEG for local caching.
  ///
  /// Uses content hash as the S3 fileId so the key is predictable — a HEAD
  /// check before encryption skips files that already exist on the remote.
  ///
  /// [plaintext] is the raw photo bytes — callers must read the file before
  /// calling this method to avoid TOCTOU races on temporary photo-library paths.
  ///
  /// [isCancelled] is checked between major steps so a long upload can be
  /// aborted mid-flight rather than running to completion.
  Future<UploadResult> upload({
    required Uint8List plaintext,
    required String fileName,
    required String mimeType,
    required DateTime createdAt,
    required Uint8List masterKey,
    bool Function() isCancelled = _neverCancelled,
  }) async {
    _log.info('Uploading: $fileName (${plaintext.length} bytes)');

    // 1. Hash original → use as fileId (content-addressable key).
    final hash = await _crypto.hash(plaintext);
    final hashHex = CryptoService.b64Encode(hash);
    final fileId = hashHex;

    // 2. Build S3 key and check remote existence.
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

    if (isCancelled()) throw const UploadCancelledException();

    // 3. Generate DEK + nonce
    final dek = _crypto.generateDek();
    final nonce = _crypto.generateNonce();

    // 4. Encrypt file
    final encrypted = await _crypto.encrypt(plaintext, dek, nonce);

    if (isCancelled()) throw const UploadCancelledException();

    // 5. Generate thumbnail
    Uint8List? thumbJpeg;
    try {
      final decoded = img.decodeImage(plaintext);
      if (decoded != null) {
        final thumb = img.copyResize(
          decoded,
          width: AppConstants.thumbnailMaxWidth,
          height: AppConstants.thumbnailMaxHeight,
          interpolation: img.Interpolation.cubic,
        );
        thumbJpeg = Uint8List.fromList(
          img.encodeJpg(thumb, quality: AppConstants.thumbnailQuality),
        );
        _log.fine('Thumbnail generated: ${thumbJpeg.length} bytes');
      }
    } catch (e) {
      _log.warning('Thumbnail generation failed (non-fatal): $e');
    }

    if (isCancelled()) throw const UploadCancelledException();

    // 6. Wrap DEK with Master Key
    Uint8List wrappedDek;
    try {
      wrappedDek = await _crypto.wrapKey(dek, masterKey);
    } finally {
      _crypto.secureFree(dek);
    }

    // 7. Build thumb key
    final thumbKey = _s3.makeThumbKey(fileId, createdAt);

    if (isCancelled()) throw const UploadCancelledException();

    // 8. Upload original to S3 (retries transient network/server errors)
    try {
      final metadata = {
        'dek': CryptoService.b64Encode(wrappedDek),
        'nonce': CryptoService.b64Encode(nonce),
        'hash': hashHex,
        'filename': fileName,
      };
      if (encrypted.length > kMultipartThreshold) {
        await _uploadMultipart(
          key,
          encrypted,
          metadata: metadata,
          contentType: mimeType,
          isCancelled: isCancelled,
        );
      } else {
        _log.info('PUT to S3: $key (${encrypted.length} bytes)');
        await withRetry(
          () => _s3.putObject(
            key,
            encrypted,
            metadata: metadata,
            contentType: mimeType,
          ),
          isRetryable: S3Service.isRetryable,
          maxAttempts: kUploadMaxAttempts,
          onRetry: (attempt, error, delay) => _log.warning(
            'PUT $key attempt $attempt failed, '
            'retry in ${delay.inMilliseconds}ms: $error',
          ),
        );
      }
    } on UploadCancelledException {
      // Cancellation must reach BackupManager as itself — not be recorded
      // as a failed file.
      rethrow;
    } catch (e) {
      _log.severe('S3 upload failed: $e');
      return UploadResult.error('Upload failed: $e');
    }

    if (isCancelled()) throw const UploadCancelledException();

    // 9. Encrypt and upload thumbnail to S3
    if (thumbJpeg != null) {
      try {
        final thumbNonce = _crypto.generateNonce();
        // Use a fresh DEK for thumbnail, wrapped with same Master Key
        final thumbDek = _crypto.generateDek();
        final encryptedThumb =
            await _crypto.encrypt(thumbJpeg, thumbDek, thumbNonce);
        final wrappedThumbDek = await _crypto.wrapKey(thumbDek, masterKey);
        _crypto.secureFree(thumbDek);

        _log.info(
          'PUT thumb to S3: $thumbKey (${encryptedThumb.length} bytes)',
        );
        await withRetry(
          () => _s3.putObject(
            thumbKey,
            encryptedThumb,
            metadata: {
              'dek': CryptoService.b64Encode(wrappedThumbDek),
              'nonce': CryptoService.b64Encode(thumbNonce),
            },
            contentType: 'image/jpeg',
          ),
          isRetryable: S3Service.isRetryable,
          maxAttempts: kUploadMaxAttempts,
          onRetry: (attempt, error, delay) => _log.warning(
            'PUT thumb $thumbKey attempt $attempt failed, '
            'retry in ${delay.inMilliseconds}ms: $error',
          ),
        );
      } catch (e) {
        // Thumbnail upload failure is non-fatal
        _log.warning('Thumbnail upload failed (non-fatal): $e');
        thumbJpeg = null;
      }
    }

    _log.info('Upload complete: $key');
    return UploadResult.success(
      key,
      hashHex,
      encrypted.length,
      thumbData: thumbJpeg,
    );
  }

  /// Upload [encrypted] via S3 multipart in 8MB parts, retrying each part
  /// independently — a flaky link re-sends one part, not the whole file.
  /// Aborts the upload on failure or cancellation so orphaned parts don't
  /// linger in the bucket.
  Future<void> _uploadMultipart(
    String key,
    Uint8List encrypted, {
    required Map<String, String> metadata,
    required String contentType,
    required bool Function() isCancelled,
  }) async {
    final uploadId = await _s3.initiateMultipartUpload(
      key,
      metadata: metadata,
      contentType: contentType,
    );
    final totalParts = (encrypted.length / kMultipartPartSize).ceil();
    _log.info(
      'MULTIPART PUT: $key (${encrypted.length} bytes, $totalParts parts)',
    );
    try {
      final parts = <S3Part>[];
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        if (isCancelled()) throw const UploadCancelledException();
        final start = (partNumber - 1) * kMultipartPartSize;
        final end = math.min(partNumber * kMultipartPartSize, encrypted.length);
        // Zero-copy view — the source buffer is never mutated.
        final chunk = Uint8List.sublistView(encrypted, start, end);
        final etag = await withRetry(
          () => _s3.uploadPart(key, uploadId, partNumber, chunk),
          isRetryable: S3Service.isRetryable,
          maxAttempts: kUploadMaxAttempts,
          onRetry: (attempt, error, delay) => _log.warning(
            'PUT part $key#$partNumber attempt $attempt failed, '
            'retry in ${delay.inMilliseconds}ms: $error',
          ),
        );
        parts.add(S3Part(partNumber, etag));
      }
      await _s3.completeMultipartUpload(key, uploadId, parts);
    } on Exception {
      // Abort so parts already stored don't linger; a failed abort is left
      // to bucket lifecycle rules (AbortIncompleteMultipartUpload).
      try {
        await _s3.abortMultipartUpload(key, uploadId);
      } on Exception catch (abortError) {
        _log.warning('Abort multipart failed ($key): $abortError');
      }
      rethrow;
    }
  }

  static bool _neverCancelled() => false;
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

  factory UploadResult.success(
    String key,
    String hash,
    int size, {
    Uint8List? thumbData,
  }) =>
      UploadResult._(
        success: true,
        s3Key: key,
        fileHash: hash,
        size: size,
        thumbData: thumbData,
      );

  factory UploadResult.remoteExists(String key, String hash) => UploadResult._(
        success: true,
        s3Key: key,
        fileHash: hash,
        remoteExists: true,
      );

  factory UploadResult.error(String msg) =>
      UploadResult._(success: false, error: msg);
}

/// Thrown by [UploadService.upload] when the caller's [isCancelled] callback
/// returns true.  Catch this in backup loops to abort the current upload
/// without marking it as failed.
class UploadCancelledException implements Exception {
  const UploadCancelledException();
}
