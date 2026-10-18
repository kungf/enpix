import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:enpix/presentation/shared/utils/date_label.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_media_repository.dart';
import 'package:enpix/services/cloud/photo_saver.dart';
import 'package:enpix/services/storage/s3_config_service.dart';

/// Days rendered before scrolling triggers another slice.
const int kCloudVisibleDaysStep = 30;

/// Result of saving a selection back to the device.
@immutable
class CloudDownloadReport {
  const CloudDownloadReport({required this.saved, required this.failures});

  final int saved;
  final List<String> failures;

  bool get hasFailures => failures.isNotEmpty;
}

enum CloudGalleryStatus { idle, loading, ready, error }

/// Immutable snapshot of the cloud gallery.
///
/// [allDays] holds every listed day; [days] is the visible slice that grows
/// as the user scrolls.
@immutable
class CloudGalleryState {
  const CloudGalleryState({
    this.status = CloudGalleryStatus.idle,
    this.allDays = const <CloudMediaDay>[],
    this.days = const <CloudMediaDay>[],
    this.errorMessage = '',
    this.selectedKeys = const <String>{},
    this.isWorking = false,
    this.workingLabel,
  });

  final CloudGalleryStatus status;
  final List<CloudMediaDay> allDays;
  final List<CloudMediaDay> days;
  final String errorMessage;

  /// Thumbnail keys of selected items.
  final Set<String> selectedKeys;
  final bool isWorking;
  final String? workingLabel;

  bool get isLoading => status == CloudGalleryStatus.loading;
  bool get hasError => status == CloudGalleryStatus.error;
  bool get isEmpty => status == CloudGalleryStatus.ready && days.isEmpty;
  bool get isSelectionMode => selectedKeys.isNotEmpty;
  int get selectedCount => selectedKeys.length;
  bool get canLoadMore => days.length < allDays.length;

  CloudGalleryState copyWith({
    CloudGalleryStatus? status,
    List<CloudMediaDay>? allDays,
    List<CloudMediaDay>? days,
    String? errorMessage,
    Set<String>? selectedKeys,
    bool? isWorking,
    String? workingLabel,
    bool clearWorkingLabel = false,
  }) {
    return CloudGalleryState(
      status: status ?? this.status,
      allDays: allDays ?? this.allDays,
      days: days ?? this.days,
      errorMessage: errorMessage ?? this.errorMessage,
      selectedKeys: selectedKeys ?? this.selectedKeys,
      isWorking: isWorking ?? this.isWorking,
      workingLabel:
          clearWorkingLabel ? null : (workingLabel ?? this.workingLabel),
    );
  }
}

/// Ensures S3 is configured before a listing attempt.
typedef CloudConfigCheck = Future<S3ConfigResult> Function();

/// Owns cloud gallery loading, selection, delete, and save-to-album flows.
///
/// Kept out of the widget so the behaviour is testable with a fake
/// repository and photo saver.
class CloudGalleryController extends StateNotifier<CloudGalleryState> {
  CloudGalleryController({
    required CloudMediaGateway repository,
    required PhotoSaver photoSaver,
    required CloudConfigCheck ensureConfigured,
    DateTime Function() now = DateTime.now,
  })  : _repository = repository,
        _photoSaver = photoSaver,
        _ensureConfigured = ensureConfigured,
        _now = now,
        super(const CloudGalleryState());

  final CloudMediaGateway _repository;
  final PhotoSaver _photoSaver;
  final CloudConfigCheck _ensureConfigured;
  final DateTime Function() _now;

  int _visibleDays = kCloudVisibleDaysStep;

