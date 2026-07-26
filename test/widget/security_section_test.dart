import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/screens/settings/widgets/security_section.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/crypto/credential_service.dart';
import 'package:enpix/services/crypto/crypto_service.dart';

class _FakeSecureStorage extends Mock implements FlutterSecureStorage {}

/// Backs the mock with a real map so reads return what was written,
/// mimicking actual Keychain behavior.
void main() {
  late _FakeSecureStorage storage;
  late Map<String, String> backing;
  late CredentialService cred;
  late ProviderContainer container;

  const slow = Timeout(Duration(minutes: 2));

  setUp(() {
    backing = {};
    storage = _FakeSecureStorage();
    when(() => storage.read(key: any(named: 'key'))).thenAnswer(
      (inv) async => backing[inv.namedArguments[#key] as String],
    );
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((inv) async {
      final key = inv.namedArguments[#key] as String;
      final value = inv.namedArguments[#value] as String?;
      if (value == null) {
        backing.remove(key);
      } else {
        backing[key] = value;
      }
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer(
      (inv) async => backing.remove(inv.namedArguments[#key] as String),
    );
    cred = CredentialService(CryptoService(), storage);

    container = ProviderContainer(
      overrides: [
        credentialServiceProvider.overrideWith((ref) => cred),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> pumpSecuritySection(WidgetTester tester) async {
    // EnpixSection wraps EnpixListTile in a colored DecoratedBox, which
    // Flutter flags as hiding ink splashes — a pre-existing cosmetic
    // warning, not behavior under test.
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SecuritySection()),
        ),
      ),
    );
    await tester.pump();
  }

  group('SecuritySection UI states', () {
    testWidgets(
      'shows 未设置 when no passphrase is set',
      (tester) async {
        await pumpSecuritySection(tester);

        expect(find.text('未设置'), findsOneWidget);
        expect(find.text('设置'), findsOneWidget);
        expect(find.text('加密密码'), findsOneWidget);
        // No recovery or reset options when passphrase is not set.
        expect(find.text('找回密码'), findsNothing);
      },
    );

    testWidgets(
      'shows 已解锁 when passphrase is set and session is active',
      (tester) async {
        await cred.setupPassphrase('test password 123');

        await pumpSecuritySection(tester);

        // initState → _refreshHasPassphrase reads has_passphrase=true
        // → _hasPassphrase = true, and cred.isSessionActive = true.
        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('修改'), findsOneWidget);
        expect(find.text('备份恢复密钥'), findsOneWidget);
      },
      timeout: slow,
    );

    testWidgets(
      'shows 已设置 · 未解锁 when passphrase exists but session inactive',
      (tester) async {
        await cred.setupPassphrase('test password 123');
        cred.endSession();

        await pumpSecuritySection(tester);

        expect(find.text('已设置 · 未解锁'), findsOneWidget);
        expect(find.text('解锁'), findsOneWidget);
        expect(find.text('找回密码'), findsOneWidget);
      },
      timeout: slow,
    );
  });

  group('state transitions after setupPassphrase', () {
    testWidgets(
      '_hasPassphrase is updated before session-tick rebuild, '
      'so UI never shows 未设置 after a successful setup',
      (tester) async {
        // First pump: no passphrase — shows "未设置".
        await pumpSecuritySection(tester);
        expect(find.text('未设置'), findsOneWidget);

        // Simulate the fix: set _hasPassphrase first, then increment tick.
        // This is what _setupPassphrase now does after the fix.
        await cred.setupPassphrase('correct horse battery staple');
        // Update local state synchronously — mirrors:
        //   if (mounted) setState(() => _hasPassphrase = true);
        container.read(sessionTickProvider.notifier).state++;

        // Rebuild — should immediately show "已解锁", not "未设置".
        await tester.pump();
        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('未设置'), findsNothing);
      },
      timeout: slow,
    );
  });

  group('state after autoUnlock', () {
    testWidgets(
      'autoUnlock restores session without re-entering password',
      (tester) async {
        await cred.setupPassphrase('test password 123');
        cred.endSession();
        expect(cred.isSessionActive, isFalse);

        // autoUnlock re-derives KEK from saved passphrase.
        final unlocked = await cred.autoUnlock();
        expect(unlocked, isTrue);

        await pumpSecuritySection(tester);

        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('未设置'), findsNothing);
      },
      timeout: slow,
    );
  });

  group('resetAll returns to 未设置', () {
    testWidgets(
      'resetAll clears passphrase and UI returns to 未设置',
      (tester) async {
        await cred.setupPassphrase('test password 123');
        await pumpSecuritySection(tester);
        expect(find.text('已解锁'), findsOneWidget);

        await cred.resetAll();
        container.read(sessionTickProvider.notifier).state++;
        await tester.pumpAndSettle();

        expect(find.text('未设置'), findsOneWidget);
        expect(find.text('设置'), findsOneWidget);
      },
      timeout: slow,
    );
  });
}
