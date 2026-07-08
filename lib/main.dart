import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire up logging so _log.info/warning/severe print to console AND terminal.
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final errorStr = record.error != null ? ' | error=${record.error}' : '';
    final stackStr = record.stackTrace != null ? '\n${record.stackTrace}' : '';
    final msg = '[${record.loggerName}] ${record.level.name}: ${record.message}$errorStr$stackStr';
    debugPrint(msg);
    developer.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });

  runApp(const ProviderScope(child: SeePhotoApp()));
}
