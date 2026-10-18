import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:enpix/presentation/screens/cloud_gallery/cloud_gallery_controller.dart';
import 'package:enpix/services/cloud/cloud_media_repository.dart';
import 'package:enpix/services/cloud/photo_saver.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/storage/s3_config_service.dart';

/// Cloud object access (list, decrypt, verify, delete).
final cloudMediaRepositoryProvider = Provider<CloudMediaRepository>((ref) {
  final creds = ref.watch(credentialServiceProvider);
  return CloudMediaRepository(
    s3: ref.watch(s3ServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    sessionMasterKey: () => creds.sessionMasterKey,
    cache: (id, bytes) => ref.read(thumbnailCacheProvider).save(id, bytes),
  );
});

/// Writes decrypted photos into the system library.
final photoSaverProvider = Provider<PhotoSaver>((ref) => const GalPhotoSaver());

/// Cloud gallery state — listings, selection, delete, save-to-album.
final cloudGalleryControllerProvider =
    StateNotifierProvider<CloudGalleryController, CloudGalleryState>((ref) {
  final config = ref.watch(s3ConfigServiceProvider);
  return CloudGalleryController(
    repository: ref.watch(cloudMediaRepositoryProvider),
    photoSaver: ref.watch(photoSaverProvider),
    ensureConfigured: config.ensureConfigured,
  );
});
