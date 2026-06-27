class AppConstants {
  AppConstants._();
  static const String appName = 'See-Photo';
  static const String appVersion = '0.1.0';
  static const int defaultTimeTtlDays = 30;
  static const double defaultSizeThresholdGb = 100.0;
  static const int defaultChunkSizeBytes = 8 * 1024 * 1024;
  static const int thumbnailMaxWidth = 512;
  static const int thumbnailMaxHeight = 512;
  static const int thumbnailQuality = 75;
  static const double defaultCacheMaxSizeGb = 2.0;
  static const int s3MultipartMinSizeBytes = 16 * 1024 * 1024;
  static const int s3MultipartPartSizeBytes = 8 * 1024 * 1024;

  /// True in integration test mode, skips photo permission dialog.
  static const bool isIntegrationTest = bool.fromEnvironment('INTEGRATION_TEST');
}
