import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import '../crypto/credential_service.dart';
import '../device_service.dart';
import '../storage/s3_service.dart';
import '../cache/thumbnail_cache.dart';
import 'upload_service.dart';
import 'upload_tracker.dart';
import 'backup_task.dart';

/// Manages backup tasks with progress tracking.
///
/// Exposes [state] as [BackupTask] for UI to watch.
/// Only one backup can run at a time — calling [start] while running is a no-op.
class BackupManager extends StateNotifier<BackupTask> {
  final Logger _log = Logger('BackupManager');
  final UploadService _uploader;
  final UploadTracker _tracker;
  final ThumbnailCache _cache;
  final CredentialService _credService;
  final S3Service _s3;
  final DeviceService _deviceService;

  bool _cancelled = false;

  BackupManager(
    this._uploader,
    this._tracker,
    this._cache,
    this._credService,
    this._s3,
    this._deviceService,
  ) : super(BackupTask(startedAt: DateTime.now()));

  /// Start a force-full backup — re-uploads everything regardless of S3 state.
  Future<void> startForceFull() async {
    await _startFull(force: true);
  }

  /// Start a backup with full scan (incremental).
  /// Uses local manifest to find boundary — uploads all photos newer than the first uploaded one.
  Future<void> startFull() async {
    await _startFull(force: false);
  }

  Future<void> _startFull({required bool force}) async {
    if (state.isRunning) {
      _log.warning('Backup already running, ignoring');
      return;
    }

    _cancelled = false;

    state = BackupTask(
      status: BackupStatus.running,
      totalCount: 0,
      startedAt: DateTime.now(),
      currentFileName: '扫描照片...',
    );

    // Register this device in S3 (idempotent — overwrites if exists).
    try {
      final deviceId = await _deviceService.getDeviceId();
      final deviceName = await _deviceService.getDeviceName();
      _s3.setDeviceId(deviceId);
      await _s3.registerDevice(deviceId, deviceName);
    } catch (e) {
      _log.warning('Device registration failed (non-fatal): $e');
    }

    // Scan local photos (newest first).
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );
    if (albums.isEmpty) {
      state = state.copyWith(status: BackupStatus.completed, completedAt: DateTime.now());
      return;
    }

    final allAssets = <AssetEntity>[];
    const pageSize = 200;
    int page = 0;
    while (!_cancelled) {
      final assets = await albums[0].getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) break;
      allAssets.addAll(assets);
      page++;
    }

    if (_cancelled) {
      state = state.copyWith(status: BackupStatus.stopped, completedAt: DateTime.now());
      return;
    }

    // Find pending photos using manifest.
    // Scan all photos, collect those not in manifest.
    // This handles gaps from old time-based code or interrupted backups.
    final pending = <AssetEntity>[];
    if (force) {
      pending.addAll(allAssets);
    } else {
      for (final asset in allAssets) {
        if (!await _tracker.isUploaded(asset.id)) {
          pending.add(asset);
        }
      }
    }

    // Reverse to upload oldest first.
    final toUpload = pending.reversed.toList();

    _log.info('Found ${toUpload.length} new photos to backup');
    await _doBackup(toUpload);
  }

  /// Start a backup with a pre-loaded list of assets.
  Future<void> start(List<AssetEntity> assets) async {
    if (state.isRunning) {
      _log.warning('Backup already running, ignoring');
      return;
    }

    _cancelled = false;

    // Ensure deviceId is set for key generation.
    final deviceId = await _deviceService.getDeviceId();
    _s3.setDeviceId(deviceId);

    // Pre-filter: remove already-uploaded assets.
    final pending = <AssetEntity>[];
    for (final asset in assets) {
      if (!await _tracker.isUploaded(asset.id)) {
        pending.add(asset);
      }
    }

    await _doBackup(pending);
  }

  /// Core backup loop.
  Future<void> _doBackup(List<AssetEntity> pending) async {
    final totalSkipped = await _tracker.uploadedCount;

    state = BackupTask(
      status: BackupStatus.running,
      totalCount: pending.length,
      skippedCount: 0,
      startedAt: DateTime.now(),
    );

    _log.info('Backup started: ${pending.length} pending, $totalSkipped total already uploaded');

    int completed = 0, failed = 0;
    final errors = <String>[];

    for (final asset in pending) {
      if (_cancelled) break;

      final fileName = asset.title ?? 'photo';
      state = state.copyWith(currentFileName: fileName);

      // Get file
      final file = await asset.originFile;
      if (file == null || !file.existsSync()) {
        failed++;
        errors.add('文件不存在: $fileName');
        state = state.copyWith(failedCount: failed, errors: errors);
        continue;
      }

      // Upload
      try {
        final result = await _uploader.upload(
          localPath: file.path,
          fileName: fileName,
          mimeType: asset.mimeType ?? 'image/jpeg',
          createdAt: asset.createDateTime,
          kek: _credService.sessionKek!,
        );

        if (result.success) {
          await _tracker.markUploaded(asset.id);
          if (result.thumbData != null) {
            await _cache.save(asset.id, result.thumbData!);
          }
          completed++;
        } else {
          failed++;
          errors.add(result.error ?? '上传失败');
        }
      } catch (e) {
        failed++;
        errors.add('$fileName: $e');
      }

      state = state.copyWith(
        completedCount: completed,
        failedCount: failed,
        errors: errors,
      );
    }

    // Persist upload records after batch.
    await _tracker.save();

    final finalStatus =
        _cancelled ? BackupStatus.stopped : BackupStatus.completed;
    state = state.copyWith(
      status: finalStatus,
      completedAt: DateTime.now(),
      currentFileName: null,
    );

    _log.info('Backup finished: $state');
  }

  /// Stop the current backup.
  void stop() {
    if (!state.isRunning) return;
    _cancelled = true;
    _log.info('Backup stopped by user');
  }

  /// Reset to idle state.
  void reset() {
    if (state.isRunning) return;
    state = BackupTask(startedAt: DateTime.now());
  }
}
