import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovered_photos/application/recovered_photos_store.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_index.dart';
import '../../recovery/application/recovery_shield/recovery_shield_models.dart';
import '../../recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import '../../recovery/application/recovery_shield_restore/recovery_shield_restore_policy.dart';
import '../../recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import '../../recovery/data/folder_scope/folder_scope_selector.dart';
import '../../recovery/data/folder_scope/platform_folder_scope_selector.dart';
import '../../recovery/data/recovery_shield_restore/platform_recovery_shield_restorer.dart';
import '../../recovery/data/recovery_shield_restore/recovery_shield_restorer.dart';
import '../../recovery/domain/deletion_evidence.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/media_source.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/recovery_discovery_evidence.dart';
import '../../recovery/domain/recovery_quality.dart';
import '../../recovery/domain/restore_capability.dart';
import '../recovery_shield_manager.dart';

class RecoveryShieldScreen extends StatefulWidget {
  const RecoveryShieldScreen({
    required this.manager,
    this.restorer,
    this.folderScopeSelector,
    this.recoveredPhotosStore,
    super.key,
  });

  final RecoveryShieldManager manager;
  final RecoveryShieldRestorer? restorer;
  final FolderScopeSelector? folderScopeSelector;
  final RecoveredPhotosStore? recoveredPhotosStore;

  @override
  State<RecoveryShieldScreen> createState() => _RecoveryShieldScreenState();
}

class _RecoveryShieldScreenState extends State<RecoveryShieldScreen> {
  RecoveryShieldSnapshot? _snapshot;
  bool _busy = false;

  RecoveryShieldRestorer get _restorer =>
      widget.restorer ?? PlatformRecoveryShieldRestorer();
  FolderScopeSelector get _folderScopeSelector =>
      widget.folderScopeSelector ?? const PlatformFolderScopeSelector();
  RecoveredPhotosStore get _recoveredPhotosStore =>
      widget.recoveredPhotosStore ?? PlatformRecoveredPhotosStore();

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
    try {
      final protected = await widget.manager.protectSelectedPhotos();
      await _refresh();
      if (mounted && protected > 0) {
        _showMessage('$protected photo${protected == 1 ? '' : 's'} protected.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to protect the selected photos.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      final removed = await widget.manager.unprotect([item.protectionId]);
      await _refresh();
      if (mounted && !removed) {
        _showMessage('Unable to remove the protected copy.');
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to remove the protected copy.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(ShieldManagedItem item) async {
    if (_busy) return;
    final record = item.record;
    if (!item.integrityVerified || record == null) {
      _showMessage('This protected copy cannot be safely restored yet.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore protected copy?'),
        content: const Text(
          'This saves a new, verified image copy. It does not mean the original was deleted, and it may create a duplicate if the original is still available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.restore),
            label: const Text('Save a copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final candidate = _candidateFor(record);
      final existingMediaIndex = ExistingMediaIndex.build(records: const []);
      AuthorizedFolderScope? scope;
      if (record.originalSource == MediaSource.sdCard) {
        final selection = await _folderScopeSelector.selectDestinationFolder();
        if (selection.status != FolderScopeSelectionStatus.selected ||
            selection.scope == null) {
          if (mounted &&
              selection.status != FolderScopeSelectionStatus.cancelled) {
            _showMessage(
              selection.message ??
                  'Choose a writable, authorized SD-card folder to continue.',
            );
          }
          return;
        }
        scope = selection.scope;
      }

      final preparation = const RecoveryShieldRestorePolicy().prepare(
        record: record,
        originalCandidate: candidate,
        existingMediaIndex: existingMediaIndex,
        authorizedDestinationScope: scope,
      );
      final rejection = preparation.rejection;
      if (rejection != null) {
        if (mounted) _showMessage(_restoreMessage(rejection));
        return;
      }

      final result = await _restorer.restore(preparation.request!);
      if (result.isSuccessful &&
          result.restoredContentUri?.scheme == 'content') {
        await _recoveredPhotosStore.upsert(
          RecoveredPhotoRecord.fromCandidate(
            contentUri: result.restoredContentUri!,
            candidate: candidate,
            restoredAt: DateTime.now(),
          ),
        );
      }
      if (mounted) {
        _showMessage(
          result.isSuccessful && result.restoredContentUri?.scheme != 'content'
              ? 'Unable to verify the restored copy.'
              : _restoreMessage(result),
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to restore the protected copy.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  MediaCandidate _candidateFor(ProtectedMediaRecord record) => MediaCandidate(
    id: 'shield:${record.protectionId}',
    source: record.originalSource,
    contentUri: record.originalContentUri,
    displayName: record.displayName,
    mimeType: record.mimeType,
    relativeLocation: record.originalLocation,
    byteSize: record.byteSize,
    width: record.width,
    height: record.height,
    createdAt: record.createdAt,
    modifiedAt: record.modifiedAt,
    takenAt: record.takenAt,
    discoveryEvidence: const RecoveryDiscoveryEvidence(
      isRecoveryShieldBackup: true,
    ),
    classification: RecoveryClassification.protectedCopy,
    deletionEvidence: DeletionEvidence(),
    restoreCapability: RestoreCapability.protectedOriginal,
    recoveryQuality: RecoveryQuality.original,
  );

  String _restoreMessage(RecoveryShieldRestoreResult result) {
    if (result.message?.trim().isNotEmpty == true) return result.message!;
    return switch (result.status) {
      RecoveryShieldRestoreStatus.restored =>
        'A verified copy was saved. The original was not marked as deleted.',
      RecoveryShieldRestoreStatus.alreadyPresent =>
        'A matching original appears to be available; no copy was saved.',
      RecoveryShieldRestoreStatus.destinationRequired =>
        'Choose a writable, authorized destination folder before restoring.',
      RecoveryShieldRestoreStatus.accessRequired => 'Destination access is unavailable. Choose an authorized folder and try again.',
      RecoveryShieldRestoreStatus.insufficientStorage =>
        'There is not enough storage to save this copy.',
      RecoveryShieldRestoreStatus.integrityFailure ||
      RecoveryShieldRestoreStatus.verificationFailure => 'Image verification failed. Check the destination for an incomplete file before retrying.',
      RecoveryShieldRestoreStatus.protectedCopyMissing =>
        'The protected copy is no longer available.',
      RecoveryShieldRestoreStatus.writeFailure =>
        'The copy could not be written to the destination.',
      RecoveryShieldRestoreStatus.operationInProgress =>
        'A restore for this protected copy is already in progress.',
      RecoveryShieldRestoreStatus.notEligible ||
      RecoveryShieldRestoreStatus.platformFailure =>
        'Unable to restore the protected copy.',
    };
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
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
                      label: _busy ? 'Working…' : 'Protect selected photos',
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
                            item.integrityVerified && item.record != null
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${_formatBytes(item.byteSize)} • ${item.integrityVerified && item.record != null ? 'Integrity verified' : 'Needs attention'}',
                                ),
                                if (item.integrityVerified)
                                  const Text(
                                    'Protected copy — not deletion evidence',
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Restore protected copy',
                            onPressed:
                                _busy ||
                                    !item.integrityVerified ||
                                    item.record == null
                                ? null
                                : () => _restore(item),
                            icon: const Icon(Icons.restore),
                          ),
                          IconButton(
                            tooltip: 'Remove protected copy',
                            onPressed: _busy ? null : () => _unprotect(item),
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
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
