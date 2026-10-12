import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/app.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/app_shell/presentation/photo_recovery_app_shell.dart';
import 'package:photo_recovery_restore/features/media_access/media_access.dart';
import 'package:photo_recovery_restore/features/media_access/presentation/media_access_screen.dart';
import 'package:photo_recovery_restore/features/onboarding/onboarding_completion_store.dart';

void main() {
  testWidgets('launch animation enters the app without requesting access', (
    tester,
  ) async {
    final store = _OnboardingStore();
    await tester.pumpWidget(
      PhotoRecoveryRestoreApp(
        showOnboarding: true,
        onboardingCompletionStore: store,
      ),
    );
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('Accurate recovery'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Storage details'), findsOneWidget);
    expect(store.isCompleteValue, isTrue);
  });

  testWidgets('launch animation does not wait for persisted onboarding state', (
    tester,
  ) async {
    final store = _OnboardingStore(isComplete: true);
    await tester.pumpWidget(
      PhotoRecoveryRestoreApp(
        showOnboarding: true,
        onboardingCompletionStore: store,
      ),
    );
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Storage details'), findsOneWidget);
  });

  testWidgets('Not now does not request permission', (tester) async {
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.pumpWidget(_accessApp(coordinator));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(coordinator.requestCalls, 0);
  });

  testWidgets('rationale appears before explicit request', (tester) async {
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.pumpWidget(_accessApp(coordinator));
    expect(find.textContaining('compare current media'), findsOneWidget);
    expect(coordinator.requestCalls, 0);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(coordinator.requestCalls, 1);
  });

  testWidgets('limited access is clearly labelled and never claims full scan', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.limitedSelectedAccess);
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaAccessScreen(
          coordinator: coordinator,
          initialState: coordinator.state,
          onAccessAvailable: (_) => continued = true,
        ),
      ),
    );
    expect(find.text('Limited photo access'), findsOneWidget);
    expect(find.textContaining('not a full-library scan'), findsOneWidget);
    expect(find.textContaining('All photos scanned'), findsNothing);
    expect(find.text('Request full photo access'), findsOneWidget);
    await tester.tap(find.text('Choose or change allowed photos'));
    await tester.pump();
    expect(coordinator.requestIntents, [
      MediaAccessRequestIntent.changeSelectedPhotos,
    ]);
    await tester.tap(find.text('Continue with limited access'));
    expect(continued, isTrue);
  });

  testWidgets('limited access offers a distinct full-access upgrade', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.limitedSelectedAccess);
    await tester.pumpWidget(_accessApp(coordinator));
    await tester.tap(find.text('Request full photo access'));
    await tester.pump();
    expect(coordinator.requestIntents, [MediaAccessRequestIntent.fullAccess]);
  });

  testWidgets('unsupported state never offers a permission request', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.unsupported);
    await tester.pumpWidget(_accessApp(coordinator));
    expect(find.text('Continue'), findsNothing);
    expect(find.textContaining('No access was requested'), findsOneWidget);
    expect(coordinator.requestCalls, 0);
  });

  testWidgets('settings-required is explicit and never opens automatically', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.settingsRequired);
    await tester.pumpWidget(_accessApp(coordinator));
    expect(coordinator.settingsCalls, 0);
    expect(find.text('Open Settings'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(coordinator.settingsCalls, 1);
  });

  testWidgets('app startup does not check or request permission', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAppShell(accessCoordinator: coordinator),
      ),
    );
    expect(coordinator.getCalls, 0);
    expect(coordinator.requestCalls, 0);
  });

  testWidgets('library permission is checked only after source intent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAppShell(accessCoordinator: coordinator),
      ),
    );
    expect(coordinator.getCalls, 0);
    await tester.tap(find.text('Recover Photos'));
    await tester.pumpAndSettle();
    expect(coordinator.getCalls, 1);
    expect(coordinator.requestCalls, 0);
    expect(find.text('Photo access'), findsOneWidget);
  });

  testWidgets('permission state is rechecked for each recovery intent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAppShell(accessCoordinator: coordinator),
      ),
    );
    await tester.tap(find.text('Recover Photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recover Photos'));
    await tester.pumpAndSettle();
    expect(coordinator.getCalls, 2);
  });

  testWidgets('full access routes to scan without another permission request', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final coordinator = _Coordinator(MediaAccessStatus.fullAccess);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAppShell(accessCoordinator: coordinator),
      ),
    );
    await tester.tap(find.text('Recover Photos'));
    await tester.pump();
    expect(find.text('Recover Photos'), findsOneWidget);
    expect(coordinator.requestCalls, 0);
  });

  testWidgets('rationale remains usable with large text and dark theme', (
    tester,
  ) async {
    final coordinator = _Coordinator(MediaAccessStatus.denied);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: MediaAccessScreen(
          coordinator: coordinator,
          initialState: coordinator.state,
          onAccessAvailable: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Not now'), findsOneWidget);
  });
}

Widget _accessApp(_Coordinator coordinator) => MaterialApp(
  theme: AppTheme.light,
  home: MediaAccessScreen(
    coordinator: coordinator,
    initialState: coordinator.state,
    onAccessAvailable: (_) {},
  ),
);

class _Coordinator implements MediaAccessCoordinator {
  _Coordinator(MediaAccessStatus status)
    : state = MediaAccessState(status: status, androidApiLevel: 34);
  MediaAccessState state;
  int getCalls = 0;
  int requestCalls = 0;
  int settingsCalls = 0;
  final List<MediaAccessRequestIntent> requestIntents = [];

  @override
  Future<MediaAccessState> getState() async {
    getCalls++;
    return state;
  }

  @override
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  }) async {
    requestCalls++;
    requestIntents.add(intent);
    return state;
  }

  @override
  Future<void> openSettings() async {
    settingsCalls++;
  }
}

class _OnboardingStore implements OnboardingCompletionStore {
  _OnboardingStore({bool isComplete = false}) : isCompleteValue = isComplete;

  bool isCompleteValue;

  @override
  Future<bool> isComplete() async => isCompleteValue;

  @override
  Future<void> markComplete() async => isCompleteValue = true;
}
