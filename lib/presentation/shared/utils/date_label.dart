/// Human-readable day label: 今天 / 昨天 / `YYYY年M月D日`.
///
/// [now] is injectable so tests are not tied to the wall clock.
String formatDayLabel(DateTime date, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final day = _dateOnly(date);
  final difference = today.difference(day).inDays;
  if (difference == 0) return '今天';
  if (difference == 1) return '昨天';
  return '${date.year}年${date.month}月${date.day}日';
}

/// Normalizes to a UTC midnight so day differences are exact multiples of
/// 24 h — local midnights across a DST transition are 23/25 h apart and
/// `Duration.inDays` would truncate them to the wrong day.
DateTime _dateOnly(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
