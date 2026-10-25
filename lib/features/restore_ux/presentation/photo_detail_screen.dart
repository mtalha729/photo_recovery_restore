import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery_scan/presentation/recovery_thumbnail.dart';
import '../../recovery/domain/recovery_result_kind.dart';
import '../../recovery/domain/media_source.dart';
import '../application/restore_ux_coordinator.dart';
import '../application/restore_ux_models.dart';

class PhotoDetailScreen extends StatefulWidget {
  const PhotoDetailScreen({required this.item, this.coordinator, super.key});

  final RestoreReviewItem item;
  final RestoreUxCoordinator? coordinator;

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  bool _restoring = false;
  bool _restored = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.item.candidate;
    final aspectRatio =
        candidate.width != null &&
            candidate.height != null &&
            candidate.width! > 0 &&
            candidate.height! > 0
        ? candidate.width! / candidate.height!
        : 1.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 3,
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.large),
                          child: RecoveryThumbnail(
                            semanticLabel:
                                'Preview of ${candidate.displayName ?? 'photo'}',
                            requestedDimension: 512,
                            contentUri:
                                candidate.contentUri ?? candidate.documentUri,
                            filePath: candidate.filePath,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(switch (resultKindFor(candidate)) {
                RecoveryResultKind.verifiedDeleted => 'Verified deleted photo',
                RecoveryResultKind.possibleRecoverable =>
                  'Possible surviving copy · original deletion not confirmed',
                RecoveryResultKind.recoverableCopy =>
                  'Recoverable copy · original deletion not confirmed',
                RecoveryResultKind.cachedImage =>
                  'Cached image · original deletion not confirmed',
                RecoveryResultKind.thumbnail => 'Thumbnail available · only thumbnail resolution can be saved',
                RecoveryResultKind.existingPhoto =>
                  'Existing photo · save a separate copy',
                RecoveryResultKind.unavailableOrCorrupt =>
                  'Photo unavailable or invalid',
              }),
              if (candidate.relativeLocation case final folder?)
                Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                [
                  _sourceLabel(candidate.source),
                  if (candidate.width != null && candidate.height != null)
                    '${candidate.width} × ${candidate.height}',
                  if (candidate.byteSize != null)
                    _sizeLabel(candidate.byteSize!),
                ].join(' · '),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed:
                _restoring ||
                    _restored ||
                    !widget.item.isEligible ||
                    widget.coordinator == null
                ? null
                : _restore,
            child: _restoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _restored
                        ? (widget.item.route == RestoreRoute.fileCopy
                              ? 'Copy saved'
                              : 'Restored')
                        : (widget.item.route == RestoreRoute.fileCopy
                              ? 'Save a copy'
                              : 'Restore Photo'),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _restore() async {
    if (_restoring || _restored || widget.coordinator == null) return;
    setState(() => _restoring = true);
    final outcome = await widget.coordinator!.restore([widget.item]);
    if (!mounted) return;
    final matchingOutcomes = outcome.items
        .where((item) => item.itemId == widget.item.candidate.id)
        .toList(growable: false);
    final status = matchingOutcomes.isEmpty
        ? null
        : matchingOutcomes.first.status;
    if (status == RestoreOutcomeStatus.restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.item.route == RestoreRoute.fileCopy
                ? 'A verified copy was saved to Pictures/Photo Recovery & Restore.'
                : 'Photo restored successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (status == RestoreOutcomeStatus.alreadyPresent) {
      setState(() {
        _restoring = false;
        _restored = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo is already restored')),
      );
      return;
    }
    setState(() => _restoring = false);
    final message = switch (status) {
      RestoreOutcomeStatus.accessRequired =>
        'Storage access is needed to save this copy.',
      RestoreOutcomeStatus.insufficientStorage =>
        'There is not enough free storage to save this copy.',
      RestoreOutcomeStatus.verificationFailure ||
      RestoreOutcomeStatus.integrityFailure =>
        'The image could not be verified, so it was not saved.',
      RestoreOutcomeStatus.staleOrMissing =>
        'The original image is no longer available at its source location.',
      _ => "Couldn't save the photo. Please try again.",
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

String _sourceLabel(MediaSource source) => switch (source) {
  MediaSource.cameraGallery => 'Camera & Gallery',
  MediaSource.screenshots => 'Screenshots',
  MediaSource.downloadsSavedMedia => 'Downloads & Saved',
  MediaSource.messagingSharedMedia => 'WhatsApp & Messaging',
  MediaSource.sdCard => 'SD Card',
  MediaSource.recoveryShield => 'Recovery Shield',
  MediaSource.unknown => 'Other Photos',
};

String _sizeLabel(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class RestoreReviewSheet extends StatefulWidget {
  const RestoreReviewSheet({
    required this.items,
    required this.coordinator,
    super.key,
  });
  final List<RestoreReviewItem> items;
  final RestoreUxCoordinator coordinator;

  @override
  State<RestoreReviewSheet> createState() => _RestoreReviewSheetState();
}

class _RestoreReviewSheetState extends State<RestoreReviewSheet> {
  RestoreBatchOutcome? _outcome;
  bool _restoring = false;
  int _completed = 0;
  RestoreCancellationToken? _cancellation;

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligible = widget.items.where((item) => item.isEligible).length;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review restore',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('${widget.items.length} selected · $eligible eligible'),
                if (_restoring)
                  Text('$_completed of ${widget.items.length} processed'),
                for (final item in widget.items)
                  Text(
                    '${item.candidate.displayName ?? 'Photo'} → ${item.expectedDestination}',
                  ),
                if (_outcome != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    label: 'Restore results',
                    child: Text(_summary(_outcome!)),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppPrimaryButton(
                  label: _restoring ? 'Restoring…' : 'Confirm restore',
                  onPressed: !_restoring && _outcome == null && eligible > 0
                      ? _restore
                      : null,
                ),
                if (_restoring)
                  TextButton(
                    onPressed: _cancellation?.cancel,
                    child: const Text('Stop after current photo'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restore() async {
    final cancellation = RestoreCancellationToken();
    setState(() {
      _restoring = true;
      _cancellation = cancellation;
    });
    final result = await widget.coordinator.restore(
      widget.items,
      cancellation: cancellation,
      onProgress: (completed, _) {
        if (mounted) setState(() => _completed = completed);
      },
    );
    if (!mounted) return;
    setState(() {
      _outcome = result;
      _restoring = false;
      _cancellation = null;
    });
  }

  static String _summary(RestoreBatchOutcome value) {
    final parts = <String>['${value.items.length} selected'];
    final saved = value.count(RestoreOutcomeStatus.restored);
    for (final kind in RestoreSavedKind.values) {
      final count = value.items
          .where(
            (item) =>
                item.status == RestoreOutcomeStatus.restored &&
                item.savedKind == kind,
          )
          .length;
      if (count == 0) continue;
      parts.add(
        '$count ${switch (kind) {
          RestoreSavedKind.trash => 'restored from trash',
          RestoreSavedKind.recoverableCopy => 'recoverable copies saved',
          RestoreSavedKind.thumbnail => 'thumbnails saved',
          RestoreSavedKind.existingCopy => 'existing-photo copies saved',
          RestoreSavedKind.recoveryShield => 'Recovery Shield photos restored',
        }}',
      );
    }
    final skipped = value.count(RestoreOutcomeStatus.skippedDuplicate);
    if (skipped > 0) parts.add('$skipped duplicate skipped');
    final cancelled = value.count(RestoreOutcomeStatus.cancelled);
    if (cancelled > 0) parts.add('$cancelled cancelled');
    final failed = value.items.length - saved - skipped - cancelled;
    if (failed > 0) parts.add('$failed not saved');
    return parts.join(' · ');
  }
}
