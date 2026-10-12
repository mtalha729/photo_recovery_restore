import 'package:flutter/material.dart';

import '../../../app/design_system/components/adaptive_shell.dart';
import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';

class DevelopmentHomePage extends StatelessWidget {
  const DevelopmentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveAppShell(
      body: SafeArea(
        child: ResponsiveContent(
          child: Center(
            child: PremiumSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Photo Recovery & Restore',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Development build',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
