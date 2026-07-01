import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto/crypto_service.dart';
import 'crypto/credential_service.dart';
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
  return CredentialService(ref.watch(cryptoServiceProvider), const FlutterSecureStorage());
});

final s3ServiceProvider = Provider<S3Service>((ref) => S3Service());

final uploadTrackerProvider = Provider<UploadTracker>((ref) => UploadTracker());

final thumbnailCacheProvider = Provider<ThumbnailCache>((ref) => ThumbnailCache());

final ttlEngineProvider = Provider<TtlEngine>((ref) {
  return TtlEngine(ref.watch(uploadTrackerProvider));
});

final backupManagerProvider = StateNotifierProvider<BackupManager, BackupTask>((ref) {
  return BackupManager(
    UploadService(
      ref.watch(cryptoServiceProvider),
      ref.watch(credentialServiceProvider),
      ref.watch(s3ServiceProvider),
    ),
    ref.watch(uploadTrackerProvider),
    ref.watch(thumbnailCacheProvider),
    ref.watch(credentialServiceProvider),
    ref.watch(s3ServiceProvider),
    ref.watch(deviceServiceProvider),
  );
});
