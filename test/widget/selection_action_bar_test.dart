import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enpix/core/theme/app_theme.dart';
import 'package:enpix/presentation/shared/widgets/selection_action_bar.dart';

/// Verifies the Phase 2.2 deliverable: the selection action bar shows the
/// selected count and fires onUpload / onCancel. The bar was extracted to a
/// public widget so this can be tested without pulling in photo_manager
/// (the gallery screen owns the AssetEntity list and wires onUpload to
/// BackupManager.start).
void main() {
  testWidgets('shows the selected count and fires onUpload / onCancel',
      (tester) async {
    var uploadCalls = 0;
    var cancelCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SelectionActionBar(
            count: 3,
            onUpload: () async => uploadCalls++,
            onCancel: () => cancelCalls++,
          ),
        ),
      ),
    );

    expect(find.text('上传所选 (3)'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('上传所选 (3)'));
    await tester.pump();
    expect(uploadCalls, 1);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancelCalls, 1);
  });
}
