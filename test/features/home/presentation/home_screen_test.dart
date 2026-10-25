import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/home/presentation/home_screen.dart';

void main() {
  Widget home() => MaterialApp(
    theme: AppTheme.light,
    home: HomeScreen(
      onStartPhotoRecovery: () {},
      onManageShield: () {},
      onRecoveredPhotos: () {},
      onSettings: () {},
      onDuplicatePhotos: () {},
      onOldPhotos: () {},
      onLargePhotos: () {},
    ),
  );

  testWidgets('Home presents one photo recovery entry and recovery history', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    expect(find.text('Storage details'), findsOneWidget);
    expect(find.text('Recover Photos'), findsOneWidget);
    expect(find.text('Deep Photo Recovery'), findsNothing);
    expect(find.text('Recover Videos'), findsNothing);
    expect(find.text('Recover Files'), findsNothing);
    expect(find.text('Recover Audio'), findsNothing);
    expect(find.text('Recovered Photos'), findsOneWidget);
    expect(find.text('Recovery Shield'), findsOneWidget);
    expect(find.text('Deep Recovery'), findsNothing);
    expect(find.text('Camera & Gallery'), findsNothing);
    expect(find.text('Messaging'), findsNothing);
    expect(find.text('Screenshots & Downloads'), findsNothing);
  });

  testWidgets('Home remains image-free and compact at large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
        child: home(),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home exposes a shared photo recovery action on a standard phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(home());

    expect(find.byKey(const ValueKey('recovery-type-grid')), findsNothing);
    expect(find.bySemanticsLabel('Recover Photos'), findsOneWidget);
  });

  testWidgets('the single Recover Photos entry starts recovery', (
    tester,
  ) async {
    var starts = 0;
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          onStartPhotoRecovery: () => starts++,
          onManageShield: () {},
          onRecoveredPhotos: () {},
          onSettings: () {},
          onDuplicatePhotos: () {},
          onOldPhotos: () {},
          onLargePhotos: () {},
        ),
      ),
    );

    final recoverPhotos = find.text('Recover Photos');
    expect(recoverPhotos, findsOneWidget);
    await tester.tap(recoverPhotos);
    expect(starts, 1);
  });

  testWidgets('Recover Photos is primary and history remains separate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(home());

    final recoverPhotos = find.byKey(const ValueKey('recover-photos-card'));
    final recoveredPhotos = find.byKey(const ValueKey('recovered-photos-card'));
    expect(recoverPhotos, findsOneWidget);
    expect(recoveredPhotos, findsOneWidget);
    expect(
      tester.getCenter(recoveredPhotos).dy,
      greaterThan(tester.getCenter(recoverPhotos).dy),
    );
    expect(tester.getSize(recoverPhotos).height, greaterThan(0));
  });

  testWidgets('Home keeps recovery actions usable at narrow widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(home());

    expect(find.byKey(const ValueKey('recovery-type-grid')), findsNothing);
    expect(find.byKey(const ValueKey('recover-and-history-row')), findsOneWidget);
    expect(find.bySemanticsLabel('Recover Photos'), findsOneWidget);
  });

  testWidgets('Smart Cleanup cards are available and invoke their callbacks', (tester) async {
    var duplicate = 0;
    var old = 0;
    var large = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(
        onStartPhotoRecovery: () {}, onManageShield: () {},
        onRecoveredPhotos: () {}, onSettings: () {},
        onDuplicatePhotos: () => duplicate++, onOldPhotos: () => old++, onLargePhotos: () => large++,
      ),
    ));
    final duplicateCard = find.text('Duplicate Photos');
    await tester.ensureVisible(duplicateCard);
    await tester.pumpAndSettle();
    expect(find.text('Coming later'), findsNothing);
    await tester.tap(duplicateCard);
    await tester.tap(find.text('Old Photos'));
    await tester.tap(find.text('Large Photos'));
    expect((duplicate, old, large), (1, 1, 1));
  });
}