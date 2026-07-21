import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'services/crypto/crypto_service.dart';
import 'services/crypto/credential_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      '${details.exception}',
      name: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      error.toString(),
      name: 'PlatformDispatcher',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  // ── Logging ──
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final errorStr = record.error != null ? ' | error=${record.error}' : '';
    final stackStr = record.stackTrace != null ? '\n${record.stackTrace}' : '';
    final msg =
        '[${record.loggerName}] ${record.level.name}: ${record.message}$errorStr$stackStr';
    debugPrint(msg);
    developer.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });

  // ── First-run detection ──
  // A returning user has both a passphrase and S3 configured; anyone missing
  // means setup is incomplete and we route to the onboarding wizard.
  final creds =
      CredentialService(CryptoService(), const FlutterSecureStorage());
  final hasPassphrase = await creds.hasPassphrase();
  final hasEndpoint = (await creds.getS3Endpoint())?.isNotEmpty ?? false;
  final hasBucket = (await creds.getS3Bucket())?.isNotEmpty ?? false;
  final isFirstRun = !(hasPassphrase && hasEndpoint && hasBucket);

  runApp(ProviderScope(child: EnpixApp(isFirstRun: isFirstRun)));
}
