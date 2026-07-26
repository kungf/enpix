import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';

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

  runApp(const ProviderScope(child: EnpixApp()));
}
