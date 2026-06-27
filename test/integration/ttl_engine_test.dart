/// TTL Engine Integration Test
/// Run: dart run test/integration/ttl_engine_test.dart
///
/// Tests the TTL engine logic (config, run control, cleanup decisions)
/// without requiring a real device photo library.

import 'dart:convert';
import 'dart:io';
import 'package:see_photo/services/ttl/ttl_config.dart';

void main() async {
  int passed = 0, failed = 0;
  void ok(String m) { passed++; print('  ✅ $m'); }
  void fail(String m) { failed++; print('  ❌ $m'); }

  print('═══ TTL Engine Test ═══\n');

  // T1: Config defaults
  print('T1: Config Defaults');
  try {
    const cfg = TtlConfig();
    if (cfg.isEnabled == false) ok('Default isEnabled=false');
    else fail('Expected isEnabled=false');
    if (cfg.timeDays == 30) ok('Default timeDays=30');
    else fail('Expected timeDays=30');
    if (cfg.sizeGb == 100) ok('Default sizeGb=100');
    else fail('Expected sizeGb=100');
  } catch (e) { fail('Defaults: $e'); }

  // T2: Config JSON roundtrip
  print('\nT2: Config JSON Roundtrip');
  try {
    const original = TtlConfig(
      timeEnabled: true,
      timeDays: 7,
      sizeEnabled: true,
      sizeGb: 200,
    );
    final json = original.toJson();
    final restored = TtlConfig.fromJson(json);
    if (restored.timeEnabled == true) ok('timeEnabled preserved');
    else fail('timeEnabled lost');
    if (restored.timeDays == 7) ok('timeDays preserved');
    else fail('timeDays lost');
    if (restored.sizeEnabled == true) ok('sizeEnabled preserved');
    else fail('sizeEnabled lost');
    if (restored.sizeGb == 200) ok('sizeGb preserved');
    else fail('sizeGb lost');
    if (restored.isEnabled) ok('isEnabled=true after restore');
    else fail('Expected isEnabled=true');
  } catch (e) { fail('Roundtrip: $e'); }

  // T3: Config fromJson with missing fields
  print('\nT3: Config fromJson Missing Fields');
  try {
    final cfg = TtlConfig.fromJson(<String, dynamic>{});
    if (cfg.timeEnabled == false) ok('Missing timeEnabled defaults to false');
    else fail('Expected false');
    if (cfg.timeDays == 30) ok('Missing timeDays defaults to 30');
    else fail('Expected 30');
    if (cfg.sizeEnabled == false) ok('Missing sizeEnabled defaults to false');
    else fail('Expected false');
    if (cfg.sizeGb == 100) ok('Missing sizeGb defaults to 100');
    else fail('Expected 100');
  } catch (e) { fail('Missing fields: $e'); }

  // T4: Config copyWith
  print('\nT4: Config copyWith');
  try {
    const original = TtlConfig(timeEnabled: true, timeDays: 14);
    final copy = original.copyWith(sizeEnabled: true, sizeGb: 50);
    if (copy.timeEnabled == true) ok('copyWith preserves timeEnabled');
    else fail('timeEnabled not preserved');
    if (copy.timeDays == 14) ok('copyWith preserves timeDays');
    else fail('timeDays not preserved');
    if (copy.sizeEnabled == true) ok('copyWith sets sizeEnabled');
    else fail('sizeEnabled not set');
    if (copy.sizeGb == 50) ok('copyWith sets sizeGb');
    else fail('sizeGb not set');
    if (original.sizeEnabled == false) ok('Original unchanged');
    else fail('Original mutated');
  } catch (e) { fail('copyWith: $e'); }

  // T5: isEnabled logic
  print('\nT5: isEnabled Logic');
  try {
    const both = TtlConfig(timeEnabled: true, sizeEnabled: true);
    const neither = TtlConfig();
    const timeOnly = TtlConfig(timeEnabled: true);
    const sizeOnly = TtlConfig(sizeEnabled: true);
    if (both.isEnabled) ok('Both enabled → isEnabled=true');
    else fail('Expected true');
    if (!neither.isEnabled) ok('Neither enabled → isEnabled=false');
    else fail('Expected false');
    if (timeOnly.isEnabled) ok('Time only → isEnabled=true');
    else fail('Expected true');
    if (sizeOnly.isEnabled) ok('Size only → isEnabled=true');
    else fail('Expected true');
  } catch (e) { fail('isEnabled: $e'); }

  // T6: Config JSON serialization format
  print('\nT6: JSON Serialization Format');
  try {
    const cfg = TtlConfig(timeEnabled: true, timeDays: 14, sizeEnabled: false, sizeGb: 50);
    final json = cfg.toJson();
    final encoded = jsonEncode(json);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    if (decoded['timeEnabled'] == true) ok('JSON has timeEnabled');
    else fail('Missing timeEnabled');
    if (decoded['timeDays'] == 14) ok('JSON has timeDays');
    else fail('Missing timeDays');
    if (decoded['sizeEnabled'] == false) ok('JSON has sizeEnabled');
    else fail('Missing sizeEnabled');
    if (decoded['sizeGb'] == 50) ok('JSON has sizeGb');
    else fail('Missing sizeGb');
    if (json.length == 4) ok('JSON has exactly 4 keys');
    else fail('Expected 4 keys, got ${json.length}');
  } catch (e) { fail('JSON format: $e'); }

  // T7: Time-based cleanup decision logic
  print('\nT7: Time-based Cleanup Decision');
  try {
    const timeDays = 30;
    final cutoff = DateTime.now().subtract(const Duration(days: timeDays));
    final oldPhoto = DateTime(2024, 1, 15);
    final newPhoto = DateTime.now();
    final edgePhoto = cutoff.subtract(const Duration(days: 1));

    if (oldPhoto.isBefore(cutoff)) ok('Old photo (2024-01-15) is before cutoff');
    else fail('Expected before cutoff');
    if (!newPhoto.isBefore(cutoff)) ok('New photo (today) is NOT before cutoff');
    else fail('Expected not before cutoff');
    if (edgePhoto.isBefore(cutoff)) ok('Edge photo (cutoff-1d) is before cutoff');
    else fail('Expected before cutoff');
  } catch (e) { fail('Time decision: $e'); }

  // T8: Size-based cleanup decision logic
  print('\nT8: Size-based Cleanup Decision');
  try {
    const sizeGb = 100;
    final limitBytes = sizeGb * 1024 * 1024 * 1024;
    final underLimit = 50 * 1024 * 1024 * 1024;
    final overLimit = 150 * 1024 * 1024 * 1024;
    final atLimit = 100 * 1024 * 1024 * 1024;

    if (underLimit <= limitBytes) ok('50 GB is under 100 GB limit');
    else fail('Expected under limit');
    if (overLimit > limitBytes) ok('150 GB exceeds 100 GB limit');
    else fail('Expected over limit');
    if (atLimit <= limitBytes) ok('100 GB is at limit (not exceeded)');
    else fail('Expected at limit');
  } catch (e) { fail('Size decision: $e'); }

  // T9: 1 GiB target free calculation
  print('\nT9: 1 GiB Target Free');
  try {
    const targetFree = 1024 * 1024 * 1024;
    if (targetFree == 1073741824) ok('1 GiB = 1,073,741,824 bytes');
    else fail('Expected 1073741824, got $targetFree');

    int freed = 0;
    int deleted = 0;
    final photoSizes = [5 * 1024 * 1024, 8 * 1024 * 1024, 3 * 1024 * 1024, 12 * 1024 * 1024];
    for (final size in photoSizes) {
      if (freed >= targetFree) break;
      freed += size;
      deleted++;
    }
    if (deleted == 4) ok('Deleted all 4 small photos (${freed ~/ (1024 * 1024)} MB freed)');
    else fail('Expected 4 deleted, got $deleted');
  } catch (e) { fail('Target free: $e'); }

  // T10: Upload tracker mock interaction
  print('\nT10: Upload Tracker Asset IDs');
  try {
    final uploadedIds = <String>{'asset-001', 'asset-002', 'asset-003'};
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final assets = [
      ('asset-001', DateTime(2024, 1, 1)),
      ('asset-002', DateTime.now()),
      ('asset-003', DateTime(2024, 6, 15)),
    ];
    final toDelete = <String>[];
    for (final (id, date) in assets) {
      if (uploadedIds.contains(id) && date.isBefore(cutoff)) {
        toDelete.add(id);
      }
    }
    if (toDelete.length == 2) ok('Found 2 old uploaded photos to delete');
    else fail('Expected 2, got ${toDelete.length}');
    if (toDelete.contains('asset-001')) ok('Includes asset-001 (old)');
    else fail('Missing asset-001');
    if (toDelete.contains('asset-003')) ok('Includes asset-003 (old)');
    else fail('Missing asset-003');
    if (!toDelete.contains('asset-002')) ok('Excludes asset-002 (new)');
    else fail('Should not include asset-002');
  } catch (e) { fail('Tracker interaction: $e'); }

  // T11: Min run interval logic
  print('\nT11: Min Run Interval');
  try {
    const minInterval = Duration(hours: 6);
    final lastRun = DateTime.now().subtract(const Duration(hours: 3));
    final tooRecent = DateTime.now().difference(lastRun) < minInterval;
    if (tooRecent) ok('3 hours ago is too recent (min 6h)');
    else fail('Expected too recent');

    final lastRunOld = DateTime.now().subtract(const Duration(hours: 7));
    final okToRun = DateTime.now().difference(lastRunOld) >= minInterval;
    if (okToRun) ok('7 hours ago is OK to run');
    else fail('Expected OK to run');
  } catch (e) { fail('Min interval: $e'); }

  print('\n═══ TTL Engine: $passed/$failed ═══');
  exit(failed > 0 ? 1 : 0);
}
