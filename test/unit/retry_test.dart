import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/core/utils/retry.dart';
import 'package:enpix/services/storage/s3_service.dart';

void main() {
  /// Sleep that resolves immediately and records requested delays.
  Future<void> Function(Duration) recordingSleep(List<Duration> log) =>
      (Duration d) async => log.add(d);

  group('withRetry', () {
    test('returns result on first success without sleeping', () async {
      final delays = <Duration>[];
      var attempts = 0;

      final result = await withRetry(
        () async => ++attempts,
        isRetryable: (_) => true,
        sleep: recordingSleep(delays),
      );

      expect(result, 1);
      expect(attempts, 1);
      expect(delays, isEmpty);
    });

    test('retries a retryable error and returns the eventual success',
        () async {
      final delays = <Duration>[];
      var attempts = 0;

      final result = await withRetry(
        () async {
          attempts++;
          if (attempts < 3) throw Exception('transient');
          return 'ok';
        },
        isRetryable: (_) => true,
        jitter: () => 0.5, // deterministic: delay factor = 1.0
        sleep: recordingSleep(delays),
      );

      expect(result, 'ok');
      expect(attempts, 3);
      // Exponential backoff: 1s then 2s (jitter 0.5 → factor 1.0).
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('rethrows the last error after exhausting attempts', () async {
      final delays = <Duration>[];
      var attempts = 0;

      await expectLater(
        withRetry(
          () async {
            attempts++;
            throw Exception('boom $attempts');
          },
          isRetryable: (_) => true,
          maxAttempts: 4,
          jitter: () => 0.5,
          sleep: recordingSleep(delays),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('boom 4'),
          ),
        ),
      );
      expect(attempts, 4);
      expect(delays.length, 3); // no sleep before the first attempt
    });

    test('does not retry a non-retryable error', () async {
      final delays = <Duration>[];
      var attempts = 0;

      await expectLater(
        withRetry(
          () async {
            attempts++;
            throw Exception('fatal');
          },
          isRetryable: (_) => false,
          sleep: recordingSleep(delays),
        ),
        throwsException,
      );
      expect(attempts, 1);
      expect(delays, isEmpty);
    });

    test('reports each retry via onRetry with growing delays', () async {
      final retries = <(int, Duration)>[];
      var attempts = 0;

      await expectLater(
        withRetry(
          () async {
            attempts++;
            throw Exception('always');
          },
          isRetryable: (_) => true,
          maxAttempts: 3,
          jitter: () => 0.5,
          sleep: (d) async {},
          onRetry: (attempt, error, delay) => retries.add((attempt, delay)),
        ),
        throwsException,
      );

      expect(retries, [
        (1, const Duration(seconds: 1)),
        (2, const Duration(seconds: 2)),
      ]);
    });

    test('jitter scales the delay within ±25%', () async {
      final delays = <Duration>[];
      var attempts = 0;

      await expectLater(
        withRetry(
          () async {
            attempts++;
            throw Exception('x');
          },
          isRetryable: (_) => true,
          maxAttempts: 2,
          jitter: () => 0.0, // factor 0.75
          sleep: recordingSleep(delays),
        ),
        throwsException,
      );
      expect(delays.single.inMilliseconds, 750);
    });
  });

  group('S3Service.isRetryable', () {
    DioException dioError(int? statusCode) => DioException(
          requestOptions: RequestOptions(),
          response: statusCode == null
              ? null
              : Response(
                  requestOptions: RequestOptions(),
                  statusCode: statusCode,
                ),
        );

    test('network failure without response is retryable', () {
      expect(S3Service.isRetryable(dioError(null)), isTrue);
    });

    test('5xx server errors are retryable', () {
      expect(S3Service.isRetryable(dioError(500)), isTrue);
      expect(S3Service.isRetryable(dioError(503)), isTrue);
    });

    test('429 rate limit is retryable', () {
      expect(S3Service.isRetryable(dioError(429)), isTrue);
    });

    test('4xx client errors are not retryable', () {
      expect(S3Service.isRetryable(dioError(400)), isFalse);
      expect(S3Service.isRetryable(dioError(403)), isFalse);
      expect(S3Service.isRetryable(dioError(404)), isFalse);
    });

    test('unwraps StorageException cause', () {
      final wrapped = StorageException(
        message: 'PUT failed',
        cause: dioError(503),
      );
      expect(S3Service.isRetryable(wrapped), isTrue);

      final wrappedFatal = StorageException(
        message: 'PUT failed',
        cause: dioError(403),
      );
      expect(S3Service.isRetryable(wrappedFatal), isFalse);
    });

    test('non-Dio errors are not retryable', () {
      expect(S3Service.isRetryable(Exception('other')), isFalse);
      expect(
        S3Service.isRetryable(const StorageException(message: 'x')),
        isFalse,
      );
    });
  });
}
