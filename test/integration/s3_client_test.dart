/// S3 Client Integration Tests
/// Run:
///   S3_ENDPOINT=http://localhost:9000 S3_BUCKET=test \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/s3_client_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:dio/dio.dart';

final _endpoint = Platform.environment['S3_ENDPOINT'] ?? 'http://localhost:9000';
final _bucket = Platform.environment['S3_BUCKET'] ?? 'test';
final _ak = Platform.environment['S3_ACCESS_KEY'] ?? '';
final _sk = Platform.environment['S3_SECRET_KEY'] ?? '';
final _region = Platform.environment['S3_REGION'] ?? 'us-east-1';

void main() async {
  if (_ak.isEmpty || _sk.isEmpty) {
    print('ERROR: Set S3_ACCESS_KEY and S3_SECRET_KEY environment variables.');
    print('Example: S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin dart run ...');
    exit(1);
  }
  int passed = 0, failed = 0;
  void ok(String m) { passed++; print('  ✅ $m'); }
  void fail(String m) { failed++; print('  ❌ $m'); }

  print('═══ S3 Client Tests ═══\n');

  String p2(int n) => n.toString().padLeft(2, '0');
  String uriEnc(String p) => p.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');

  // SigV4 signing
  String sign(String method, String path, Map<String, String> hdrs, String ph) {
    final now = DateTime.now().toUtc();
    final amz = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
    final date = '${now.year}${p2(now.month)}${p2(now.day)}';
    final host = Uri.parse(_endpoint).host;
    final port = Uri.parse(_endpoint).hasPort ? ':${Uri.parse(_endpoint).port}' : '';
    final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph, 'x-amz-date': amz, ...hdrs};
    final sorted = h.keys.toList()..sort();
    final canon = sorted.map((k) => '${k.toLowerCase()}:${h[k]!.trim()}').join('\n');
    final signed = sorted.map((k) => k.toLowerCase()).join(';');
    final cr = [method, uriEnc(path), '', '$canon\n', signed, ph].join('\n');
    final scope = '$date/$_region/s3/aws4_request';
    final sts = ['AWS4-HMAC-SHA256', amz, scope, sha256.convert(utf8.encode(cr)).toString()].join('\n');
    final kDate = Hmac(sha256, utf8.encode('AWS4$_sk')).convert(utf8.encode(date)).bytes;
    final kReg = Hmac(sha256, kDate).convert(utf8.encode(_region)).bytes;
    final kSvc = Hmac(sha256, kReg).convert(utf8.encode('s3')).bytes;
    final signKey = Hmac(sha256, kSvc).convert(utf8.encode('aws4_request')).bytes;
    return 'AWS4-HMAC-SHA256 Credential=$_ak/$scope, SignedHeaders=$signed, Signature=${Hmac(sha256, signKey).convert(utf8.encode(sts)).toString()}';
  }

  Map<String, String> auth(String method, String path, {Map<String, String>? extra, String? ph}) {
    final now = DateTime.now().toUtc();
    final amz = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
    final host = Uri.parse(_endpoint).host;
    final port = Uri.parse(_endpoint).hasPort ? ':${Uri.parse(_endpoint).port}' : '';
    final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph ?? 'UNSIGNED-PAYLOAD', 'x-amz-date': amz, if (extra != null) ...extra};
    h['Authorization'] = sign(method, path, h, ph ?? 'UNSIGNED-PAYLOAD');
    return h;
  }

  final dio = Dio(BaseOptions(baseUrl: _endpoint, connectTimeout: const Duration(seconds: 10), validateStatus: (_) => true));

  // T1: Connectivity
  print('T1: Connectivity');
  try {
    final r = await dio.head('/$_bucket', options: Options(headers: auth('HEAD', '/$_bucket')));
    if (r.statusCode == 200 || r.statusCode == 403) ok('Reachable (${r.statusCode})');
    else fail('Status ${r.statusCode}');
  } catch (e) { fail('Unreachable: $e'); }

  // T2: PUT object
  print('\nT2: PUT object');
  final testKey = 'test/s3-client-test-${DateTime.now().millisecondsSinceEpoch}.bin';
  final testData = Uint8List.fromList(utf8.encode('S3 client test data'));
  final dataHash = sha256.convert(testData).toString();
  try {
    final sw = Stopwatch()..start();
    final extra = {'Content-Type': 'application/octet-stream', 'Content-Length': testData.length.toString(), 'x-amz-content-sha256': dataHash};
    final r = await dio.put('/$_bucket/$testKey', data: Stream.value(testData), options: Options(headers: auth('PUT', '/$_bucket/$testKey', extra: extra, ph: dataHash)));
    if (r.statusCode == 200) ok('PUT: ${sw.elapsedMilliseconds}ms');
    else fail('PUT status ${r.statusCode}');
  } catch (e) { fail('PUT: $e'); }

  // T3: HEAD object
  print('\nT3: HEAD object');
  try {
    final r = await dio.head('/$_bucket/$testKey', options: Options(headers: auth('HEAD', '/$_bucket/$testKey')));
    if (r.statusCode == 200) ok('HEAD OK (${r.headers.value('content-length')} bytes)');
    else fail('HEAD status ${r.statusCode}');
  } catch (e) { fail('HEAD: $e'); }

  // T4: GET object
  print('\nT4: GET object');
  try {
    final sw = Stopwatch()..start();
    final r = await dio.get('/$_bucket/$testKey', options: Options(headers: auth('GET', '/$_bucket/$testKey'), responseType: ResponseType.bytes));
    final data = Uint8List.fromList(List<int>.from(r.data));
    if (utf8.decode(data) == utf8.decode(testData)) ok('GET: ${sw.elapsedMilliseconds}ms, content verified');
    else fail('GET content mismatch');
  } catch (e) { fail('GET: $e'); }

  // T5: GET with Range
  print('\nT5: Range request');
  try {
    final r = await dio.get('/$_bucket/$testKey', options: Options(
      headers: auth('GET', '/$_bucket/$testKey', extra: {'Range': 'bytes=0-3'}),
      responseType: ResponseType.bytes,
    ));
    final data = Uint8List.fromList(List<int>.from(r.data));
    if (data.length == 4) ok('Range: 4 bytes OK');
    else fail('Range: expected 4, got ${data.length}');
  } catch (e) { fail('Range: $e'); }

  // T6: PUT with metadata
  print('\nT6: Metadata');
  try {
    final mk = 'test/meta-${DateTime.now().millisecondsSinceEpoch}.bin';
    final extra = <String, String>{
      'Content-Type': 'application/octet-stream', 'Content-Length': '10',
      'x-amz-meta-testkey': 'hello-world', 'x-amz-meta-version': '1',
      'x-amz-content-sha256': sha256.convert(Uint8List(10)).toString(),
    };
    await dio.put('/$_bucket/$mk', data: Stream.value(Uint8List(10)), options: Options(headers: auth('PUT', '/$_bucket/$mk', extra: extra, ph: sha256.convert(Uint8List(10)).toString())));
    final r = await dio.head('/$_bucket/$mk', options: Options(headers: auth('HEAD', '/$_bucket/$mk')));
    final testVal = r.headers.value('x-amz-meta-testkey');
    if (testVal == 'hello-world') ok('Metadata preserved');
    else fail('Metadata: got "$testVal"');
    await dio.delete('/$_bucket/$mk', options: Options(headers: auth('DELETE', '/$_bucket/$mk')));
  } catch (e) { fail('Metadata: $e'); }

  // T7: Delete
  print('\nT7: Delete');
  try {
    await dio.delete('/$_bucket/$testKey', options: Options(headers: auth('DELETE', '/$_bucket/$testKey')));
    final r = await dio.head('/$_bucket/$testKey', options: Options(headers: auth('HEAD', '/$_bucket/$testKey')));
    if (r.statusCode == 404) ok('Deleted OK (404)');
    else fail('Still exists (${r.statusCode})');
  } catch (e) { fail('Delete: $e'); }

  // T8: Nonexistent key
  print('\nT8: Error handling');
  final r404 = await dio.head('/$_bucket/nonexistent-xyz', options: Options(headers: auth('HEAD', '/$_bucket/nonexistent-xyz')));
  if (r404.statusCode == 404) ok('404 on missing key');
  else fail('Expected 404, got ${r404.statusCode}');

  // T9: Large object (1MB)
  print('\nT9: Large object');
  final bigKey = 'test/large-${DateTime.now().millisecondsSinceEpoch}.bin';
  final bigData = Uint8List(1024 * 1024);
  final bigHash = sha256.convert(bigData).toString();
  try {
    final swP = Stopwatch()..start();
    final extra = {'Content-Type': 'application/octet-stream', 'Content-Length': bigData.length.toString(), 'x-amz-content-sha256': bigHash};
    await dio.put('/$_bucket/$bigKey', data: Stream.value(bigData), options: Options(headers: auth('PUT', '/$_bucket/$bigKey', extra: extra, ph: bigHash)));
    final pMs = swP.elapsedMilliseconds;
    swP..reset()..start();
    final r = await dio.get('/$_bucket/$bigKey', options: Options(headers: auth('GET', '/$_bucket/$bigKey'), responseType: ResponseType.bytes));
    final gMs = swP.elapsedMilliseconds;
    ok('1MB PUT: ${pMs}ms, GET: ${gMs}ms');
    await dio.delete('/$_bucket/$bigKey', options: Options(headers: auth('DELETE', '/$_bucket/$bigKey')));
  } catch (e) { fail('Large: $e'); }

  print('\n═══ S3 Client: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
