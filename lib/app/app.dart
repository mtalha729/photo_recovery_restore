import 'dart:async';

import 'package:flutter/material.dart';

import 'design_system/theme/app_theme.dart';
import '../features/app_shell/presentation/photo_recovery_app_shell.dart';
import '../features/media_access/media_access.dart';
import '../features/onboarding/onboarding_completion_store.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/recovery_shield_management/recovery_shield_manager.dart';
import '../features/settings/app_preferences.dart';

class PhotoRecoveryRestoreApp extends StatefulWidget {
  const PhotoRecoveryRestoreApp({
    this.themeMode,
    this.showOnboarding = false,
    this.onboardingCompletionStore,
    this.preferencesController,
    this.mediaAccessCoordinator,
    this.shieldManager,
    super.key,
  });

  final ThemeMode? themeMode;
  final bool showOnboarding;
  final OnboardingCompletionStore? onboardingCompletionStore;
  final AppPreferencesController? preferencesController;
  final MediaAccessCoordinator? mediaAccessCoordinator;
  final RecoveryShieldManager? shieldManager;

  @override
  State<PhotoRecoveryRestoreApp> createState() => _PhotoRecoveryRestoreAppState();
}

class _PhotoRecoveryRestoreAppState extends State<PhotoRecoveryRestoreApp> {
  late final AppPreferencesController _preferences =
      widget.preferencesController ??
      AppPreferencesController(PlatformAppPreferencesStore());
  int _onboardingReplay = 0;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_refresh);
    _preferences.load();
  }

  @override
  void dispose() {
    _preferences.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Recovery & Restore',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: widget.themeMode ?? _preferences.state.themeMode,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) ||
              _preferences.state.reduceMotion,
        ),
        child: child!,
      ),
      home: _AppEntry(
        showOnboarding: widget.showOnboarding,
        completionStore: widget.onboardingCompletionStore,
        preferences: _preferences,
        mediaAccessCoordinator: widget.mediaAccessCoordinator,
        shieldManager: widget.shieldManager,
        replayGeneration: _onboardingReplay,
        onReplayRequested: () => setState(() => _onboardingReplay++),
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry({
    required this.showOnboarding,
    required this.preferences,
    required this.replayGeneration,
    required this.onReplayRequested,
    this.completionStore,
    this.mediaAccessCoordinator,
    this.shieldManager,
  });
  final bool showOnboarding;
  final OnboardingCompletionStore? completionStore;
  final AppPreferencesController preferences;
  final MediaAccessCoordinator? mediaAccessCoordinator;
  final RecoveryShieldManager? shieldManager;
  final int replayGeneration;
  final VoidCallback onReplayRequested;

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  late final OnboardingCompletionStore _completionStore =
      widget.completionStore ?? PlatformOnboardingCompletionStore();
  late bool _showOnboarding = widget.showOnboarding;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _AppEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replayGeneration != oldWidget.replayGeneration) {
      setState(() => _showOnboarding = true);
    }
  }

  void _finishOnboarding() {
    if (mounted) setState(() => _showOnboarding = false);
    unawaited(_completionStore.markComplete());
  }

  @override
  Widget build(BuildContext context) => _showOnboarding
      ? OnboardingScreen(
          onFinished: _finishOnboarding,
        )
      : PhotoRecoveryAppShell(
          accessCoordinator: widget.mediaAccessCoordinator,
          shieldManager: widget.shieldManager,
          preferences: widget.preferences,
          onReplayOnboarding: widget.onReplayRequested,
        );
}
