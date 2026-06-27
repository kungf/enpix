import 'package:flutter_test/flutter_test.dart';
import 'package:see_photo/app.dart';

void main() {
  testWidgets('App renders main screen with navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const SeePhotoApp());

    // The main screen has a bottom nav with "本地" tab.
    expect(find.text('本地'), findsWidgets);
    expect(find.text('See-Photo'), findsOneWidget);
  });
}
