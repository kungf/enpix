import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bounded-concurrency, LRU-cached thumbnail loader.
///
/// Generic over the cache key so it can serve both local (asset id) and cloud
/// (S3 key) thumbnails. Callers supply the fetch logic per [load] call:
///
/// - Concurrency capped at [maxConcurrent] (default 6) so scrolling a large
///   gallery does not fan out into hundreds of parallel platform/network calls.
/// - LRU cache capped at [maxCache] entries (default 300); the least recently
///   accessed entry is evicted when the cap is exceeded.
/// - Dispose-safe: results live only in memory; nothing is written to disk.
class ThumbnailLoader<K> {
  final int maxConcurrent;
  final int _maxCache;

  ThumbnailLoader({this.maxConcurrent = 6, int maxCache = 300})
      : _maxCache = maxCache;

  final LinkedHashMap<K, Uint8List> _cache = LinkedHashMap();
  final Map<K, Future<Uint8List?>> _inFlight = {};
  final List<_Job<K>> _queue = [];
  int _running = 0;

  /// Returns the cached thumbnail for [key] if present, otherwise invokes
  /// [fetcher] (subject to the concurrency limit) and caches a non-null
  /// result. Concurrent callers for the same [key] share one in-flight fetch.
  Future<Uint8List?> load(K key, Future<Uint8List?> Function() fetcher) async {
    final cached = _cache.remove(key);
    if (cached != null) {
      // Re-insert at the MRU end (LinkedHashMap preserves insertion order).
      _cache[key] = cached;
      return cached;
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final completer = Completer<Uint8List?>();
    _inFlight[key] = completer.future;
    _enqueue(_Job(key, fetcher, completer));
    return completer.future;
  }

  void _enqueue(_Job<K> job) {
    _queue.add(job);
    _pump();
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _running++;
      _execute(job);
    }
  }

  Future<void> _execute(_Job<K> job) async {
    Uint8List? result;
    try {
      result = await job.fetcher();
    } catch (_) {
      result = null;
    }
    _running--;
    _inFlight.remove(job.key);
    if (result != null) {
      _cache[job.key] = result;
      while (_cache.length > _maxCache) {
        _cache.remove(_cache.keys.first);
      }
    }
    if (!job.completer.isCompleted) {
      job.completer.complete(result);
    }
    _pump();
  }
}

class _Job<K> {
  final K key;
  final Future<Uint8List?> Function() fetcher;
  final Completer<Uint8List?> completer;

  _Job(this.key, this.fetcher, this.completer);
}

/// Throttled LRU cache for local asset thumbnails (key = asset id).
final localThumbnailLoaderProvider =
    Provider<ThumbnailLoader<String>>((ref) => ThumbnailLoader<String>());

/// Throttled LRU cache for cloud thumbnails (key = S3 object key).
final cloudThumbnailLoaderProvider =
    Provider<ThumbnailLoader<String>>((ref) => ThumbnailLoader<String>());
