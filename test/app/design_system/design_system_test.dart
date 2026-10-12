import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/app.dart';
import 'package:photo_recovery_restore/app/design_system/components/adaptive_shell.dart';
import 'package:photo_recovery_restore/app/design_system/components/app_components.dart';
import 'package:photo_recovery_restore/app/design_system/foundations/app_breakpoints.dart';
import 'package:photo_recovery_restore/app/design_system/foundations/app_colors.dart';
import 'package:photo_recovery_restore/app/design_system/foundations/app_tokens.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/settings/app_preferences.dart';

void main() {
  group('theme', () {
    test('premium palette retains the locked brand colors', () {
      expect(AppColors.primary.toARGB32(), 0xFF3157F5);
      expect(AppColors.primaryDark.toARGB32(), 0xFF1737C7);
      expect(AppColors.accent.toARGB32(), 0xFF23C7D9);
      expect(AppColors.protection.toARGB32(), 0xFF14B8A6);
      expect(AppColors.darkBackground.toARGB32(), 0xFF080D1A);
    });

    testWidgets('light and dark themes build correctly', (tester) async {
      await tester.pumpWidget(
        const PhotoRecoveryRestoreApp(themeMode: ThemeMode.light),
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );

      await tester.pumpWidget(
        const PhotoRecoveryRestoreApp(themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('system theme follows platform brightness', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(const PhotoRecoveryRestoreApp());
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
    });
  });

  test('adaptive breakpoints and grid columns use available width', () {
    expect(AppBreakpoints.windowClassFor(599), AppWindowClass.compact);
    expect(AppBreakpoints.windowClassFor(600), AppWindowClass.medium);
    expect(AppBreakpoints.windowClassFor(840), AppWindowClass.expanded);
    expect(AppPhotoGrid.columnsFor(320), 2);
    expect(AppPhotoGrid.columnsFor(900), 5);
    expect(AppPhotoGrid.columnsFor(10000), AppPhotoGrid.maximumColumns);
  });

  testWidgets('navigation switches from bottom bar to rail', (tester) async {
    Future<void> pumpAt(double width) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SizedBox(
          width: width,
          child: AdaptiveAppShell(
            body: const Text('Body'),
            destinations: const [
              AppNavigationDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
              ),
              AppNavigationDestination(
                icon: Icons.photo_outlined,
                selectedIcon: Icons.photo,
                label: 'Photos',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpAt(500);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.binding.setSurfaceSize(const Size(900, 800));
    await pumpAt(900);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('short landscape keeps navigation reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 430));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const AdaptiveAppShell(
          body: Text('Body'),
          destinations: [
            AppNavigationDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Home',
            ),
            AppNavigationDestination(
              icon: Icons.photo_outlined,
              selectedIcon: Icons.photo,
              label: 'Photos',
            ),
          ],
        ),
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status chip has text, icon, and semantic label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: RecoveryStatusChip(status: RecoveryStatusVisual.protected),
        ),
      ),
    );
    expect(find.text('Protected'), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(RecoveryStatusChip)),
      matchesSemantics(label: 'Protected'),
    );
  });

  testWidgets('core components render narrow with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: ResponsiveContent(
                padding: EdgeInsets.all(12),
                child: RecoveryCardShell(
                  title: 'A long recovery item title that must remain usable',
                  subtitle:
                      'Supporting metadata remains readable at large scale.',
                  status: RecoveryStatusVisual.possibleCopy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Possible Copy'), findsOneWidget);
  });

  testWidgets('core components render at wide constraints', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: ResponsiveContent(
            child: AppEmptyState(
              icon: Icons.photo_outlined,
              title: 'Nothing here yet',
              message: 'Future recovery results will appear here.',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  test('reduced motion resolves token durations to zero', () {
    expect(AppMotion.durationFor(reduceMotion: true), Duration.zero);
    expect(AppMotion.durationFor(reduceMotion: false), AppMotion.standard);
  });

  testWidgets('saved reduced-motion preference reaches production widgets', (
    tester,
  ) async {
    final preferences = AppPreferencesController(
      _PreferenceStore(
        const AppPreferenceState(reduceMotion: true),
      ),
    );
    await tester.pumpWidget(
      PhotoRecoveryRestoreApp(preferencesController: preferences),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.of(tester.element(find.byType(Scaffold).first))
          .disableAnimations,
      isTrue,
    );
  });
}

class _PreferenceStore implements AppPreferencesStore {
  _PreferenceStore(this.value);
  AppPreferenceState value;

  @override
  Future<List<String>> authorizedFolders() async => const [];

  @override
  Future<String> appVersion() async => 'test';

  @override
  Future<AppPreferenceState> load() async => value;

  @override
  Future<void> save(AppPreferenceState state) async => value = state;
}
