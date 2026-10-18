import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/core/utils/retry.dart';
import 'package:enpix/services/cache/thumbnail_cache.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/crypto/credential_service.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';

/// S3 user-metadata header names (lowercased, as returned by
/// [S3Service.headObject]).
const String kMetadataDek = 'x-amz-meta-dek';
const String kMetadataHash = 'x-amz-meta-hash';
const String kMetadataFilename = 'x-amz-meta-filename';

/// Attempts per cloud operation: 1 initial + 2 retries for transient errors.
const int kCloudMaxAttempts = 3;

/// Thrown when a cloud object cannot be listed, decrypted, or verified.
class CloudMediaException implements Exception {
  const CloudMediaException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'CloudMediaException: $message';
}

/// Decrypted original plus the integrity result.
@immutable
class CloudMediaContent {
  const CloudMediaContent({
    required this.bytes,
    required this.fileName,
    required this.hashVerified,
  });

  final Uint8List bytes;

  /// Original file name from object metadata, when present.
  final String? fileName;

  /// True when the stored BLAKE2b hash matched the decrypted bytes.
  /// False for legacy objects uploaded without a hash.
  final bool hashVerified;
}

@immutable
class CloudDeleteFailure {
  const CloudDeleteFailure({required this.media, required this.error});

  final CloudMedia media;
  final Object error;
}

@immutable
class CloudDeleteReport {
  const CloudDeleteReport({required this.deleted, required this.failures});

  final int deleted;
  final List<CloudDeleteFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

/// Seam for the cloud gallery so its controller can be tested without S3,
/// crypto, or a photo library.
abstract interface class CloudMediaGateway {
  Future<List<CloudMedia>> listThumbnails();
  Future<Uint8List> loadThumbnail(CloudMedia media);
  Future<CloudMediaContent> fetchOriginal(CloudMedia media);
  Future<CloudDeleteReport> deleteAll(Iterable<CloudMedia> items);
}

/// Reads and deletes cloud objects for the cloud gallery.
///
/// Keeps the S3/crypto mechanics out of the widget layer so the listing,
/// decryption, hash verification, and delete flows are unit-testable.
class CloudMediaRepository implements CloudMediaGateway {
  CloudMediaRepository({
    required S3Service s3,
    required CryptoService crypto,
    required CredentialService credentials,
    required ThumbnailCache cache,
    int maxAttempts = kCloudMaxAttempts,
    Future<void> Function(Duration delay) sleep = _defaultSleep,
  })  : _s3 = s3,
        _crypto = crypto,
        _credentials = credentials,
        _cache = cache,
        _maxAttempts = maxAttempts,
        _sleep = sleep;

  final Logger _log = Logger('CloudMediaRepository');

  final S3Service _s3;
  final CryptoService _crypto;
  final CredentialService _credentials;
  final ThumbnailCache _cache;
  final int _maxAttempts;
  final Future<void> Function(Duration delay) _sleep;

