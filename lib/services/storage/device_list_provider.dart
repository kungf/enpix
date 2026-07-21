import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../providers.dart';
import 's3_config_service.dart';
import 's3_service.dart';

/// Snapshot of the S3 device registry plus the current device's ID, for the
/// overview "devices" card.
typedef DeviceRegistry = ({List<DeviceInfo> devices, String currentDeviceId});

/// Empty registry value used when S3 is not configured.
const emptyDeviceRegistry =
    (devices: <DeviceInfo>[], currentDeviceId: '');

/// Lists all devices registered under this KEK fingerprint and marks the
/// current device. autoDispose + manual invalidate on refresh.
final deviceListProvider =
    FutureProvider.autoDispose<DeviceRegistry>((ref) async {
  final configured = await ref.watch(s3ConfiguredProvider.future);
  if (!configured) return emptyDeviceRegistry;

  final result = await ref.watch(s3ConfigServiceProvider).ensureConfigured();
  if (result != S3ConfigResult.configured) return emptyDeviceRegistry;

  final s3 = ref.watch(s3ServiceProvider);
  final currentDeviceId = await ref.watch(deviceServiceProvider).getDeviceId();
  final log = Logger('deviceListProvider');
  try {
    final devicesMap = await s3.listDevices();
    final devices = devicesMap.values.toList()
      ..sort((a, b) {
        // Current device first, then alphabetical.
        if (a.deviceId == currentDeviceId) return -1;
        if (b.deviceId == currentDeviceId) return 1;
        return a.name.compareTo(b.name);
      });
    return (devices: devices, currentDeviceId: currentDeviceId);
  } catch (e, st) {
    log.warning('listDevices failed: $e', e, st);
    rethrow;
  }
});
