import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'biometric/biometric_service.dart';
import 'crypto/crypto_service.dart';
import 'crypto/credential_service.dart';
import 'crypto/recovery_service.dart';
import 'network/network_guard.dart';
import 'settings/upload_settings_provider.dart';
import 'storage/s3_service.dart';
import 'upload/upload_tracker.dart';
import 'cache/thumbnail_cache.dart';
import 'ttl/ttl_engine.dart';
import 'upload/upload_service.dart';
import 'upload/backup_manager.dart';
import 'upload/backup_task.dart';
import 'device_service.dart';

/// Shared singleton services — created once, shared across all screens.
/// This ensures the CredentialService session set in SettingsScreen is
/// visible to LocalGalleryScreen's upload flow.

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final deviceServiceProvider = Provider<DeviceService>((ref) => DeviceService());

final credentialServiceProvider = Provider<CredentialService>((ref) {
  return CredentialService(
    ref.watch(cryptoServiceProvider),
    const FlutterSecureStorage(),
    biometric: LocalAuthBiometric(),
  );
});

final s3ServiceProvider = Provider<S3Service>((ref) => S3Service());

final recoveryServiceProvider = Provider<RecoveryService>((ref) {
  return RecoveryService(
    ref.watch(cryptoServiceProvider),
    ref.watch(s3ServiceProvider),
  );
});

final uploadTrackerProvider = Provider<UploadTracker>((ref) => UploadTracker());

final thumbnailCacheProvider =
    Provider<ThumbnailCache>((ref) => ThumbnailCache());

final ttlEngineProvider = Provider<TtlEngine>((ref) {
  return TtlEngine(ref.watch(uploadTrackerProvider));
});

/// Enforces the WiFi-only upload setting. [wifiOnly] is read via ref.read
/// at check time so toggling the setting mid-backup takes effect on the
/// next batch without rebuilding the manager.
final networkGuardProvider = Provider<NetworkGuard>((ref) {
  return NetworkGuard(
    probe: ConnectivityPlusProbe(),
    wifiOnly: () => ref.read(uploadSettingsProvider).wifiOnly,
  );
});

final backupManagerProvider =
    StateNotifierProvider<BackupManager, BackupTask>((ref) {
  return BackupManager(
    UploadService(
      ref.watch(cryptoServiceProvider),
      ref.watch(s3ServiceProvider),
    ),
    ref.watch(uploadTrackerProvider),
    ref.watch(thumbnailCacheProvider),
    ref.watch(credentialServiceProvider),
    ref.watch(s3ServiceProvider),
    ref.watch(deviceServiceProvider),
    ref.watch(networkGuardProvider),
  );
});

/// Incremented to signal that the KEK session state (unlock/lock) may have
/// changed, so widgets watching it rebuild to reflect the new state. Bridges
/// the non-reactive [CredentialService] session to Riverpod.
final sessionTickProvider = StateProvider<int>((ref) => 0);
