import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';

/// Explains the app's optional Android special access before opening the
/// system-owned All files access settings page.
class PhotoRecoveryAccessScreen extends StatefulWidget {
  const PhotoRecoveryAccessScreen({
    required this.provider,
    required this.onAccessAvailable,
    super.key,
  });

  final PlatformDeepStorageRecoveryProvider provider;
  final VoidCallback onAccessAvailable;

  @override
  State<PhotoRecoveryAccessScreen> createState() =>
      _PhotoRecoveryAccessScreenState();
}

class _PhotoRecoveryAccessScreenState extends State<PhotoRecoveryAccessScreen>
    with WidgetsBindingObserver {
  bool _openingSettings = false;
  bool _returnedFromSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _returnedFromSettings) {
      _checkAfterSettings();
    }
  }

  Future<void> _openSettings() async {
    setState(() => _openingSettings = true);
    try {
      await widget.provider.openAccessSettings();
      _returnedFromSettings = true;
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  Future<void> _checkAfterSettings() async {
    _returnedFromSettings = false;
    final capability = await widget.provider.getCapability();
    if (!mounted || !capability.available) return;
    widget.onAccessAvailable();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo Recovery Access')),
    body: SafeArea(
      child: ResponsiveContent(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: PremiumSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.manage_search_rounded,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Photo Recovery Access',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Allow broader storage access so Photo Recovery & Restore can search accessible storage for deleted, hidden and recoverable image copies.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppPrimaryButton(
                    label: _openingSettings
                        ? 'Opening settings…'
                        : 'Enable Photo Recovery Access',
                    onPressed: _openingSettings ? null : _openSettings,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
