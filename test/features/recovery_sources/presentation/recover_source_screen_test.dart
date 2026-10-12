import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovery_sources/presentation/recover_source_screen.dart';
import 'package:photo_recovery_restore/features/recovery_sources/presentation/recovery_source_intent.dart';

void main() {
  testWidgets('renders four mutually distinct recovery source cards', (
    tester,
  ) async {
    _useLargeViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RecoverSourceScreen(onSourceSelected: (_) {}, onSettings: () {}),
      ),
    );

    for (final source in RecoverySourceIntent.values) {
      expect(find.text(source.title), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == source.semanticLabel,
        ),
        findsOneWidget,
      );
    }
    expect(
      RecoverySourceIntent.values.map((value) => value.title).toSet(),
      hasLength(4),
    );
  });

  for (final source in RecoverySourceIntent.values) {
    testWidgets('${source.title} emits its exact typed navigation intent', (
      tester,
    ) async {
      _useLargeViewport(tester);
      RecoverySourceIntent? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecoverSourceScreen(
            onSourceSelected: (intent) => selected = intent,
            onSettings: () {},
          ),
        ),
      );

      final sourceTitle = find.text(source.title);
      await tester.ensureVisible(sourceTitle);
      await tester.tap(sourceTitle);
      expect(selected, source);
    });
  }

  testWidgets('source intent opens a clean capability placeholder', (
    tester,
  ) async {
    _useLargeViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: PhotoRecoverySourceNavigationHarness()),
    );
    final cameraGallery = find.text('Camera & Gallery');
    await tester.ensureVisible(cameraGallery);
    await tester.tap(cameraGallery);
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera & Gallery'), findsOneWidget);
    expect(find.textContaining('next recovery step'), findsOneWidget);
  });
}

void _useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class PhotoRecoverySourceNavigationHarness extends StatelessWidget {
  const PhotoRecoverySourceNavigationHarness({super.key});

  @override
  Widget build(BuildContext context) => RecoverSourceScreen(
    onSettings: () {},
    onSourceSelected: (intent) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Text('${intent.title}: ${intent.capabilityMessage}'),
          ),
        ),
      );
    },
  );
}
