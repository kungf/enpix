import 'dart:io';

/// E2E test configuration loaded from test/e2e/.env.e2e.
class E2EConfig {
  final String s3Endpoint;
  final String s3AccessKey;
  final String s3SecretKey;
  final String s3Bucket;
  final String s3Region;

  const E2EConfig({
    required this.s3Endpoint,
    required this.s3AccessKey,
    required this.s3SecretKey,
    required this.s3Bucket,
    this.s3Region = 'us-east-1',
  });

  /// Load config, trying .env.e2e then fallback env vars.
  static Future<E2EConfig> load() async {
    // Try .env.e2e first
    final candidates = [
      '${Directory.current.path}/test/e2e/.env.e2e',
      '.env.e2e',
    ];
    for (final file in candidates) {
      final envFile = File(file);
      if (envFile.existsSync()) {
        final lines = await envFile.readAsLines();
        final map = <String, String>{};
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx >= 0) {
            map[trimmed.substring(0, eqIdx).trim()] = trimmed.substring(eqIdx + 1).trim();
          }
        }
        return E2EConfig(
          s3Endpoint: map['S3_ENDPOINT']!,
          s3AccessKey: map['S3_ACCESS_KEY']!,
          s3SecretKey: map['S3_SECRET_KEY']!,
          s3Bucket: map['S3_BUCKET'] ?? 'enpix-e2e-test',
          s3Region: map['S3_REGION'] ?? 'us-east-1',
        );
      }
    }
    throw StateError('E2E config not found. See test/e2e/.env.e2e');
  }
}
