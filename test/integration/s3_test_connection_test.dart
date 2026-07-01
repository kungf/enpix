/// S3 testConnection() Method E2E Test
/// Run:
///   S3_ENDPOINT=http://192.168.18.100:9000 S3_BUCKET=wytest \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/s3_test_connection_test.dart

import 'dart:io';
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

  print('═══ S3 testConnection() Test ═══');
  print('Endpoint: $_endpoint');
  print('Bucket: $_bucket\n');

  final s3 = S3Service();

  // T1: Not configured — should throw.
  print('T1: Not configured (should throw)');
  try {
    await s3.testConnection();
    fail('Should have thrown');
  } catch (e) {
    ok('Threw as expected: ${e.runtimeType}');
  }

  // T2: Configure with correct credentials — should pass.
  print('\nT2: Correct credentials (should pass)');
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: _bucket,
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  try {
    final msg = await s3.testConnection();
    ok('Passed: $msg');
  } catch (e) {
    fail('Failed: $e');
  }

  // T3: Wrong access key — should fail.
  print('\nT3: Wrong access key (should fail)');
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: _bucket,
    region: _region,
    accessKey: 'wrong-key',
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  try {
    await s3.testConnection();
    fail('Should have thrown');
  } catch (e) {
    ok('Threw as expected: ${e.runtimeType}');
  }

  // T4: Wrong bucket — should fail.
  print('\nT4: Wrong bucket (should fail)');
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: 'nonexistent-bucket-xyz',
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  try {
    await s3.testConnection();
    fail('Should have thrown');
  } catch (e) {
    ok('Threw as expected: ${e.runtimeType}');
  }

  // T5: Wrong endpoint — should fail.
  print('\nT5: Wrong endpoint (should fail)');
  s3.configure(StorageConfig(
    endpointUrl: 'http://192.168.18.100:19999',
    bucketName: _bucket,
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  try {
    await s3.testConnection();
    fail('Should have thrown');
  } catch (e) {
    ok('Threw as expected: ${e.runtimeType}');
  }

  // T6: Re-configure with correct credentials — should pass again.
  print('\nT6: Re-configure correct (should pass)');
  s3.configure(StorageConfig(
    endpointUrl: _endpoint,
    bucketName: _bucket,
    region: _region,
    accessKey: _ak,
    secretKey: _sk,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ));
  try {
    final msg = await s3.testConnection();
    ok('Passed: $msg');
  } catch (e) {
    fail('Failed: $e');
  }

  print('\n═══ testConnection: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
