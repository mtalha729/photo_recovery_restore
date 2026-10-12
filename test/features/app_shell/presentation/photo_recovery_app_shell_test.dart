import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/app.dart';

void main() {
  Future<void> setSize(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Home is a focused dashboard without bottom tabs', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 800));
    await tester.pumpWidget(const PhotoRecoveryRestoreApp());

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Storage details'), findsOneWidget);
    expect(find.text('Recover Photos'), findsOneWidget);
    expect(find.text('View details'), findsNothing);
  });

  testWidgets('Home exposes one accessible photo recovery action', (
    tester,
  ) async {
    await tester.pumpWidget(const PhotoRecoveryRestoreApp());
    expect(find.bySemanticsLabel('Recover Photos'), findsOneWidget);
    expect(find.bySemanticsLabel('Start Deep Recovery'), findsNothing);
    expect(find.text('Camera & Gallery'), findsNothing);
  });

  testWidgets('dashboard is usable at narrow, wide, and large text layouts', (
    tester,
  ) async {
    await setSize(tester, const Size(320, 720));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.7)),
        child: PhotoRecoveryRestoreApp(),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const PhotoRecoveryRestoreApp());
    await tester.pumpAndSettle();
    expect(find.text('Storage details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light and dark dashboard themes remain compatible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const PhotoRecoveryRestoreApp(themeMode: ThemeMode.light),
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );

    await tester.pumpWidget(
      const PhotoRecoveryRestoreApp(themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
  });

  testWidgets(
    'dashboard exposes Settings and source-agnostic recovery actions',
    (tester) async {
      await tester.pumpWidget(const PhotoRecoveryRestoreApp());
      expect(find.byTooltip('Open settings'), findsOneWidget);
      expect(find.text('Recover Photos'), findsOneWidget);
      expect(find.text('Deep Recovery'), findsNothing);
    },
  );
}
