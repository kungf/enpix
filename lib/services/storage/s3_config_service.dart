import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../crypto/credential_service.dart';
import '../device_service.dart';
import '../providers.dart';
import '../../domain/entities/storage_config.dart';
import 's3_service.dart';

/// Result of [S3ConfigService.ensureConfigured].
enum S3ConfigResult {
  /// S3Service is ready for use.
  configured,

  /// Access Key / Secret Key are missing from Keychain.
  missingCredentials,

  /// Endpoint or Bucket is missing.
  missingEndpoint,
}

/// Consolidates S3 configuration: reads credentials from Keychain and
/// configures [S3Service]. Replaces the duplicated `_configureS3()` blocks
/// that previously lived inline in the local and cloud gallery screens.
///
/// Configuration is idempotent: if [S3Service.isConfigured] is already true
/// and [force] is false, returns [S3ConfigResult.configured] immediately.
class S3ConfigService {
  final Logger _log = Logger('S3ConfigService');
  final CredentialService _creds;
  final S3Service _s3;
  final DeviceService _devices;

  S3ConfigService(this._creds, this._s3, this._devices);

  /// Ensure [S3Service] is configured from Keychain credentials.
  Future<S3ConfigResult> ensureConfigured({bool force = false}) async {
    if (!force && _s3.isConfigured) return S3ConfigResult.configured;

    final s3Creds = await _creds.loadS3Credentials();
    if (s3Creds == null) return S3ConfigResult.missingCredentials;

    final endpointUrl = await _creds.getS3Endpoint() ?? '';
    final bucketName = await _creds.getS3Bucket() ?? '';
    if (endpointUrl.isEmpty || bucketName.isEmpty) {
      return S3ConfigResult.missingEndpoint;
    }

    final region = await _creds.getS3Region() ?? 'default';
    final fingerprint = await _creds.getKekFingerprint();
    final deviceId = await _devices.getDeviceId();

    _s3.configure(
      StorageConfig(
        endpointUrl: endpointUrl,
        bucketName: bucketName,
        region: region,
        accessKey: s3Creds.accessKey,
        secretKey: s3Creds.secretKey,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      kekFingerprint: fingerprint,
      deviceId: deviceId,
    );
    _log.info('S3 configured: $endpointUrl / $bucketName');
    return S3ConfigResult.configured;
  }
}

final s3ConfigServiceProvider = Provider<S3ConfigService>((ref) {
  return S3ConfigService(
    ref.watch(credentialServiceProvider),
    ref.watch(s3ServiceProvider),
    ref.watch(deviceServiceProvider),
  );
});

/// Whether S3 is set up with valid credentials in Keychain.
///
/// Pure check (no side effects) so UIs can watch it to decide between
/// "configure S3" and the gallery view. Invalidate after S3 settings change.
final s3ConfiguredProvider = FutureProvider<bool>((ref) async {
  final creds = ref.watch(credentialServiceProvider);
  final s3Creds = await creds.loadS3Credentials();
  if (s3Creds == null) return false;
  final endpoint = await creds.getS3Endpoint() ?? '';
  final bucket = await creds.getS3Bucket() ?? '';
  return endpoint.isNotEmpty && bucket.isNotEmpty;
});
