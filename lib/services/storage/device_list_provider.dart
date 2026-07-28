import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 's3_config_service.dart';

/// Snapshot of the current device's S3 path identifier for the overview
/// "devices" card.
typedef DeviceRegistry = ({String currentDeviceId});

/// Empty registry value used when S3 is not configured.
const emptyDeviceRegistry = (currentDeviceId: '');

/// Reads the current device's path ID (e.g. "wyang-iphone8").
/// autoDispose + manual invalidate on refresh.
final deviceListProvider =
    FutureProvider.autoDispose<DeviceRegistry>((ref) async {
  final configured = await ref.watch(s3ConfiguredProvider.future);
  if (!configured) return emptyDeviceRegistry;

  final result = await ref.watch(s3ConfigServiceProvider).ensureConfigured();
  if (result != S3ConfigResult.configured) return emptyDeviceRegistry;

  final deviceId = await ref.watch(deviceServiceProvider).getDevicePathId();
  return (currentDeviceId: deviceId);
});
