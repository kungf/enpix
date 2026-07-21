import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/screens/overview/overview_screen.dart';
import 'package:enpix/services/storage/remote_usage_provider.dart';
import 'package:enpix/services/storage/s3_config_service.dart';

/// Verifies the Phase 2.1 deliverable: the overview storage card renders real
/// S3 usage (no more hardcoded 50GB) and offers a configure path when S3 is
/// not set up. Other cards render their loading/error states harmlessly; only
/// the storage card is asserted here.
void main() {
  testWidgets(
    'storage card renders real aggregated usage when S3 is configured',
    (tester) async {
      const bytes = 1073741824; // 1 GiB -> _formatBytes -> "1.00 GB"
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            s3ConfiguredProvider.overrideWith((ref) async => true),
            remoteUsageProvider.overrideWith((ref) async => bytes),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OverviewScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('1.00 GB'), findsOneWidget);
      expect(find.text('已用'), findsOneWidget);
    },
  );

  testWidgets(
    'storage card shows not-configured state when S3 is unset',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            s3ConfiguredProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OverviewScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('未配置 S3'), findsOneWidget);
    },
  );

  // Phase 1.1 deliverable: the dark ThemeExtension resolves (context.colors)
  // without throwing when the system is in dark mode.
  testWidgets('renders under the dark theme without crashing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          s3ConfiguredProvider.overrideWith((ref) async => true),
          remoteUsageProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const OverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('存储用量'), findsOneWidget);
  });
}
