import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/storage/s3_service.dart';

void main() {
  group('CloudMediaKey.parse', () {
    test('parses a standard thumbnail key', () {
      final key = CloudMediaKey.parse(
        'enpix/wyang-iphone8/thumbs/20260307/abc_thumb.enc',
      );

      expect(key, isNotNull);
      expect(key!.fileId, 'abc');
      expect(key.deviceId, 'wyang-iphone8');
      expect(key.createdAt, DateTime(2026, 3, 7));
    });

    test('parses a key that carries an extra prefix segment', () {
      final key = CloudMediaKey.parse(
        'enpix/team-a/wyang-iphone8/thumbs/20260307/abc_thumb.enc',
      );

      expect(key, isNotNull);
      expect(key!.deviceId, 'wyang-iphone8');
    });

    test('rejects a key without the thumbnail suffix', () {
      expect(
        CloudMediaKey.parse('enpix/dev/thumbs/20260307/abc.enc'),
        isNull,
      );
    });

    test('rejects a key that has no thumbs segment', () {
      expect(
        CloudMediaKey.parse('enpix/dev/files/20260307/abc_thumb.enc'),
        isNull,
      );
    });

    test('rejects an impossible calendar date', () {
      expect(
        CloudMediaKey.parse('enpix/dev/thumbs/20260231/abc_thumb.enc'),
        isNull,
      );
    });

    test('rejects an empty file id', () {
      expect(
        CloudMediaKey.parse('enpix/dev/thumbs/20260307/_thumb.enc'),
        isNull,
      );
    });
  });

  group('CloudMedia', () {
    test('derives the original key from the thumbnail key', () {
      expect(
        CloudMedia.originalKeyFor('enpix/dev/thumbs/20260307/abc_thumb.enc'),
        'enpix/dev/files/20260307/abc.enc',
      );
    });

    test('derives the original key when the path has a prefix', () {
      expect(
        CloudMedia.originalKeyFor(
          'enpix/team/dev/thumbs/20260307/abc_thumb.enc',
        ),
        'enpix/team/dev/files/20260307/abc.enc',
      );
    });

    test('ignores original objects during listing', () {
      final media = CloudMedia.fromObject(
        const S3Object(
          key: 'enpix/dev/files/20260307/abc.enc',
          size: 10,
          lastModified: '2026-03-07T00:00:00Z',
        ),
      );

      expect(media, isNull);
    });

    test('carries size, device, and date from the listing', () {
      final media = CloudMedia.fromObject(
        const S3Object(
          key: 'enpix/dev/thumbs/20260307/abc_thumb.enc',
          size: 1234,
          lastModified: '2026-03-07T00:00:00Z',
        ),
      );

      expect(media, isNotNull);
      expect(media!.fileId, 'abc');
      expect(media.deviceId, 'dev');
      expect(media.thumbnailSize, 1234);
      expect(media.dateKey, '2026-03-07');
      expect(media.originalKey, 'enpix/dev/files/20260307/abc.enc');
    });
  });

  test('formatDateKey pads month and day', () {
    expect(formatDateKey(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
