import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_breakpoints.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import 'recovery_source_intent.dart';

class RecoverSourceScreen extends StatelessWidget {
  const RecoverSourceScreen({
    required this.onSourceSelected,
    required this.onSettings,
    super.key,
  });

  final ValueChanged<RecoverySourceIntent> onSourceSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: CustomScrollView(
      key: const PageStorageKey('recover-source-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveContent(
            maxWidth: 920,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where were your photos?',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Choose one place to start a focused recovery.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AccessibleIconAction(
                      icon: Icons.settings_outlined,
                      label: 'Open settings',
                      onPressed: onSettings,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const TonalSurface(
                  color: AppColors.accent,
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      AppTonalIcon(
                        icon: Icons.verified_user_outlined,
                        color: AppColors.accent,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Existing photos and Possible Copies stay separate from Verified Deleted results.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = AppPhotoGrid.columnsFor(
                      constraints.maxWidth,
                      minimumWidth: 300,
                      gap: AppSpacing.md,
                    ).clamp(1, 2);
                    final cardWidth =
                        (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        for (final source in RecoverySourceIntent.values)
                          SizedBox(
                            width: cardWidth,
                            child: _RecoverySourceCard(
                              source: source,
                              onTap: () => onSourceSelected(source),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecoverySourceCard extends StatelessWidget {
  const _RecoverySourceCard({required this.source, required this.onTap});

  final RecoverySourceIntent source;
  final VoidCallback onTap;

  Color get _color => switch (source) {
    RecoverySourceIntent.cameraGallery => AppColors.primary,
    RecoverySourceIntent.messaging => AppColors.accent,
    RecoverySourceIntent.screenshotsDownloads => AppColors.protection,
    RecoverySourceIntent.scopedFolders => AppColors.warning,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: source.semanticLabel,
    child: TonalSurface(
      color: _color,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.large),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.large),
          child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTonalIcon(
                icon: source.icon,
                color: _color,
                size: AppIconSizes.large,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      source.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, color: _color),
            ],
          ),
          ),
        ),
      ),
    ),
  );
}
