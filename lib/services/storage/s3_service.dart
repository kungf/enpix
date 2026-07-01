import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';
import '../../core/errors/storage_exception.dart';
import '../../domain/entities/storage_config.dart';

class S3Service {
  final Logger _log = Logger('S3Service');
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 300)));
  StorageConfig? _config;
  String? _kekFingerprint;

  void configure(StorageConfig config, {String? kekFingerprint}) {
    _log.info('Configuring S3: ${config.endpointUrl} / ${config.bucketName}');
    _config = config;
    _kekFingerprint = kekFingerprint;
    _dio.options.baseUrl = config.endpointUrl;
  }

  bool get isConfigured => _config != null;

  // ── Path helpers ──

  static String generateKey(String fingerprint, String fileId, DateTime createdAt) {
    final prefix = fingerprint.length >= 12 ? fingerprint.substring(0, 12) : 'shared';
    final y = createdAt.year.toString();
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    return '$prefix/files/$y/$m/$d/$fileId.enc';
  }

  String makeKey(String fileId, DateTime createdAt) {
    return generateKey(_kekFingerprint ?? 'shared', fileId, createdAt);
  }

  /// Generate S3 key for a thumbnail.
  static String generateThumbKey(String fingerprint, String fileId) {
    final prefix = fingerprint.length >= 12 ? fingerprint.substring(0, 12) : 'shared';
    return '$prefix/thumbs/$fileId\_thumb.enc';
  }

  String makeThumbKey(String fileId) {
    return generateThumbKey(_kekFingerprint ?? 'shared', fileId);
  }

  // ── HTTP operations ──

  /// Test S3 connection and required permissions (HEAD, LIST, PUT, GET).
  /// Returns a message describing the result. Throws on failure.
  Future<String> testConnection() async {
    _ensureConfigured();
    final bucket = _config!.bucketName;
    const testKey = '.enpix-connection-test';
    final testData = Uint8List.fromList([1, 2, 3, 4]);

    // 1. HEAD bucket — test connectivity.
    try {
      await _dio.head('/$bucket', options: _signedOptions('HEAD', '/$bucket'));
    } on Exception catch (e) {
      throw StorageException(message: '无法连接: $e', cause: e);
    }

    // 2. LIST — test list permission.
    try {
      final listPath = '/$bucket?list-type=2&max-keys=1';
      await _dio.get(listPath, options: _signedOptions('GET', listPath));
    } on Exception catch (e) {
      throw StorageException(message: '无 LIST 权限: $e', cause: e);
    }

    // 3. PUT — test write permission.
    try {
      final sha = sha256.convert(testData).toString();
      final objPath = '/$bucket/$testKey';
      await _dio.put(objPath, data: Stream.value(testData), options: _signedOptions('PUT', objPath, headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': testData.length.toString(),
        'x-amz-content-sha256': sha,
      }, payloadHash: sha));
    } on Exception catch (e) {
      throw StorageException(message: '无写入权限: $e', cause: e);
    }

    // 4. HEAD object — test head permission.
    try {
      final objPath = '/$bucket/$testKey';
      await _dio.head(objPath, options: _signedOptions('HEAD', objPath));
    } on Exception catch (e) {
      throw StorageException(message: '无 HEAD 权限: $e', cause: e);
    }

    // 5. GET — test read permission.
    try {
      final objPath = '/$bucket/$testKey';
      await _dio.get(objPath, options: _signedOptions('GET', objPath));
    } on Exception catch (e) {
      throw StorageException(message: '无读取权限: $e', cause: e);
    }

    // 6. Cleanup.
    try {
      final objPath = '/$bucket/$testKey';
      await _dio.delete(objPath, options: _signedOptions('DELETE', objPath));
    } catch (_) {}

    return '连接成功，权限正常';
  }

  Future<void> putObject(String key, Uint8List data, {Map<String, String>? metadata, String? contentType}) async {
    _ensureConfigured();
    _log.info('PUT $key (${data.length} bytes)');
    try {
      final body = data;
      final sha = sha256.convert(body).toString();
      final extraHeaders = <String, String>{
        'Content-Type': contentType ?? 'application/octet-stream',
        'Content-Length': body.length.toString(),
        'x-amz-content-sha256': sha,
      };
      if (metadata != null) {
        for (final e in metadata.entries) {
          extraHeaders['x-amz-meta-${e.key}'] = e.value;
        }
      }
      await _dio.put('/${_config!.bucketName}/$key', data: Stream.value(body), options: _signedOptions('PUT', '/${_config!.bucketName}/$key', headers: extraHeaders, payloadHash: sha));
    } catch (e) {
      throw StorageException(message: 'PUT failed: $key — $e', cause: e);
    }
  }

  Future<Uint8List> getObject(String key) async {
    _ensureConfigured();
    try {
      final path = '/${_config!.bucketName}/$key';
      final r = await _dio.get(path, options: _signedOptions('GET', path));
      return Uint8List.fromList(r.data is List<int> ? r.data as List<int> : []);
    } catch (e) {
      throw StorageException(message: 'GET failed: $key — $e', cause: e);
    }
  }

  Future<Map<String, String>> headObject(String key) async {
    _ensureConfigured();
    try {
      final path = '/${_config!.bucketName}/$key';
      final r = await _dio.head(path, options: _signedOptions('HEAD', path));
      final meta = <String, String>{};
      r.headers.forEach((n, v) { if (n.startsWith('x-amz-meta-')) meta[n] = v.join(','); });
      return meta;
    } catch (e) {
      throw StorageException(message: 'HEAD failed: $key — $e', cause: e);
    }
  }

  Future<void> deleteObject(String key) async {
    _ensureConfigured();
    try {
      final path = '/${_config!.bucketName}/$key';
      await _dio.delete(path, options: _signedOptions('DELETE', path));
      _log.info('DELETED: $key');
    } catch (e) {
      throw StorageException(message: 'DELETE failed: $key — $e', cause: e);
    }
  }

  /// List objects under [prefix]. Returns all matching objects (paginated internally).
  Future<List<S3Object>> listObjects(String prefix) async {
    _ensureConfigured();
    final results = <S3Object>[];
    String? continuationToken;

    do {
      final queryParts = <String>[
        'list-type=2',
        'prefix=$prefix',
        'max-keys=1000',
      ];
      if (continuationToken != null) {
        queryParts.add('continuation-token=${Uri.encodeComponent(continuationToken)}');
      }
      // Sort for consistent signing.
      queryParts.sort();
      final query = queryParts.join('&');
      final path = '/${_config!.bucketName}?$query';

      try {
        final r = await _dio.get(path, options: _signedOptions('GET', path));
        final body = r.data is String ? r.data as String : r.data.toString();
        final doc = XmlDocument.parse(body);

        final listBucketResult = doc.getElement('ListBucketResult');
        if (listBucketResult == null) break;

        final isTruncated = listBucketResult.getElement('IsTruncated')?.innerText == 'true';
        continuationToken = isTruncated
            ? listBucketResult.getElement('NextContinuationToken')?.innerText
            : null;

        for (final contents in listBucketResult.findAllElements('Contents')) {
          final key = contents.getElement('Key')?.innerText ?? '';
          final size = int.tryParse(contents.getElement('Size')?.innerText ?? '0') ?? 0;
          final lastModified = contents.getElement('LastModified')?.innerText ?? '';
          if (key.endsWith('/')) continue; // skip folder markers
          results.add(S3Object(key: key, size: size, lastModified: lastModified));
        }
      } catch (e) {
        throw StorageException(message: 'LIST failed: prefix=$prefix — $e', cause: e);
      }
    } while (continuationToken != null);

    _log.info('LISTED ${results.length} objects under $prefix');
    return results;
  }

  // ── AWS Signature V4 ──

  Options _signedOptions(String method, String path, {Map<String, String>? headers, String? payloadHash}) {
    final cfg = _config!;
    final host = Uri.parse(cfg.endpointUrl).host;
    final port = Uri.parse(cfg.endpointUrl).hasPort ? ':${Uri.parse(cfg.endpointUrl).port}' : '';
    final now = DateTime.now().toUtc();
    final amzDate = _fmt(now);
    final dateStamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final service = 's3';
    final region = cfg.region.isNotEmpty ? cfg.region : 'default';
    final contentSha256 = payloadHash ?? 'UNSIGNED-PAYLOAD';

    // Canonical headers (sorted alphabetically)
    final signedHdrs = <String, String>{'host': '$host$port'};
    if (headers != null) signedHdrs.addAll(headers);
    signedHdrs['x-amz-content-sha256'] = contentSha256;
    signedHdrs['x-amz-date'] = amzDate;

    final sortedKeys = signedHdrs.keys.toList()..sort();
    final canonicalHeaders = sortedKeys.map((k) => '${k.toLowerCase()}:${signedHdrs[k]!.trim()}').join('\n');
    final signedHeadersStr = sortedKeys.map((k) => k.toLowerCase()).join(';');

    // Canonical request — split path and query string.
    // Encode query values to match Dio's URL encoding behavior.
    final parts = path.split('?');
    final canonicalPath = _uriEncodePath(parts[0]);
    var canonicalQuery = '';
    if (parts.length > 1) {
      final params = parts[1].split('&').map((p) {
        final eqIdx = p.indexOf('=');
        if (eqIdx >= 0) {
          final key = p.substring(0, eqIdx);
          final val = p.substring(eqIdx + 1);
          return '$key=${Uri.encodeComponent(val)}';
        }
        return p;
      }).toList()
        ..sort();
      canonicalQuery = params.join('&');
    }

    final canonicalRequest = [
      method,
      canonicalPath,
      canonicalQuery,
      '$canonicalHeaders\n',
      signedHeadersStr,
      contentSha256,
    ].join('\n');

    // String to sign
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // Signing key
    final kDate = Hmac(sha256, utf8.encode('AWS4${cfg.secretKey}')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode(service)).bytes;
    final signingKey = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;

    // Signature
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    // Authorization header
    final authHeader = '$algorithm Credential=${cfg.accessKey}/$credentialScope, SignedHeaders=$signedHeadersStr, Signature=$signature';

    return Options(method: method, headers: {
      ...signedHdrs,
      'Authorization': authHeader,
      'Content-Type': headers?['Content-Type'] ?? 'application/octet-stream',
    });
  }

  String _uriEncodePath(String path) {
    return path.split('/').map((seg) => seg.isEmpty ? '' : Uri.encodeComponent(seg)).join('/');
  }

  String _fmt(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}'
        'T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}Z';
  }

  void _ensureConfigured() {
    if (_config == null) throw StorageNotConfiguredException();
  }
}

/// Minimal representation of an S3 object from ListObjects.
class S3Object {
  final String key;
  final int size;
  final String lastModified;

  const S3Object({required this.key, required this.size, required this.lastModified});
}
