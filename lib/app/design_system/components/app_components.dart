import 'package:flutter/material.dart';

import '../foundations/app_colors.dart';
import '../foundations/app_tokens.dart';

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    this.maxWidth = 1120,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.description,
    this.action,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (action != null) ...[const SizedBox(width: AppSpacing.sm), action!],
    ],
  );
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    ),
  );
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.label,
    this.icon,
    this.onPressed,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    required this.label,
    this.icon,
    this.onPressed,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => icon == null
      ? OutlinedButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

enum RecoveryStatusVisual {
  verified,
  protected,
  possibleCopy,
  warning,
  corrupted,
  unavailable,
  error,
  currentMedia,
}

class RecoveryStatusChip extends StatelessWidget {
  const RecoveryStatusChip({required this.status, this.label, super.key});

  final RecoveryStatusVisual status;
  final String? label;

  static const _labels = {
    RecoveryStatusVisual.verified: 'Verified Deleted',
    RecoveryStatusVisual.protected: 'Protected',
    RecoveryStatusVisual.possibleCopy: 'Possible Copy',
    RecoveryStatusVisual.warning: 'Needs attention',
    RecoveryStatusVisual.corrupted: 'Damaged',
    RecoveryStatusVisual.unavailable: 'Unavailable',
    RecoveryStatusVisual.error: 'Error',
    RecoveryStatusVisual.currentMedia: 'Current media',
  };

  static const _icons = {
    RecoveryStatusVisual.verified: Icons.verified_outlined,
    RecoveryStatusVisual.protected: Icons.shield_outlined,
    RecoveryStatusVisual.possibleCopy: Icons.content_copy_outlined,
    RecoveryStatusVisual.warning: Icons.warning_amber_rounded,
    RecoveryStatusVisual.corrupted: Icons.broken_image_outlined,
    RecoveryStatusVisual.unavailable: Icons.block_outlined,
    RecoveryStatusVisual.error: Icons.error_outline,
    RecoveryStatusVisual.currentMedia: Icons.photo_outlined,
  };

  static const _colors = {
    RecoveryStatusVisual.verified: AppColors.verified,
    RecoveryStatusVisual.protected: AppColors.protected,
    RecoveryStatusVisual.possibleCopy: AppColors.possibleCopy,
    RecoveryStatusVisual.warning: AppColors.warning,
    RecoveryStatusVisual.corrupted: AppColors.corrupted,
    RecoveryStatusVisual.unavailable: AppColors.unavailable,
    RecoveryStatusVisual.error: AppColors.error,
    RecoveryStatusVisual.currentMedia: AppColors.currentMedia,
  };

  @override
  Widget build(BuildContext context) {
    final text = label ?? _labels[status]!;
    final color = _colors[status]!;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Chip(
        avatar: Icon(_icons[status], size: AppIconSizes.small, color: color),
        label: Text(text),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
        backgroundColor: color.withValues(alpha: .1),
        side: BorderSide(color: color.withValues(alpha: .28)),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class RecoveryCardShell extends StatelessWidget {
  const RecoveryCardShell({
    required this.title,
    required this.status,
    this.subtitle,
    this.leading,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final RecoveryStatusVisual status;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PremiumSurface(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox.square(dimension: 56, child: leading),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  RecoveryStatusChip(status: status),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => PremiumSurface(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}

class AppSkeleton extends StatelessWidget {
  const AppSkeleton({this.width, required this.height, super.key});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
    ),
  );
}

class AccessibleIconAction extends StatelessWidget {
  const AccessibleIconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));
}

class TonalSurface extends StatelessWidget {
  const TonalSurface({
    required this.child,
    required this.color,
    this.padding,
    super.key,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .10,
      ),
      borderRadius: BorderRadius.circular(AppRadii.large),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: child,
  );
}

class AppTonalIcon extends StatelessWidget {
  const AppTonalIcon({
    required this.icon,
    required this.color,
    this.size = AppIconSizes.medium,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .20 : .12,
      ),
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Icon(icon, size: size, color: color),
  );
}

class AppHeroSurface extends StatelessWidget {
  const AppHeroSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadii.large),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.primary, AppColors.primaryDark],
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: .20),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: child,
  );
}

class AppHeroButton extends StatelessWidget {
  const AppHeroButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
    style: FilledButton.styleFrom(
      foregroundColor: AppColors.primaryDark,
      backgroundColor: Colors.white,
      minimumSize: const Size(48, AppTouchTargets.minimum),
    ),
  );
}
