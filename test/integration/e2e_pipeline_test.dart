/// 独立 E2E 管线测试
/// Run:
///   S3_ENDPOINT=http://localhost:9000 S3_BUCKET=test \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/e2e_pipeline_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:dio/dio.dart';

void main() async {
  print('═══ Enpix E2E Pipeline Test ═══\n');

  var passed = 0, failed = 0;
  void ok(String msg) { passed++; print('  ✅ $msg'); }
  void err(String msg) { failed++; print('  ❌ $msg'); }

  final endpoint = Platform.environment['S3_ENDPOINT'] ?? 'http://localhost:9000';
  final bucket = Platform.environment['S3_BUCKET'] ?? 'test';
  final ak = Platform.environment['S3_ACCESS_KEY'] ?? '';
  final sk = Platform.environment['S3_SECRET_KEY'] ?? '';
  final region = Platform.environment['S3_REGION'] ?? 'us-east-1';

  if (ak.isEmpty || sk.isEmpty) {
    err('Set S3_ACCESS_KEY and S3_SECRET_KEY environment variables');
    print('Example: S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin dart run ...');
    return;
  }

  final dio = Dio(BaseOptions(baseUrl: endpoint, connectTimeout: const Duration(seconds: 10)));
  final blake2b = Blake2b(hashLengthInBytes: 32);
  final aead = Xchacha20.poly1305Aead();
  final argon2id = Argon2id(parallelism: 4, memory: 65536, iterations: 3, hashLength: 32);

  Uint8List rand(int n) {
    final r = Uint8List(n);
    for (int i = 0; i < n; i++) r[i] = DateTime.now().microsecond % 256;
    return r;
  }

  Future<Uint8List> deriveKek(String pw, Uint8List salt) async {
    final k = await argon2id.deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: salt);
    return Uint8List.fromList(await k.extractBytes());
  }

  Future<Uint8List> encrypt(Uint8List plain, Uint8List key, Uint8List nonce) async {
    final box = await aead.encrypt(plain, secretKey: SecretKey(key), nonce: nonce);
    final r = Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length);
    r.setAll(0, nonce); r.setAll(nonce.length, box.cipherText); r.setAll(nonce.length + box.cipherText.length, box.mac.bytes);
    return r;
  }

  Future<Uint8List> decrypt(Uint8List data, Uint8List key) async {
    final nonce = data.sublist(0, 24);
    final ct = data.sublist(24, data.length - 16);
    final mac = Mac(data.sublist(data.length - 16));
    return Uint8List.fromList(await aead.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(key)));
  }

  Future<Uint8List> wrapKey(Uint8List key, Uint8List kek) async {
    final nonce = rand(24);
    final box = await aead.encrypt(key, secretKey: SecretKey(kek), nonce: nonce);
    final r = Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length);
    r.setAll(0, nonce); r.setAll(nonce.length, box.cipherText); r.setAll(nonce.length + box.cipherText.length, box.mac.bytes);
    return r;
  }

  Future<Uint8List> unwrapKey(Uint8List wrapped, Uint8List kek) async {
    final nonce = wrapped.sublist(0, 24);
    final ct = wrapped.sublist(24, wrapped.length - 16);
    final mac = Mac(wrapped.sublist(wrapped.length - 16));
    return Uint8List.fromList(await aead.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(kek)));
  }

  // ── Helper: S3 ops with AWS Signature V4 ──
  String p2(int n) => n.toString().padLeft(2, '0');
  String uriEnc(String p) => p.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/');

  String sign(String method, String path, Map<String, String> hdrs, String payloadHash) {
    final now = DateTime.now().toUtc();
    final amzDate = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
    final dateStamp = '${now.year}${p2(now.month)}${p2(now.day)}';
    final host = Uri.parse(endpoint).host;
    final port = Uri.parse(endpoint).hasPort ? ':${Uri.parse(endpoint).port}' : '';
    final headers = <String, String>{'host': '$host$port', 'x-amz-content-sha256': payloadHash, 'x-amz-date': amzDate, ...hdrs};
    final sorted = headers.keys.toList()..sort();
    final canonicalHeaders = sorted.map((k) => '$k:${headers[k]!.trim()}').join('\n');
    final signedHeaders = sorted.join(';');
    final canonicalRequest = [method, uriEnc(path), '', '$canonicalHeaders\n', signedHeaders, payloadHash].join('\n');
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = ['AWS4-HMAC-SHA256', amzDate, credentialScope, sha256.convert(utf8.encode(canonicalRequest)).toString()].join('\n');
    final kDate = Hmac(sha256, utf8.encode('AWS4$sk')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
    final signingKey = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();
    return 'AWS4-HMAC-SHA256 Credential=$ak/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';
  }

  Options s3Opts(String method, String path, {Map<String, String>? extra, String? payloadHash}) {
    final now = DateTime.now().toUtc();
    final amzDate = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
    final host = Uri.parse(endpoint).host;
    final port = Uri.parse(endpoint).hasPort ? ':${Uri.parse(endpoint).port}' : '';
    final ph = payloadHash ?? 'UNSIGNED-PAYLOAD';
    final headers = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph, 'x-amz-date': amzDate};
    if (extra != null) headers.addAll(extra);
    headers['Authorization'] = sign(method, path, headers, ph);
    return Options(method: method, headers: headers);
  }

  Future<void> s3Put(String key, Uint8List data, {Map<String, String>? meta}) async {
    final ph = sha256.convert(data).toString();
    final extra = <String, String>{'Content-Type': 'application/octet-stream', 'Content-Length': data.length.toString()};
    if (meta != null) for (final e in meta.entries) extra['x-amz-meta-${e.key}'] = e.value;
    await dio.put('/$bucket/$key', data: Stream.value(data), options: s3Opts('PUT', '/$bucket/$key', extra: extra, payloadHash: ph));
  }

  Future<Uint8List> s3Get(String key) async {
    final r = await dio.get('/$bucket/$key', options: s3Opts('GET', '/$bucket/$key'), data: null);
    return Uint8List.fromList(r.data is List<int> ? r.data as List<int> : []);
  }

  Future<Map<String, String>> s3Head(String key) async {
    final r = await dio.head('/$bucket/$key', options: s3Opts('HEAD', '/$bucket/$key'));
    final m = <String, String>{};
    r.headers.forEach((n, v) { if (n.startsWith('x-amz-meta-')) m[n] = v.join(','); });
    return m;
  }

  Future<void> s3Delete(String key) async =>
      await dio.delete('/$bucket/$key', options: s3Opts('DELETE', '/$bucket/$key'));

  // ══════ Test 1: MinIO Connectivity ══════
  print('Test 1: MinIO Connectivity');
  try {
    await dio.head('/$bucket', options: s3Opts('HEAD', '/$bucket'));
    ok('MinIO reachable');
  } catch (e) {
    err('MinIO unreachable: $e');
    print('\n⚠️  MinIO not available. Aborting.\n');
    print('Results: $passed passed, $failed failed');
    return;
  }

  // ══════ Test 2: Crypto Roundtrip ══════
  print('\nTest 2: Crypto Roundtrip');
  final plaintext = Uint8List.fromList(utf8.encode('Enpix E2E ${DateTime.now().toIso8601String()}'));
  try {
    final salt = rand(16);
    final kek = await deriveKek('e2e-pass', salt);
    final dek = rand(32);
    final nonce = rand(24);

    final encryptedData = await encrypt(plaintext, dek, nonce);
    final decrypted = await decrypt(encryptedData, dek);
    if (utf8.decode(decrypted) == utf8.decode(plaintext)) ok('Encrypt/decrypt roundtrip');
    else err('Mismatch');

    final wrapped = await wrapKey(dek, kek);
    final unwrapped = await unwrapKey(wrapped, kek);
    if (unwrapped.length == dek.length) ok('Key wrap/unwrap roundtrip');
    else err('Key wrap mismatch');

    final hash = await blake2b.hash(plaintext);
    ok('BLAKE2b hash: ${base64Url.encode(hash.bytes).substring(0, 16)}...');
  } catch (e) {
    err('Crypto error: $e');
  }

  // ══════ Test 3: Upload Encrypted ══════
  print('\nTest 3: Upload Encrypted to S3');
  final salt = rand(16);
  final kek = await deriveKek('e2e-pass', salt);
  final dek = rand(32);
  final nonce = rand(24);
  final encryptedData = await encrypt(plaintext, dek, nonce);
  final wrappedDek = await wrapKey(dek, kek);
  final originHash = await blake2b.hash(plaintext);
  final originHashB64 = base64Url.encode(originHash.bytes);

  final date = DateTime.now();
  final s3Key = 'e2e-test/${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/test-${date.millisecondsSinceEpoch}.enc';

  try {
    final sw = Stopwatch()..start();
    await s3Put(s3Key, encryptedData, meta: {
      'dek': base64Url.encode(wrappedDek),
      'hash': originHashB64,
      'filename': 'e2e_test.txt',
    });
    ok('Upload: ${sw.elapsedMilliseconds}ms → $s3Key');
  } catch (e) {
    err('Upload failed: $e');
    print('Results: $passed passed, $failed failed');
    return;
  }

  // ══════ Test 4: Download ══════
  print('\nTest 4: Download from S3');
  try {
    final sw = Stopwatch()..start();
    final dl = await s3Get(s3Key);
    if (dl.length == encryptedData.length) ok('Download: ${sw.elapsedMilliseconds}ms, ${dl.length} bytes');
    else err('Size mismatch: ${dl.length} vs ${encryptedData.length}');
  } catch (e) {
    err('Download failed: $e');
  }

  // ══════ Test 5: Metadata ══════
  print('\nTest 5: Metadata Verification');
  try {
    final meta = await s3Head(s3Key);
    if (meta['x-amz-meta-hash'] == originHashB64) ok('Hash in metadata matches');
    else err('Hash mismatch');
  } catch (e) {
    err('HEAD failed: $e');
  }

  // ══════ Test 6: Decrypt & Integrity ══════
  print('\nTest 6: Decrypt & Integrity Check');
  try {
    final meta = await s3Head(s3Key);
    final storedWrappedDek = Uint8List.fromList(base64Url.decode(meta['x-amz-meta-dek']!));
    final recoveredDek = await unwrapKey(storedWrappedDek, kek);

    final dl = await s3Get(s3Key);
    final recovered = await decrypt(dl, recoveredDek);

    final recoveredHash = await blake2b.hash(recovered);
    final recoveredHashB64 = base64Url.encode(recoveredHash.bytes);

    if (recoveredHashB64 == originHashB64) ok('Integrity VERIFIED');
    else err('Integrity FAILED');

    if (utf8.decode(recovered) == utf8.decode(plaintext)) ok('Content byte-perfect');
    else err('Content mismatch');
  } catch (e) {
    err('Decrypt failed: $e');
  }

  // ══════ Test 7: Cleanup ══════
  print('\nTest 7: Cleanup');
  try {
    await s3Delete(s3Key);
    try { await s3Head(s3Key); err('File still exists'); } catch (_) { ok('Deleted'); }
  } catch (e) {
    err('Delete failed: $e');
  }

  // ══════ Test 8: Performance ══════
  print('\nTest 8: Performance');
  try {
    final mb = Uint8List(1024 * 1024);
    final pdek = rand(32), pnonce = rand(24);
    final swE = Stopwatch()..start();
    await encrypt(mb, pdek, pnonce);
    ok('1MB encrypt: ${swE.elapsedMilliseconds}ms');

    final swD = Stopwatch()..start();
    await argon2id.deriveKey(secretKey: SecretKey(utf8.encode('perf')), nonce: rand(16));
    ok('Argon2id(64MiB): ${swD.elapsedMilliseconds}ms');
  } catch (e) {
    err('Perf test failed: $e');
  }

  // ══════ Results ══════
  print('\n═══════════════════════════════');
  print('Results: $passed passed, $failed failed');
  print('═══════════════════════════════');
}
