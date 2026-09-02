import 'dart:typed_data';

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

  /// Bypasses the real (slow) Argon2id crypto. Uses [restoreWithRecoveryKey]
  /// to activate a session and a keychain backing map to control
  /// [hasPassphrase] — no real key derivation needed.
  final _dummyKey = Uint8List(32);

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
        expect(find.text('重置密码'), findsNothing);
      },
    );

    testWidgets(
      'shows 已解锁 when passphrase is set and session is active',
      (tester) async {
        // Activate session without real crypto.
        cred.restoreWithRecoveryKey(_dummyKey);
        backing['has_passphrase'] = 'true';

        await pumpSecuritySection(tester);

        // initState → _refreshHasPassphrase reads has_passphrase=true
        // → _hasPassphrase = true, and cred.isSessionActive = true.
        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('修改'), findsOneWidget);
        expect(find.text('备份恢复密钥'), findsOneWidget);
      },
    );

    testWidgets(
      'shows 已设置 · 未解锁 when passphrase exists but session inactive',
      (tester) async {
        cred.restoreWithRecoveryKey(_dummyKey);
        backing['has_passphrase'] = 'true';
        cred.endSession();

        await pumpSecuritySection(tester);

        expect(find.text('已设置 · 未解锁'), findsOneWidget);
        expect(find.text('解锁'), findsOneWidget);
        expect(find.text('重置密码'), findsOneWidget);
      },
    );
  });

  group('state transitions after session activation', () {
    testWidgets(
      'UI shows 已解锁 after session tick rebuild with active session',
      (tester) async {
        // First pump: no passphrase — shows "未设置".
        await pumpSecuritySection(tester);
        expect(find.text('未设置'), findsOneWidget);

        // Simulate what _setupPassphrase now does after the fix:
        // 1. activate session, 2. set _hasPassphrase, 3. tick rebuild.
        cred.restoreWithRecoveryKey(_dummyKey);
        backing['has_passphrase'] = 'true';
        container.read(sessionTickProvider.notifier).state++;

        // Rebuild — should immediately show "已解锁", not "未设置".
        await tester.pump();
        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('未设置'), findsNothing);
      },
    );
  });

  group('state after autoUnlock', () {
    testWidgets(
      'active session renders 已解锁 regardless of _hasPassphrase',
      (tester) async {
        cred.restoreWithRecoveryKey(_dummyKey);
        // Deliberately DON'T set backing['has_passphrase'] —
        // _hasPassphrase starts false but isActive is true, so the UI
        // should still show "已解锁" (isActive has priority).
        expect(cred.isSessionActive, isTrue);

        await pumpSecuritySection(tester);

        // Subtitle logic: isActive → '已解锁'.
        expect(find.text('已解锁'), findsOneWidget);
        expect(find.text('未设置'), findsNothing);
      },
    );
  });

  group('auto-unlock toggle', () {
    testWidgets(
      'hidden when no passphrase is set',
      (tester) async {
        await pumpSecuritySection(tester);

        expect(find.text('自动解锁'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      },
    );

    testWidgets(
      'enabling shows risk dialog and persists restore material',
      (tester) async {
        // Bypass real crypto — enableAutoUnlock only needs a session KEK
        // (Argon2id derivation hangs under the testWidgets fake clock).
        cred.startSession(_dummyKey);
        backing['has_passphrase'] = 'true';
        await pumpSecuritySection(tester);

        expect(find.text('自动解锁'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        // Risk confirmation before weakening the security posture.
        expect(find.text('开启自动解锁？'), findsOneWidget);
        expect(
          find.textContaining('能解锁你手机的人'),
          findsOneWidget,
        );

        await tester.tap(find.text('开启'));
        await tester.pumpAndSettle();

        expect(backing['auto_unlock_enabled'], 'true');
        expect(backing.containsKey('wrapped_kek_v1'), isTrue);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      },
    );

    testWidgets(
      'disabling clears stored restore material',
      (tester) async {
        cred.startSession(_dummyKey);
        backing['has_passphrase'] = 'true';
        await cred.enableAutoUnlock();
        await pumpSecuritySection(tester);

        // Turning off needs no confirmation dialog.
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(backing['auto_unlock_enabled'], 'false');
        expect(backing.containsKey('wrapped_kek_v1'), isFalse);
        expect(backing.containsKey('saved_passphrase'), isFalse);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      },
    );
  });
}
