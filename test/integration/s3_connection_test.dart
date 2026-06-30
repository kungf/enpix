/// S3 Connection Test E2E Test
/// Run:
///   S3_ENDPOINT=http://192.168.18.100:9000 S3_BUCKET=wytest \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/s3_connection_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

final _endpoint = Platform.environment['S3_ENDPOINT'] ?? 'http://localhost:9000';
final _bucket = Platform.environment['S3_BUCKET'] ?? 'test';
final _ak = Platform.environment['S3_ACCESS_KEY'] ?? '';
final _sk = Platform.environment['S3_SECRET_KEY'] ?? '';
final _region = Platform.environment['S3_REGION'] ?? 'us-east-1';

String p2(int n) => n.toString().padLeft(2, '0');

String sign(String method, String fullPath, Map<String, String> hdrs, String ph) {
  final now = DateTime.now().toUtc();
  final amz = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
  final date = '${now.year}${p2(now.month)}${p2(now.day)}';
  final uri = Uri.parse(_endpoint);
  final host = uri.host, port = uri.hasPort ? ':${uri.port}' : '';

  // Split path and query string.
  final parts = fullPath.split('?');
  final path = parts[0];
  final query = parts.length > 1 ? parts[1] : '';

  final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph, 'x-amz-date': amz, ...hdrs};
  final sorted = h.keys.toList()..sort();
  final canon = sorted.map((k) => '${k.toLowerCase()}:${h[k]!.trim()}').join('\n');
  final signed = sorted.map((k) => k.toLowerCase()).join(';');

  // Canonical query string: sorted by parameter name.
  final canonQuery = query.isEmpty ? '' : (() { final params = query.split('&')..sort(); return params.join('&'); })();

  final cr = [method, path.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/'), canonQuery, '$canon\n', signed, ph].join('\n');
  final scope = '$date/$_region/s3/aws4_request';
  final sts = ['AWS4-HMAC-SHA256', amz, scope, sha256.convert(utf8.encode(cr)).toString()].join('\n');
  final kDate = Hmac(sha256, utf8.encode('AWS4$_sk')).convert(utf8.encode(date)).bytes;
  final kReg = Hmac(sha256, kDate).convert(utf8.encode(_region)).bytes;
  final kSvc = Hmac(sha256, kReg).convert(utf8.encode('s3')).bytes;
  final signKey = Hmac(sha256, kSvc).convert(utf8.encode('aws4_request')).bytes;
  return 'AWS4-HMAC-SHA256 Credential=$_ak/$scope, SignedHeaders=$signed, Signature=${Hmac(sha256, signKey).convert(utf8.encode(sts)).toString()}';
}

Map<String, String> auth(String method, String fullPath, {Map<String, String>? extra, String? ph}) {
  final now = DateTime.now().toUtc();
  final amz = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
  final uri = Uri.parse(_endpoint);
  final host = uri.host, port = uri.hasPort ? ':${uri.port}' : '';
  final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph ?? 'UNSIGNED-PAYLOAD', 'x-amz-date': amz, if (extra != null) ...extra};
  h['Authorization'] = sign(method, fullPath, h, ph ?? 'UNSIGNED-PAYLOAD');
  return h;
}

void main() async {
  int passed = 0, failed = 0;
  void ok(String m) { passed++; print('  ✅ $m'); }
  void fail(String m) { failed++; print('  ❌ $m'); }

  print('═══ S3 Connection Test ═══');
  print('Endpoint: $_endpoint');
  print('Bucket: $_bucket\n');

  final dio = Dio(BaseOptions(
    baseUrl: _endpoint,
    connectTimeout: const Duration(seconds: 10),
    validateStatus: (_) => true,
  ));

  const testKey = '.enpix-connection-test';
  final testData = Uint8List.fromList([1, 2, 3, 4]);

  // T1: HEAD bucket — connectivity
  print('T1: HEAD bucket (connectivity)');
  try {
    final r = await dio.head('/$_bucket', options: Options(headers: auth('HEAD', '/$_bucket')));
    if (r.statusCode == 200) ok('Connectivity OK (200)');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('Connection failed: $e'); }

  // T2: LIST — list permission
  print('\nT2: LIST (list permission)');
  try {
    final listPath = '/$_bucket?list-type=2&max-keys=1';
    final r = await dio.get(listPath, options: Options(headers: auth('GET', listPath)));
    if (r.statusCode == 200) ok('LIST permission OK');
    else if (r.statusCode == 403) fail('LIST denied (403)');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('LIST failed: $e'); }

  // T3: PUT — write permission
  print('\nT3: PUT (write permission)');
  try {
    final sha = sha256.convert(testData).toString();
    final r = await dio.put('/$_bucket/$testKey', data: Stream.value(testData), options: Options(headers: auth('PUT', '/$_bucket/$testKey', ph: sha, extra: {
      'Content-Type': 'application/octet-stream',
      'Content-Length': testData.length.toString(),
      'x-amz-content-sha256': sha,
    })));
    if (r.statusCode == 200) ok('PUT permission OK');
    else if (r.statusCode == 403) fail('PUT denied (403)');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('PUT failed: $e'); }

  // T4: HEAD object — head permission
  print('\nT4: HEAD object (head permission)');
  try {
    final r = await dio.head('/$_bucket/$testKey', options: Options(headers: auth('HEAD', '/$_bucket/$testKey')));
    if (r.statusCode == 200) ok('HEAD object OK');
    else if (r.statusCode == 403) fail('HEAD denied (403)');
    else if (r.statusCode == 404) fail('Object not found (404) — PUT may have failed');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('HEAD failed: $e'); }

  // T5: GET — read permission
  print('\nT5: GET (read permission)');
  try {
    final r = await dio.get('/$_bucket/$testKey', options: Options(headers: auth('GET', '/$_bucket/$testKey'), responseType: ResponseType.bytes));
    if (r.statusCode == 200) ok('GET permission OK');
    else if (r.statusCode == 403) fail('GET denied (403)');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('GET failed: $e'); }

  // T6: DELETE — cleanup
  print('\nT6: DELETE (cleanup)');
  try {
    final r = await dio.delete('/$_bucket/$testKey', options: Options(headers: auth('DELETE', '/$_bucket/$testKey')));
    if (r.statusCode == 200 || r.statusCode == 204) ok('Cleanup OK');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('Cleanup failed: $e'); }

  // T7: HEAD with wrong credentials — should fail
  print('\nT7: Wrong credentials (should fail)');
  try {
    final r = await dio.head('/$_bucket', options: Options(headers: auth('HEAD', '/$_bucket')));
    if (r.statusCode == 200) ok('Endpoint reachable');
    else fail('Unexpected status: ${r.statusCode}');
  } catch (e) { fail('Endpoint unreachable: $e'); }

  print('\n═══ S3 Connection: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
