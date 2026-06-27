import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto/crypto_service.dart';
import 'crypto/credential_service.dart';
import 'storage/s3_service.dart';
import 'upload/upload_tracker.dart';

/// Shared singleton services — created once, shared across all screens.
/// This ensures the CredentialService session set in SettingsScreen is
/// visible to LocalGalleryScreen's upload flow.

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final credentialServiceProvider = Provider<CredentialService>((ref) {
  return CredentialService(ref.watch(cryptoServiceProvider), const FlutterSecureStorage());
});

final s3ServiceProvider = Provider<S3Service>((ref) => S3Service());

final uploadTrackerProvider = Provider<UploadTracker>((ref) => UploadTracker());
