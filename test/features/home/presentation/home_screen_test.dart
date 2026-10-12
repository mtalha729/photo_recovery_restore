import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/home/presentation/home_screen.dart';

void main() {
  Widget home() => MaterialApp(
    theme: AppTheme.light,
    home: HomeScreen(
      onRecoverPhotos: () {},
      onDeepPhotoRecovery: () {},
      onManageShield: () {},
      onRecoveredPhotos: () {},
      onSettings: () {},
      onDuplicatePhotos: () {},
      onOldPhotos: () {},
      onLargePhotos: () {},
    ),
  );

  testWidgets('Home presents one source-agnostic photo recovery entry', (
    tester,
  ) async {
    await tester.pumpWidget(home());
    expect(find.text('Storage details'), findsOneWidget);
    expect(find.text('Recover Photos'), findsOneWidget);
    expect(find.text('Recover Videos'), findsNothing);
    expect(find.text('Recover Files'), findsNothing);
    expect(find.text('Recover Audio'), findsNothing);
    expect(find.textContaining('Recovered'), findsOneWidget);
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

  testWidgets('Home uses one focused recovery action on a standard phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(home());

    expect(find.byKey(const ValueKey('recovery-type-grid')), findsNothing);
    expect(find.bySemanticsLabel('Recover Photos'), findsOneWidget);
  });

  testWidgets('Recover Photos and Recovered Photos share one horizontal row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(home());

    final recoverPhotos = find.byKey(const ValueKey('recover-photos-card'));
    final recoveredPhotos = find.byKey(const ValueKey('recovered-photos-card'));
    expect(recoverPhotos, findsOneWidget);
    expect(recoveredPhotos, findsOneWidget);
    expect(tester.getCenter(recoveredPhotos).dx, greaterThan(tester.getCenter(recoverPhotos).dx));
    expect(
      (tester.getCenter(recoveredPhotos).dy - tester.getCenter(recoverPhotos).dy).abs(),
      lessThan(1),
    );
    expect(tester.getSize(recoveredPhotos).height, tester.getSize(recoverPhotos).height);
  });
  testWidgets('Home keeps its focused action at narrow widths', (tester) async {
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
        onRecoverPhotos: () {}, onDeepPhotoRecovery: () {}, onManageShield: () {},
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