  /// Lists every backup thumbnail under `enpix/`, newest day first.
  ///
  /// Non-thumbnail objects and keys that do not match the layout are
  /// skipped rather than failing the whole listing.
  @override
  Future<List<CloudMedia>> listThumbnails() async {
    final objects = await _withRetry(() => _s3.listObjects('enpix/'));
    final items = <CloudMedia>[];
    for (final object in objects) {
      if (!object.key.contains('/$kThumbnailsSegment/')) continue;
      final media = CloudMedia.fromObject(object);
      if (media != null) items.add(media);
    }
    items.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.fileId.compareTo(a.fileId);
    });
    _log.info('Listed ${items.length} cloud thumbnails');
    return List<CloudMedia>.unmodifiable(items);
  }

  /// Downloads and decrypts one thumbnail, refreshing the disk cache.
  @override
  Future<Uint8List> loadThumbnail(CloudMedia media) async {
    final meta = await _withRetry(() => _s3.headObject(media.thumbnailKey));
    final dekB64 = meta[kMetadataDek];
    if (dekB64 == null) {
      throw CloudMediaException('缩略图缺少解密元数据', cause: media.thumbnailKey);
    }
    final encrypted = await _withRetry(() => _s3.getObject(media.thumbnailKey));
    final plaintext = await _decrypt(encrypted, dekB64);

    // Cache write failure must not hide a successful decrypt.
    try {
      await _cache.save(media.fileId, plaintext);
    } on Exception catch (e) {
      _log.warning('Thumbnail cache save failed: ${media.fileId} — $e');
    }
    return plaintext;
  }

  /// Downloads, decrypts, and integrity-checks the encrypted original.
  ///
  /// Throws [CloudMediaException] when the session is locked, metadata is
  /// missing, or the BLAKE2b hash does not match the decrypted bytes.
  @override
  Future<CloudMediaContent> fetchOriginal(CloudMedia media) async {
    final meta = await _withRetry(() => _s3.headObject(media.originalKey));
    final dekB64 = meta[kMetadataDek];
    if (dekB64 == null) {
      throw CloudMediaException('云端原始文件缺少解密元数据', cause: media.originalKey);
    }

    final encrypted = await _withRetry(() => _s3.getObject(media.originalKey));
    final plaintext = await _decrypt(encrypted, dekB64);

    final expectedHash = meta[kMetadataHash];
    if (expectedHash == null) {
      // Legacy objects predate hash metadata — accept but surface it.
      _log.warning('No hash metadata for ${media.originalKey}');
      return CloudMediaContent(
        bytes: plaintext,
        fileName: meta[kMetadataFilename],
        hashVerified: false,
      );
    }

    final actualHash = await _crypto.hash(plaintext);
    final matches = _crypto.secureCompare(
      actualHash,
      CryptoService.b64Decode(expectedHash),
    );
    if (!matches) {
      throw CloudMediaException(
        '完整性校验失败，文件可能已损坏',
        cause: media.originalKey,
      );
    }
    return CloudMediaContent(
      bytes: plaintext,
      fileName: meta[kMetadataFilename],
      hashVerified: true,
    );
  }

  /// Permanently deletes the original and thumbnail of every item.
  ///
  /// A missing object counts as deleted (DELETE is idempotent); other
  /// failures are collected so one bad item does not block the rest.
  @override
  Future<CloudDeleteReport> deleteAll(Iterable<CloudMedia> items) async {
    var deleted = 0;
    final failures = <CloudDeleteFailure>[];
    for (final item in items) {
      try {
        await _deleteObject(item.originalKey);
        await _deleteObject(item.thumbnailKey);
        deleted++;
      } on Exception catch (e) {
        _log.warning('Delete failed: ${item.originalKey} — $e');
        failures.add(CloudDeleteFailure(media: item, error: e));
      }
    }
    _log.info('Deleted $deleted cloud items, ${failures.length} failed');
    return CloudDeleteReport(
      deleted: deleted,
      failures: List<CloudDeleteFailure>.unmodifiable(failures),
    );
  }

  Future<void> _deleteObject(String key) async {
    try {
      await _withRetry(() => _s3.deleteObject(key));
    } on StorageException catch (e) {
      // Some S3-compatible servers report 404 for an already-missing key.
      if (_httpStatus(e.cause) == 404) return;
      rethrow;
    }
  }

  Future<Uint8List> _decrypt(Uint8List encrypted, String wrappedDekB64) async {
    final masterKey = _credentials.sessionMasterKey;
    if (masterKey == null) {
      throw const CloudMediaException('会话已锁定，请先解锁');
    }
    final dek = await _crypto.unwrapKey(
      CryptoService.b64Decode(wrappedDekB64),
      masterKey,
    );
    try {
      return await _crypto.decrypt(encrypted, dek);
    } on Exception catch (e) {
      throw CloudMediaException('解密失败', cause: e);
    } finally {
      _crypto.secureFree(dek);
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() operation) => withRetry(
        operation,
        isRetryable: S3Service.isRetryable,
        maxAttempts: _maxAttempts,
        sleep: _sleep,
      );

  static int? _httpStatus(Object? error) {
    if (error is DioException) return error.response?.statusCode;
    if (error is StorageException) return _httpStatus(error.cause);
    return null;
  }

  static Future<void> _defaultSleep(Duration delay) =>
      Future<void>.delayed(delay);
}
