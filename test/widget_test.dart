import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/app.dart';

void main() {
  testWidgets('App renders navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: EnpixApp()));
    await tester.pump();

    // Cloud / Overview / Settings tabs are always present (Photos is hidden
    // on desktop/web, so we only assert the always-on destinations).
    expect(find.text('云端'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
