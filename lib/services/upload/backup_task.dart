/// Backup task state model — immutable, drives UI via StateNotifier.
class BackupTask {
  final BackupStatus status;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final int skippedCount;
  final String? currentFileName;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<String> errors;

  const BackupTask({
    this.status = BackupStatus.idle,
    this.totalCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.currentFileName,
    required this.startedAt,
    this.completedAt,
    this.errors = const [],
  });

  bool get isRunning => status == BackupStatus.running;
  bool get isIdle => status == BackupStatus.idle;
  bool get isDone =>
      status == BackupStatus.completed || status == BackupStatus.stopped;

  int get processedCount => completedCount + failedCount + skippedCount;
  double get progress =>
      totalCount > 0 ? processedCount / totalCount : 0.0;

  String get progressText => '$processedCount / $totalCount';

  Duration get elapsed =>
      (completedAt ?? DateTime.now()).difference(startedAt);

  BackupTask copyWith({
    BackupStatus? status,
    int? totalCount,
    int? completedCount,
    int? failedCount,
    int? skippedCount,
    String? currentFileName,
    DateTime? completedAt,
    List<String>? errors,
  }) {
    return BackupTask(
      status: status ?? this.status,
      totalCount: totalCount ?? this.totalCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      currentFileName: currentFileName,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      errors: errors ?? this.errors,
    );
  }

  @override
  String toString() =>
      'BackupTask($status, $processedCount/$totalCount, '
      'ok=$completedCount skip=$skippedCount fail=$failedCount)';
}

enum BackupStatus { idle, running, completed, stopped }