  /// Lists the cloud, replacing any previous state. Safe to call while a
  /// listing is already in flight — the second call is ignored.
  Future<void> load() async {
    if (state.isLoading) return;
    _visibleDays = kCloudVisibleDaysStep;
    state = state.copyWith(
      status: CloudGalleryStatus.loading,
      allDays: const <CloudMediaDay>[],
      days: const <CloudMediaDay>[],
      errorMessage: '',
      selectedKeys: const <String>{},
    );

    try {
      final config = await _ensureConfigured();
      if (config != S3ConfigResult.configured) {
        state = state.copyWith(
          status: CloudGalleryStatus.error,
          errorMessage: _configMessage(config),
        );
        return;
      }
      final items = await _repository.listThumbnails();
      final days = _groupByDay(items);
      state = state.copyWith(
        status: CloudGalleryStatus.ready,
        allDays: days,
        days: _visibleSlice(days),
      );
    } on Exception catch (e) {
      state = state.copyWith(
        status: CloudGalleryStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Re-lists once the session becomes usable again.
  Future<void> onSessionUnlocked() => load();

  /// Reveals another slice of days (client-side pagination).
  void showMore() {
    if (!state.canLoadMore) return;
    _visibleDays =
        (_visibleDays + kCloudVisibleDaysStep).clamp(0, state.allDays.length);
    state = state.copyWith(days: _visibleSlice(state.allDays));
  }

  void toggleSelection(String thumbnailKey) {
    final next = Set<String>.of(state.selectedKeys);
    if (!next.add(thumbnailKey)) next.remove(thumbnailKey);
    state = state.copyWith(selectedKeys: next);
  }

  void clearSelection() {
    state = state.copyWith(selectedKeys: const <String>{});
  }

  /// Selects every item in the currently visible days.
  void selectAllVisible() {
    final keys = <String>{
      for (final day in state.days)
        for (final item in day.items) item.thumbnailKey,
    };
    state = state.copyWith(selectedKeys: keys);
  }

  /// Permanently deletes the selection. Returns null when nothing to do.
  Future<CloudDeleteReport?> deleteSelected() async {
    final selected = _selectedItems();
    if (selected.isEmpty || state.isWorking) return null;

    state = state.copyWith(
      isWorking: true,
      workingLabel: '正在删除 ${selected.length} 张…',
    );
    final report = await _repository.deleteAll(selected);

    final failedKeys = <String>{
      for (final failure in report.failures) failure.media.thumbnailKey,
    };
    final removedKeys = <String>{
      for (final item in selected)
        if (!failedKeys.contains(item.thumbnailKey)) item.thumbnailKey,
    };
    final remaining = _withoutItems(state.allDays, removedKeys);

    state = state.copyWith(
      allDays: remaining,
      days: _visibleSlice(remaining),
      selectedKeys: const <String>{},
      isWorking: false,
      clearWorkingLabel: true,
    );
    return report;
  }

  /// Downloads and saves the selection to the system photo library.
  Future<CloudDownloadReport?> downloadSelected() async {
    final selected = _selectedItems();
    if (selected.isEmpty || state.isWorking) return null;

    var saved = 0;
    final failures = <String>[];
    state = state.copyWith(
      isWorking: true,
      workingLabel: _downloadLabel(0, selected.length),
    );

    for (var i = 0; i < selected.length; i++) {
      final media = selected[i];
      state = state.copyWith(
        workingLabel: _downloadLabel(i + 1, selected.length),
      );
      try {
        final content = await _repository.fetchOriginal(media);
        await _photoSaver.saveImage(
          content.bytes,
          fileName: _saveName(media, content),
        );
        saved++;
      } on Exception catch (e) {
        failures.add('${media.fileId}: $e');
      }
    }

    state = state.copyWith(
      isWorking: false,
      selectedKeys: const <String>{},
      clearWorkingLabel: true,
    );
    return CloudDownloadReport(
      saved: saved,
      failures: List<String>.unmodifiable(failures),
    );
  }

  List<CloudMedia> _selectedItems() {
    final keys = state.selectedKeys;
    return <CloudMedia>[
      for (final day in state.allDays)
        for (final item in day.items)
          if (keys.contains(item.thumbnailKey)) item,
    ];
  }

  List<CloudMediaDay> _groupByDay(List<CloudMedia> items) {
    final groups = <String, List<CloudMedia>>{};
    for (final item in items) {
      groups.putIfAbsent(item.dateKey, () => <CloudMedia>[]).add(item);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return <CloudMediaDay>[
      for (final key in keys)
        CloudMediaDay(
          dateKey: key,
          label: formatDayLabel(DateTime.parse(key), now: _now()),
          items: List<CloudMedia>.unmodifiable(groups[key]!),
        ),
    ];
  }

  List<CloudMediaDay> _visibleSlice(List<CloudMediaDay> days) =>
      List<CloudMediaDay>.unmodifiable(days.take(_visibleDays));

  /// Drops [removeKeys] and any day left empty.
  List<CloudMediaDay> _withoutItems(
    List<CloudMediaDay> days,
    Set<String> removeKeys,
  ) {
    final remaining = <CloudMediaDay>[];
    for (final day in days) {
      final items = day.items
          .where((item) => !removeKeys.contains(item.thumbnailKey))
          .toList(growable: false);
      if (items.isEmpty) continue;
      remaining.add(
        CloudMediaDay(dateKey: day.dateKey, label: day.label, items: items),
      );
    }
    return List<CloudMediaDay>.unmodifiable(remaining);
  }

  static String _downloadLabel(int current, int total) =>
      '正在保存 $current/$total…';

  /// Uses the uploaded file name when it survived truncation, otherwise a
  /// unique per-object fallback.
  static String _saveName(CloudMedia media, CloudMediaContent content) {
    var name = content.fileName?.trim() ?? '';
    if (name.endsWith('...')) {
      name = name.substring(0, name.length - 3);
    }
    return name.isEmpty ? 'enpix_${media.fileId}' : name;
  }

  static String _configMessage(S3ConfigResult result) => switch (result) {
        S3ConfigResult.missingEndpoint => '请先在设置中配置 S3 Endpoint 和 Bucket',
        S3ConfigResult.missingCredentials => '请先在设置中配置 Access Key 和 Secret Key',
        S3ConfigResult.configured => '',
      };
}
