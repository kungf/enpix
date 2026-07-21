import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/screens/settings/widgets/upload_section.dart';
import 'package:enpix/services/settings/upload_settings_provider.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// Verifies the Phase 2.4 deliverable: UploadSection writes through to the
/// uploadSettingsProvider (Keychain persistence) on every change and the new
/// state is reflected in the UI.
void main() {
  late _MockSecureStorage storage;

  setUp(() {
    storage = _MockSecureStorage();
    // Notifier loads on construction; default to "no stored settings".
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    // Writes are fire-and-forget from the UI; absorb them so no platform
    // channel is touched.
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
  });

  testWidgets(
    'toggling WiFi-only writes through to the notifier and reflects in the UI',
    (tester) async {
      // EnpixSection wraps SwitchListTiles in a colored DecoratedBox, which
      // Flutter flags as hiding ink splashes - a pre-existing cosmetic
      // warning, not behavior under test. Capture FlutterErrors and only fail
      // on unexpected ones.
      final previousOnError = FlutterError.onError;
      final flutterErrors = <FlutterErrorDetails>[];
      FlutterError.onError = flutterErrors.add;
      addTearDown(() {
        FlutterError.onError = previousOnError;
        final unexpected = flutterErrors
            .where((e) => !e.toString().contains('may be invisible'))
            .toList();
        expect(unexpected, isEmpty, reason: '$unexpected');
      });

      final container = ProviderContainer(
        overrides: [
          uploadSettingsProvider.overrideWith(
            (ref) => UploadSettingsNotifier(storage),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: UploadSection()),
          ),
        ),
      );
      // Let the notifier's async _load() settle.
      await tester.pump();

      // Default state: WiFi-only on (see UploadSettings defaults).
      expect(container.read(uploadSettingsProvider).wifiOnly, isTrue);

      // Tap the "仅 WiFi 上传" SwitchListTile to turn it off.
      await tester.tap(find.widgetWithText(SwitchListTile, '仅 WiFi 上传'));
      await tester.pumpAndSettle();

      // Persisted (write invoked) + reflected (notifier state + switch off).
      verify(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).called(greaterThanOrEqualTo(1));
      expect(container.read(uploadSettingsProvider).wifiOnly, isFalse);

      final sw = tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, '仅 WiFi 上传'),
          matching: find.byType(Switch),
        ),
      );
      expect(sw.value, isFalse);
    },
  );
}
