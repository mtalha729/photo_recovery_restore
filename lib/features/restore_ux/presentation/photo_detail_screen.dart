import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery_scan/presentation/recovery_thumbnail.dart';
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
    final aspectRatio = candidate.width != null &&
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.large),
                  child: RecoveryThumbnail(
                    semanticLabel:
                        'Preview of ${candidate.displayName ?? 'photo'}',
                    requestedDimension: 512,
                    contentUri: candidate.contentUri,
                    filePath: candidate.filePath,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
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
            onPressed: _restoring || _restored || !widget.item.isEligible ||
                    widget.coordinator == null
                ? null
                : _restore,
            child: _restoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_restored ? 'Restored' : 'Restore Photo'),
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
    final status =
        matchingOutcomes.isEmpty ? null : matchingOutcomes.first.status;
    if (status == RestoreOutcomeStatus.restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo restored successfully')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't restore photo. Please try again.")),
    );
  }
}
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
                  onPressed: !_restoring && eligible > 0 ? _restore : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final result = await widget.coordinator.restore(widget.items);
    if (!mounted) return;
    setState(() {
      _outcome = result;
      _restoring = false;
    });
  }

  static String _summary(RestoreBatchOutcome value) {
    final parts = <String>[];
    for (final status in RestoreOutcomeStatus.values) {
      final count = value.count(status);
      if (count > 0) parts.add('$count ${status.name}');
    }
    return parts.join(' · ');
  }
}
