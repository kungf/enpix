/// E2E Upload Pipeline Test
/// Run:
///   S3_ENDPOINT=http://localhost:9000 S3_BUCKET=test \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/upload_pipeline_test.dart

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

// ── Shared helpers ──
String p2(int n) => n.toString().padLeft(2, '0');
Uint8List rnd(int n) { final r = Uint8List(n); for (int i = 0; i < n; i++) r[i] = (DateTime.now().microsecond + i) % 256; return r; }

String sign(String method, String path, Map<String, String> hdrs, String ph) {
  final now = DateTime.now().toUtc();
  final amz = '${now.year}${p2(now.month)}${p2(now.day)}T${p2(now.hour)}${p2(now.minute)}${p2(now.second)}Z';
  final date = '${now.year}${p2(now.month)}${p2(now.day)}';
  final host = Uri.parse(_endpoint).host, port = Uri.parse(_endpoint).hasPort ? ':${Uri.parse(_endpoint).port}' : '';
  final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph, 'x-amz-date': amz, ...hdrs};
  final sorted = h.keys.toList()..sort();
  final canon = sorted.map((k) => '${k.toLowerCase()}:${h[k]!.trim()}').join('\n');
  final signed = sorted.map((k) => k.toLowerCase()).join(';');
  final cr = [method, path.split('/').map((s) => s.isEmpty ? '' : Uri.encodeComponent(s)).join('/'), '', '$canon\n', signed, ph].join('\n');
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
  final host = Uri.parse(_endpoint).host, port = Uri.parse(_endpoint).hasPort ? ':${Uri.parse(_endpoint).port}' : '';
  final h = <String, String>{'Host': '$host$port', 'x-amz-content-sha256': ph ?? 'UNSIGNED-PAYLOAD', 'x-amz-date': amz, if (extra != null) ...extra};
  h['Authorization'] = sign(method, path, h, ph ?? 'UNSIGNED-PAYLOAD');
  return h;
}

