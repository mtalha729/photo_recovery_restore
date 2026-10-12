import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';

/// A brief, non-interactive launch transition. It deliberately does not wait
/// on platform persistence, so startup always reaches the app shell.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();
  late final Timer _finishTimer;

  @override
  void initState() {
    super.initState();
    _finishTimer = Timer(
      const Duration(milliseconds: 1300),
      widget.onFinished,
    );
  }

  @override
  void dispose() {
    _finishTimer.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animation = reduceMotion
        ? const AlwaysStoppedAnimation<double>(0)
        : _controller;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ResponsiveContent(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: Semantics(
              label: 'Loading Photo Recovery and Restore',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) => _RecoveryLaunchAnimation(
                      progress: animation.value,
                      reduceMotion: reduceMotion,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.headlineSmall,
                      children: const [
                        TextSpan(text: 'Photo '),
                        TextSpan(
                          text: 'Recovery',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Preparing your private recovery workspace',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: 156,
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      color: AppColors.primary,
                      backgroundColor: AppColors.primary.withValues(alpha: .14),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Loading…',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryLaunchAnimation extends StatelessWidget {
  const _RecoveryLaunchAnimation({
    required this.progress,
    required this.reduceMotion,
  });

  final double progress;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scale = reduceMotion ? 1.0 : 0.94 + math.sin(progress * math.pi) * .06;
    return SizedBox(
      width: 164,
      height: 164,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: reduceMotion ? 0 : progress * math.pi * 2,
            child: Container(
              width: 146,
              height: 146,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: .42),
                  width: 5,
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: scale,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accent, AppColors.primary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: .20),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.restore_page_rounded,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
          const Positioned(
            top: 14,
            right: 14,
            child: _OrbitPhotoIcon(color: AppColors.protection),
          ),
          const Positioned(
            bottom: 12,
            left: 10,
            child: _OrbitPhotoIcon(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

class _OrbitPhotoIcon extends StatelessWidget {
  const _OrbitPhotoIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      shape: BoxShape.circle,
    ),
    child: Icon(Icons.photo_outlined, color: color, size: 22),
  );
}
