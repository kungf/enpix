/// S3 listObjects() E2E Test
/// Run:
///   S3_ENDPOINT=http://192.168.18.100:9000 S3_BUCKET=wytest \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/s3_list_objects_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:see_photo/domain/entities/storage_config.dart';
import 'package:see_photo/services/storage/s3_service.dart';

final _endpoint = Platform.environment['S3_ENDPOINT'] ?? 'http://localhost:9000';
final _bucket = Platform.environment['S3_BUCKET'] ?? 'test';
final _ak = Platform.environment['S3_ACCESS_KEY'] ?? '';
final _sk = Platform.environment['S3_SECRET_KEY'] ?? '';
final _region = Platform.environment['S3_REGION'] ?? 'default';

void main() async {
  int passed = 0, failed = 0;
  void ok(String m) { passed++; print('  ✅ $m'); }
  void fail(String m) { failed++; print('  ❌ $m'); }

  print('═══ S3 listObjects() Test ═══');
  print('Endpoint: $_endpoint');
  print('Bucket: $_bucket\n');

  final s3 = S3Service();
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: _bucket,
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));

  // T1: List empty bucket.
  print('T1: List empty bucket');
  try {
    final objects = await s3.listObjects('');
    ok('Listed ${objects.length} objects');
  } catch (e) {
    fail('Failed: $e');
  }

  // T2: Upload a test file, then list.
  print('\nT2: Upload + List');
  try {
    final testData = Uint8List.fromList([1, 2, 3, 4]);
    final testKey = 'test-list-obj';
    await s3.putObject(testKey, testData, contentType: 'application/octet-stream');
    final objects = await s3.listObjects('');
    final found = objects.any((o) => o.key.contains(testKey));
    if (found) ok('Found uploaded object in list');
    else fail('Object not found in list (${objects.length} objects)');
    await s3.deleteObject(testKey);
  } catch (e) {
    fail('Failed: $e');
  }

  // T3: List with prefix.
  print('\nT3: List with prefix');
  try {
    final testData = Uint8List.fromList([5, 6, 7, 8]);
    await s3.putObject('prefix-test/file1', testData);
    await s3.putObject('prefix-test/file2', testData);
    await s3.putObject('other/file3', testData);
    final objects = await s3.listObjects('prefix-test/');
    final count = objects.where((o) => o.key.startsWith('prefix-test/')).length;
    if (count == 2) ok('Prefix filter works ($count objects)');
    else fail('Expected 2, got $count');
    await s3.deleteObject('prefix-test/file1');
    await s3.deleteObject('prefix-test/file2');
    await s3.deleteObject('other/file3');
  } catch (e) {
    fail('Failed: $e');
  }

  // T4: List with thumbs/ prefix (simulates cloud gallery).
  print('\nT4: List thumbs/ prefix');
  try {
    final testData = Uint8List.fromList([9, 10, 11, 12]);
    await s3.putObject('thumbs/test_thumb.enc', testData);
    final objects = await s3.listObjects('thumbs/');
    final count = objects.where((o) => o.key.startsWith('thumbs/')).length;
    if (count >= 1) ok('Thumbs listing works ($count objects)');
    else fail('Expected >=1, got $count');
    await s3.deleteObject('thumbs/test_thumb.enc');
  } catch (e) {
    fail('Failed: $e');
  }

  // T5: List after testConnection (verify S3 state is clean).
  print('\nT5: testConnection then listObjects');
  try {
    final msg = await s3.testConnection();
    ok('testConnection: $msg');
    final objects = await s3.listObjects('');
    ok('listObjects after testConnection: ${objects.length} objects');
  } catch (e) {
    fail('Failed: $e');
  }

  print('\n═══ listObjects: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
