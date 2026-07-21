import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/services/upload/upload_tracker.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage storage;
  late UploadTracker tracker;

  setUp(() {
    storage = _MockSecureStorage();
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    tracker = UploadTracker(storage: storage);
  });

  group('migration', () {
    test('migrates legacy List format to records (unknown timestamps)',
        () async {
      when(() => storage.read(key: 'upload_records'))
          .thenAnswer((_) async => jsonEncode(['a', 'b', 'c']));
      expect(await tracker.uploadedCount, 3);
      expect(await tracker.isUploaded('a'), isTrue);
      // Migrated records (t=0) are excluded from the activity chart.
      expect((await tracker.countsPerDay(7)).fold<int>(0, (a, b) => a + b), 0);
    });

    test('migrates legacy Map<id, timestamp> format', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      when(() => storage.read(key: 'upload_records'))
          .thenAnswer((_) async => jsonEncode({'a': now, 'b': now - 86400000}));
      final counts = await tracker.countsPerDay(7);
      expect(counts.fold<int>(0, (a, b) => a + b), 2);
    });
  });

  group('countsPerDay + totalBytes', () {
    test('marks today and sums bytes', () async {
      await tracker.markUploaded('a', sizeBytes: 1024);
      await tracker.markUploaded('b', sizeBytes: 2048);
      final counts = await tracker.countsPerDay(7);
      expect(counts.last, 2); // today is the last bucket
      expect(await tracker.totalBytes, 3072);
    });
  });

  group('prune', () {
    test('drops records older than 180 days, keeps unknown-timestamp ones',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = now - const Duration(days: 400).inMilliseconds;
      when(() => storage.read(key: 'upload_records')).thenAnswer((_) async {
        return jsonEncode({
          'old': {'t': old, 's': 100},
          'today': {'t': now, 's': 200},
          'unknown': {'t': 0, 's': 300},
        });
      });
      expect(await tracker.uploadedCount, 2); // 'today' + 'unknown'
      expect(await tracker.isUploaded('old'), isFalse);
      expect(await tracker.isUploaded('today'), isTrue);
      expect(await tracker.isUploaded('unknown'), isTrue);
      expect(await tracker.totalBytes, 500);
    });
  });
}
