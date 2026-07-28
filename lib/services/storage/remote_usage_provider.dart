import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../providers.dart';
import 's3_config_service.dart';

/// Total bytes used in S3 for this user, aggregated by listing every object
/// under the enpix/ prefix and summing sizes.
///
/// autoDispose so re-entering the overview tab re-fetches fresh data.
/// Pull-to-refresh invalidates it explicitly. Returns 0 when S3 is not
/// configured (the UI watches [s3ConfiguredProvider] to distinguish that case).
final remoteUsageProvider = FutureProvider.autoDispose<int>((ref) async {
  final configured = await ref.watch(s3ConfiguredProvider.future);
  if (!configured) return 0;

  final result = await ref.watch(s3ConfigServiceProvider).ensureConfigured();
  if (result != S3ConfigResult.configured) return 0;

  final s3 = ref.watch(s3ServiceProvider);

  final log = Logger('remoteUsageProvider');
  try {
    final objects = await s3.listObjects('enpix/');
    var total = 0;
    for (final o in objects) {
      total += o.size;
    }
    log.info('Aggregated ${objects.length} objects, $total bytes used');
    return total;
  } catch (e, st) {
    log.warning('S3 LIST aggregation failed: $e', e, st);
    rethrow;
  }
});
