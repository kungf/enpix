import 'package:enpix/services/storage/s3_service.dart';

/// Segment names in the S3 key layout.
const String kThumbnailsSegment = 'thumbs';
const String kOriginalsSegment = 'files';
const String kThumbnailSuffix = '_thumb.enc';
const String kEncryptedSuffix = '.enc';

/// Parsed identity of a backed-up object, recovered from its S3 key.
///
/// Key layout written by [S3Service.generateThumbKey]:
/// `enpix/{prefix?}/{deviceId}/thumbs/YYYYMMDD/{fileId}_thumb.enc`
class CloudMediaKey {
  const CloudMediaKey({
    required this.fileId,
    required this.deviceId,
    required this.createdAt,
  });

  final String fileId;
  final String deviceId;
  final DateTime createdAt;

  /// Parses a thumbnail key. Returns null for any key that is not a
  /// well-formed thumbnail object — callers skip those.
  static CloudMediaKey? parse(String key) {
    if (!key.endsWith(kThumbnailSuffix)) return null;
    final parts = key.split('/');
    final thumbsIndex = parts.indexOf(kThumbnailsSegment);
    // Need a device segment before "thumbs" and a date + file after it.
    if (thumbsIndex < 1 || thumbsIndex + 2 != parts.length - 1) return null;

    final fileName = parts.last;
    final fileId =
        fileName.substring(0, fileName.length - kThumbnailSuffix.length);
    if (fileId.isEmpty) return null;

    final createdAt = _parseDate(parts[thumbsIndex + 1]);
    if (createdAt == null) return null;

    return CloudMediaKey(
      fileId: fileId,
      deviceId: parts[thumbsIndex - 1],
      createdAt: createdAt,
    );
  }

  /// Parses an 8-digit `YYYYMMDD` segment, rejecting impossible dates.
  static DateTime? _parseDate(String segment) {
    if (segment.length != 8) return null;
    final value = int.tryParse(segment);
    if (value == null) return null;
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // Reject overflow like 20260231 → March 3.
    if (date.month != month || date.day != day) return null;
    return date;
  }
}

/// A backed-up photo as seen from the cloud: its encrypted thumbnail plus
/// everything needed to derive the original object's key.
class CloudMedia {
  const CloudMedia({
    required this.fileId,
    required this.thumbnailKey,
    required this.originalKey,
    required this.deviceId,
    required this.createdAt,
    required this.thumbnailSize,
  });

  final String fileId;
  final String thumbnailKey;

  /// Encrypted original object key — derived by swapping the `thumbs`
  /// segment for `files` and dropping the `_thumb` suffix.
  final String originalKey;
  final String deviceId;
  final DateTime createdAt;
  final int thumbnailSize;

  /// `YYYY-MM-DD`, used to group items by day.
  String get dateKey => formatDateKey(createdAt);

  /// Builds a cloud item from a listed thumbnail object.
  /// Returns null when the key does not match the expected layout.
  static CloudMedia? fromObject(S3Object object) {
    final parsed = CloudMediaKey.parse(object.key);
    if (parsed == null) return null;
    final originalKey = originalKeyFor(object.key);
    if (originalKey == null) return null;
    return CloudMedia(
      fileId: parsed.fileId,
      thumbnailKey: object.key,
      originalKey: originalKey,
      deviceId: parsed.deviceId,
      createdAt: parsed.createdAt,
      thumbnailSize: object.size,
    );
  }

  /// Derives the original object key from a thumbnail key.
  static String? originalKeyFor(String thumbnailKey) {
    const thumbMarker = '/$kThumbnailsSegment/';
    final markerIndex = thumbnailKey.indexOf(thumbMarker);
    if (markerIndex < 0) return null;
    if (!thumbnailKey.endsWith(kThumbnailSuffix)) return null;
    final prefix = thumbnailKey.substring(0, markerIndex);
    final tail = thumbnailKey.substring(markerIndex + thumbMarker.length);
    final withoutSuffix =
        tail.substring(0, tail.length - kThumbnailSuffix.length);
    return '$prefix/$kOriginalsSegment/$withoutSuffix$kEncryptedSuffix';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudMedia &&
          other.thumbnailKey == thumbnailKey &&
          other.originalKey == originalKey;

  @override
  int get hashCode => Object.hash(thumbnailKey, originalKey);
}

/// `YYYY-MM-DD` for grouping and stable section keys.
String formatDateKey(DateTime date) => '${date.year}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// One day's worth of cloud items.
class CloudMediaDay {
  const CloudMediaDay({
    required this.dateKey,
    required this.label,
    required this.items,
  });

  final String dateKey;
  final String label;
  final List<CloudMedia> items;
}
