import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../recovery_shield_manager.dart';

class RecoveryShieldScreen extends StatefulWidget {
  const RecoveryShieldScreen({required this.manager, super.key});
  final RecoveryShieldManager manager;

  @override
  State<RecoveryShieldScreen> createState() => _RecoveryShieldScreenState();
}

class _RecoveryShieldScreenState extends State<RecoveryShieldScreen> {
  RecoveryShieldSnapshot? _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final snapshot = await widget.manager.load();
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _protect() async {
    setState(() => _busy = true);
    final protected = await widget.manager.protectSelectedPhotos();
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (protected > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$protected photo${protected == 1 ? '' : 's'} protected.',
          ),
        ),
      );
    }
  }

  Future<void> _unprotect(ShieldManagedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove protected copy?'),
        content: const Text(
          'This removes only the Recovery Shield copy. The original photo is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove copy'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.manager.unprotect([item.protectionId]);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ResponsiveContent(
      maxWidth: 920,
      child: ListView(
        children: [
          const AppSectionHeader(
            title: 'Recovery Shield',
            description: 'Keep exact private copies of photos you choose, improving future recoverability.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_snapshot == null)
            const AppSkeleton(height: 150)
          else ...[
            TonalSurface(
              color: AppColors.protection,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const AppTonalIcon(
                        icon: Icons.shield_outlined,
                        color: AppColors.protection,
                        size: AppIconSizes.large,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          _snapshot!.protectedCount == 0
                              ? 'Shield is ready'
                              : '${_snapshot!.protectedCount} protected ${_snapshot!.protectedCount == 1 ? 'photo' : 'photos'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Private storage used: ${_formatBytes(_snapshot!.storageBytes)}',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Protection does not mean the original photo is deleted.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppPrimaryButton(
                    label: _busy ? 'Protecting…' : 'Protect selected photos',
                    icon: Icons.add_photo_alternate_outlined,
                    onPressed: _busy ? null : _protect,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_snapshot!.items.isEmpty)
              const AppEmptyState(
                icon: Icons.shield_outlined,
                title: 'No protected photos yet',
                message: 'Only photos you explicitly select are copied into Recovery Shield.',
              )
            else
              ..._snapshot!.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: PremiumSurface(
                    child: Row(
                      children: [
                        Icon(
                          item.integrityVerified
                              ? Icons.verified_outlined
                              : Icons.warning_amber_rounded,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName ?? 'Protected photo',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${_formatBytes(item.byteSize)} • ${item.integrityVerified ? 'Integrity verified' : 'Needs attention'}',
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove protected copy',
                          onPressed: () => _unprotect(item),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
