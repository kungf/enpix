import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/app.dart';

void main() {
  testWidgets('App renders navigation tabs', (WidgetTester tester) async {
    // EnpixSection wraps children in a colored DecoratedBox, which Flutter
    // flags as hiding ink splashes — a pre-existing cosmetic warning, not a
    // behavior under test. Capture FlutterErrors and only fail on unexpected
    // ones.
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

    await tester.pumpWidget(const ProviderScope(child: EnpixApp()));
    await tester.pump();

    // Cloud / Overview / Settings tabs are always present (Photos is hidden
    // on desktop/web, so we only assert the always-on destinations).
    expect(find.text('云端'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
