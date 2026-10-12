import 'package:flutter/material.dart';
// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/app.dart';

void main() {
  testWidgets('launch transition always reaches Home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PhotoRecoveryRestoreApp(showOnboarding: true));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump();

    expect(find.text('Storage details'), findsOneWidget);
    expect(find.text('Recover Photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shows the production app shell', (tester) async {
    await tester.pumpWidget(const PhotoRecoveryRestoreApp());

    expect(find.text('Storage details'), findsOneWidget);
    expect(find.text('Recover photos'), findsOneWidget);
  });
}
