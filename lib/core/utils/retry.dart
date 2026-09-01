import 'dart:async';
import 'dart:math';

/// Runs [operation] with exponential backoff retries.
///
/// - Attempts up to [maxAttempts] times in total (1 initial + retries).
/// - Retries only when [isRetryable] returns true for the thrown exception.
/// - Delay before retry N is `initialDelay * 2^(N-1)` (1s, 2s, 4s, …),
///   scaled by a jitter factor in [0.75, 1.25] to avoid thundering herds.
/// - Only [Exception] subtypes are caught — [Error]s (programming bugs)
///   propagate immediately.
/// - [sleep] and [jitter] are injectable for deterministic tests.
/// - [onRetry] is invoked before each retry sleep with the 1-based attempt
///   number that just failed, the error, and the upcoming delay.
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  required bool Function(Object error) isRetryable,
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
  double Function() jitter = _defaultJitter,
  Future<void> Function(Duration delay) sleep = _defaultSleep,
  void Function(int attempt, Object error, Duration delay)? onRetry,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await operation();
    } on Exception catch (e) {
      if (attempt >= maxAttempts || !isRetryable(e)) rethrow;
      final baseMs = initialDelay.inMilliseconds * (1 << (attempt - 1));
      final delay = Duration(
        milliseconds: (baseMs * (0.75 + 0.5 * jitter())).round(),
      );
      onRetry?.call(attempt, e, delay);
      await sleep(delay);
    }
  }
}

final _random = Random();

double _defaultJitter() => _random.nextDouble();

Future<void> _defaultSleep(Duration delay) => Future<void>.delayed(delay);
