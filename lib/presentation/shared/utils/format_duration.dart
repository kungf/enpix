/// Formats a duration in seconds as `m:ss`, or `h:mm:ss` when >= 1 hour.
///
/// Example: `125` -> `2:05`, `3725` -> `1:02:05`.
String formatDuration(int seconds) {
  if (seconds < 0) seconds = 0;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$m:$ss';
}
