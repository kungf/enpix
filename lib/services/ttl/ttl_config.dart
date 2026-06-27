/// TTL engine configuration for automatic local file cleanup.
class TtlConfig {
  final bool timeEnabled;
  final int timeDays;
  final bool sizeEnabled;
  final int sizeGb;

  const TtlConfig({
    this.timeEnabled = false,
    this.timeDays = 30,
    this.sizeEnabled = false,
    this.sizeGb = 100,
  });

  bool get isEnabled => timeEnabled || sizeEnabled;

  TtlConfig copyWith({
    bool? timeEnabled,
    int? timeDays,
    bool? sizeEnabled,
    int? sizeGb,
  }) {
    return TtlConfig(
      timeEnabled: timeEnabled ?? this.timeEnabled,
      timeDays: timeDays ?? this.timeDays,
      sizeEnabled: sizeEnabled ?? this.sizeEnabled,
      sizeGb: sizeGb ?? this.sizeGb,
    );
  }

  Map<String, dynamic> toJson() => {
        'timeEnabled': timeEnabled,
        'timeDays': timeDays,
        'sizeEnabled': sizeEnabled,
        'sizeGb': sizeGb,
      };

  factory TtlConfig.fromJson(Map<String, dynamic> json) => TtlConfig(
        timeEnabled: json['timeEnabled'] as bool? ?? false,
        timeDays: json['timeDays'] as int? ?? 30,
        sizeEnabled: json['sizeEnabled'] as bool? ?? false,
        sizeGb: json['sizeGb'] as int? ?? 100,
      );

  @override
  String toString() =>
      'TtlConfig(time: ${timeEnabled ? "${timeDays}d" : "off"}, '
      'size: ${sizeEnabled ? "${sizeGb}GB" : "off"})';
}