void main() async {
  int passed = 0, failed = 0;
  void ok(String m) { passed++; print('  ✅ $m'); }
  void fail(String m) { failed++; print('  ❌ $m'); }

  print('═══ Upload Pipeline Test ═══\n');

  final blake2b = Blake2b(hashLengthInBytes: 32);
  final aead = Xchacha20.poly1305Aead();
  final argon2id = Argon2id(parallelism: 4, memory: 65536, iterations: 3, hashLength: 32);

  Future<Uint8List> deriveKek(String pw, Uint8List s) async { final k = await argon2id.deriveKey(secretKey: SecretKey(utf8.encode(pw)), nonce: s); return Uint8List.fromList(await k.extractBytes()); }
  Future<Uint8List> enc(Uint8List p, Uint8List k, Uint8List n) async { final b = await aead.encrypt(p, secretKey: SecretKey(k), nonce: n); final r = Uint8List(n.length + b.cipherText.length + b.mac.bytes.length); r.setAll(0, n); r.setAll(n.length, b.cipherText); r.setAll(n.length + b.cipherText.length, b.mac.bytes); return r; }
  Future<Uint8List> dec(Uint8List d, Uint8List k) async { final n = d.sublist(0, 24); final c = d.sublist(24, d.length - 16); final m = Mac(d.sublist(d.length - 16)); return Uint8List.fromList(await aead.decrypt(SecretBox(c, nonce: n, mac: m), secretKey: SecretKey(k))); }

  final dio = Dio(BaseOptions(baseUrl: _endpoint, connectTimeout: const Duration(seconds: 10), validateStatus: (_) => true));

  Future<void> s3Put(String key, Uint8List data, {Map<String, String>? meta}) async {
    final ph = sha256.convert(data).toString();
    final extra = <String, String>{'Content-Type': 'application/octet-stream', 'Content-Length': data.length.toString()};
    if (meta != null) for (final e in meta.entries) extra['x-amz-meta-${e.key}'] = e.value;
    final r = await dio.put('/$_bucket/$key', data: Stream.value(data), options: Options(headers: auth('PUT', '/$_bucket/$key', extra: extra, ph: ph)));
    if (r.statusCode != 200) throw Exception('PUT ${r.statusCode}');
  }

  Future<Uint8List> s3Get(String key) async {
    final r = await dio.get('/$_bucket/$key', options: Options(headers: auth('GET', '/$_bucket/$key'), responseType: ResponseType.bytes));
    if (r.statusCode != 200) throw Exception('GET ${r.statusCode}');
    return Uint8List.fromList(List<int>.from(r.data));
  }

  Future<Map<String, String>> s3Head(String key) async {
    final r = await dio.head('/$_bucket/$key', options: Options(headers: auth('HEAD', '/$_bucket/$key')));
    if (r.statusCode != 200) throw Exception('HEAD ${r.statusCode}');
    final m = <String, String>{}; r.headers.forEach((n, v) { if (n.startsWith('x-amz-meta-')) m[n] = v.join(','); }); return m;
  }

  // ── Setup ──
  final salt = Uint8List(16);
  for (int i = 0; i < 16; i++) salt[i] = i + 1;
  final kek = await deriveKek('pipeline-test-pass', salt);
  final plaintext = Uint8List.fromList(utf8.encode('See-Photo Pipeline: ${DateTime.now().toIso8601String()}'));

  // T1: Crypto roundtrip
  print('T1: Crypto Roundtrip');
  try {
    final dek = rnd(32);
    final e = await enc(plaintext, dek, rnd(24));
    final d = await dec(e, dek);
    if (utf8.decode(d) == utf8.decode(plaintext)) ok('Encrypt/decrypt OK');
    else fail('Mismatch');
    final w = await enc(dek, kek, rnd(24));
    final u = await dec(w, kek);
    if (u.length == dek.length) ok('Key wrap/unwrap OK');
    else fail('Key mismatch');
  } catch (e) { fail('Crypto: $e'); }

  // T2: Encrypt & Upload
  print('\nT2: Encrypt & Upload');
  final origHash = await blake2b.hash(plaintext);
  final origHashB64 = base64Url.encode(origHash.bytes);
  final dek = rnd(32), nonce = rnd(24);
  final encrypted = await enc(plaintext, dek, nonce);
  final wrappedDek = await enc(dek, kek, rnd(24));
  final date = DateTime.now();
  final s3Key = 'test-pipeline/${date.year}/${p2(date.month)}/${p2(date.day)}/pipe-${date.millisecondsSinceEpoch}.enc';

  try {
    final sw = Stopwatch()..start();
    await s3Put(s3Key, encrypted, meta: {'dek': base64Url.encode(wrappedDek), 'hash': origHashB64});
    ok('Upload: ${sw.elapsedMilliseconds}ms, ${encrypted.length}B');
  } catch (e) { fail('Upload: $e'); }

  // T3: Download & Decrypt & Verify
  print('\nT3: Download → Decrypt → Verify');
  try {
    final meta = await s3Head(s3Key);
    final dl = await s3Get(s3Key);
    final wDek = Uint8List.fromList(base64Url.decode(meta['x-amz-meta-dek']!));
    final rDek = await dec(wDek, kek);
    final recovered = await dec(dl, rDek);
    final rHash = await blake2b.hash(recovered);
    if (base64Url.encode(rHash.bytes) == origHashB64) ok('Integrity VERIFIED');
    else fail('Integrity FAILED');
    if (utf8.decode(recovered) == utf8.decode(plaintext)) ok('Content byte-perfect');
    else fail('Content mismatch');
  } catch (e) { fail('Download/decrypt: $e'); }

  // T4: Hash verification only
  print('\nT4: Hash Verification');
  try {
    final meta = await s3Head(s3Key);
    if (meta['x-amz-meta-hash'] == origHashB64) ok('Stored hash matches');
    else fail('Hash mismatch');
  } catch (e) { fail('Hash check: $e'); }

  // T5: Cleanup
  print('\nT5: Cleanup');
  try {
    await dio.delete('/$_bucket/$s3Key', options: Options(headers: auth('DELETE', '/$_bucket/$s3Key')));
    ok('Cleaned up');
  } catch (e) { fail('Cleanup: $e'); }

  // T6: Wrong key detection
  print('\nT6: Wrong Key Detection');
  try {
    final wrongDek = rnd(32);
    try { await dec(encrypted, wrongDek); fail('Should reject wrong key'); } catch (_) { ok('Wrong key rejected'); }
  } catch (e) { fail('Wrong key test: $e'); }

  // T7: Performance
  print('\nT7: Performance');
  try {
    final mb = Uint8List(1024 * 1024);
    final pDek = rnd(32), pNonce = rnd(24);
    final sw = Stopwatch()..start();
    await enc(mb, pDek, pNonce);
    ok('1MB encrypt: ${sw.elapsedMilliseconds}ms');
    sw..reset()..start();
    await argon2id.deriveKey(secretKey: SecretKey(utf8.encode('bench')), nonce: Uint8List(16));
    ok('Argon2id(64MiB): ${sw.elapsedMilliseconds}ms');
  } catch (e) { fail('Perf: $e'); }

  print('\n═══ Upload Pipeline: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
