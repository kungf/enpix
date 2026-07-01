/// S3 getObject() E2E Test — simulates cloud gallery preview flow
/// Run:
///   S3_ENDPOINT=http://192.168.18.100:9000 S3_BUCKET=wytest \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/s3_get_object_test.dart

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

  print('═══ S3 getObject() Test ═══\n');

  final s3 = S3Service();
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: _bucket,
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));

  // T1: PUT + GET roundtrip.
  print('T1: PUT + GET roundtrip');
  try {
    final data = Uint8List.fromList([1, 2, 3, 4, 5]);
    await s3.putObject('get-test/roundtrip.enc', data);
    final got = await s3.getObject('get-test/roundtrip.enc');
    if (got.length == data.length && got[0] == 1 && got[4] == 5) {
      ok('Content verified (${got.length} bytes)');
    } else {
      fail('Content mismatch: expected ${data.length}, got ${got.length}');
    }
    await s3.deleteObject('get-test/roundtrip.enc');
  } catch (e) {
    fail('Failed: $e');
  }

  // T2: GET with key containing date folder (new format).
  print('\nT2: GET with date folder key');
  try {
    final data = Uint8List.fromList([10, 20, 30]);
    final key = 'files/20260701/test-file.enc';
    await s3.putObject(key, data);
    final got = await s3.getObject(key);
    if (got.length == 3 && got[0] == 10) ok('Date folder key works');
    else fail('Content mismatch');
    await s3.deleteObject(key);
  } catch (e) {
    fail('Failed: $e');
  }

  // T3: GET thumb key (simulates cloud gallery thumb download).
  print('\nT3: GET thumb key');
  try {
    final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // fake JPEG header
    final key = 'thumbs/20260701/abc-123_thumb.enc';
    await s3.putObject(key, data);
    final got = await s3.getObject(key);
    if (got.length == 4 && got[0] == 0xFF) ok('Thumb key works');
    else fail('Content mismatch');
    await s3.deleteObject(key);
  } catch (e) {
    fail('Failed: $e');
  }

  // T4: GET full image key (simulates cloud gallery full preview).
  print('\nT4: GET full image key');
  try {
    final data = Uint8List(1024); // 1KB fake encrypted photo
    for (int i = 0; i < data.length; i++) data[i] = i % 256;
    final key = 'files/20260701/full-photo-uuid.enc';
    await s3.putObject(key, data);
    final got = await s3.getObject(key);
    if (got.length == 1024 && got[255] == 255) ok('Full image key works (${got.length} bytes)');
    else fail('Content mismatch');
    await s3.deleteObject(key);
  } catch (e) {
    fail('Failed: $e');
  }

  // T5: GET non-existent key (should throw).
  print('\nT5: GET non-existent key');
  try {
    await s3.getObject('non-existent-key-xyz.enc');
    fail('Should have thrown');
  } catch (e) {
    ok('Threw as expected: ${e.runtimeType}');
  }

  // T6: PUT + HEAD + GET + DELETE full flow.
  print('\nT6: Full PUT/HEAD/GET/DELETE flow');
  try {
    final data = Uint8List.fromList([100, 200, 50, 75]);
    await s3.putObject('flow-test.obj', data, metadata: {'test': 'value'});
    final head = await s3.headObject('flow-test.obj');
    if (head['x-amz-meta-test'] == 'value') ok('HEAD metadata OK');
    else fail('Metadata mismatch');
    final got = await s3.getObject('flow-test.obj');
    if (got.length == 4) ok('GET OK');
    else fail('Size mismatch');
    await s3.deleteObject('flow-test.obj');
    try {
      await s3.headObject('flow-test.obj');
      fail('Should have been deleted');
    } catch (_) {
      ok('DELETE confirmed');
    }
  } catch (e) {
    fail('Failed: $e');
  }

  print('\n═══ getObject: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
