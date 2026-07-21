import 'package:flutter/foundation.dart';

/// User-configurable upload behavior. Persisted to Keychain as JSON.
///
/// Fields:
/// - [thresholdEnabled]: whether the age threshold filter is active.
/// - [thresholdValue]: age threshold in the unit selected by [unitHours].
///   `0` means no limit (upload everything).
/// - [unitHours]: `true` interprets [thresholdValue] as hours, `false` as days.
/// - [wifiOnly]: only upload over WiFi.
@immutable
class UploadSettings {
  final bool thresholdEnabled;
  final double thresholdValue;
  final bool unitHours;
  final bool wifiOnly;

  const UploadSettings({
    this.thresholdEnabled = true,
    this.thresholdValue = 0,
    this.unitHours = false,
    this.wifiOnly = true,
  });

  factory UploadSettings.fromJson(Map<String, dynamic> json) => UploadSettings(
        thresholdEnabled: json['thresholdEnabled'] as bool? ?? true,
        thresholdValue: (json['thresholdValue'] as num?)?.toDouble() ?? 0,
        unitHours: json['unitHours'] as bool? ?? false,
        wifiOnly: json['wifiOnly'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'thresholdEnabled': thresholdEnabled,
        'thresholdValue': thresholdValue,
        'unitHours': unitHours,
        'wifiOnly': wifiOnly,
      };

  UploadSettings copyWith({
    bool? thresholdEnabled,
    double? thresholdValue,
    bool? unitHours,
    bool? wifiOnly,
  }) =>
      UploadSettings(
        thresholdEnabled: thresholdEnabled ?? this.thresholdEnabled,
        thresholdValue: thresholdValue ?? this.thresholdValue,
        unitHours: unitHours ?? this.unitHours,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UploadSettings &&
          thresholdEnabled == other.thresholdEnabled &&
          thresholdValue == other.thresholdValue &&
          unitHours == other.unitHours &&
          wifiOnly == other.wifiOnly;

  @override
  int get hashCode => Object.hash(
        thresholdEnabled,
        thresholdValue,
        unitHours,
        wifiOnly,
      );
}
