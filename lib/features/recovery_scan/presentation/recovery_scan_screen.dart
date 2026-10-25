import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_breakpoints.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/recovery_result_kind.dart';
import '../../recovery/domain/media_source.dart';
import '../../restore_ux/application/restore_ux_coordinator.dart';
import '../../restore_ux/application/restore_ux_models.dart';
import '../../restore_ux/presentation/photo_detail_screen.dart';
import '../application/recovery_scan_controller.dart';
import '../application/recovery_scan_models.dart';
import 'recovery_thumbnail.dart';
import 'photo_recovery_access_screen.dart';

class RecoveryScanScreen extends StatefulWidget {
  const RecoveryScanScreen({
    required this.controller,
    this.onRestoreIntent,
    this.onRestoreReview,
    this.restoreCoordinator,
    this.startImmediately = true,
    super.key,
  });

  final RecoveryScanController controller;
  final bool startImmediately;
  final ValueChanged<List<MediaCandidate>>? onRestoreIntent;
  final ValueChanged<List<RestoreReviewItem>>? onRestoreReview;
  final RestoreUxCoordinator? restoreCoordinator;

  @override
  State<RecoveryScanScreen> createState() => _RecoveryScanScreenState();
}

class _RecoveryScanScreenState extends State<RecoveryScanScreen>
    with WidgetsBindingObserver {
  final Set<String> _selectedIds = {};
  List<MediaCandidate>? _groupVerifiedItems;
  List<MediaCandidate>? _groupPossibleCopies;
  List<_SourceGroup>? _cachedGroups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_refresh);
    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startWithStorageAccess();
      });
    }
  }

  @override
  void didUpdateWidget(covariant RecoveryScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      oldWidget.controller.cancel();
      widget.controller.addListener(_refresh);
      _selectedIds.clear();
      _cachedGroups = null;
    }
    if (widget.startImmediately &&
        (!oldWidget.startImmediately ||
            oldWidget.controller != widget.controller)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startWithStorageAccess();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_refresh);
    widget.controller.cancel();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _startWithStorageAccess() async {
    const provider = PlatformDeepStorageRecoveryProvider();
    final capability = await provider.getCapability();
    if (!mounted) return;
    if (capability.requestSupported &&
        capability.mode != DeepStorageAccessMode.allFilesAccess) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (accessContext) => PhotoRecoveryAccessScreen(
            provider: provider,
            onAccessAvailable: () => Navigator.of(accessContext).pop(),
          ),
        ),
      );
      if (!mounted) return;
    }
    await widget.controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.retryDeepScanAfterResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ScanTopBar(
              source: state.source,
              selectedCount: _selectedIds.length,
            ),
            Expanded(child: _body(state)),
          ],
        ),
      ),
      bottomNavigationBar: _selectedIds.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppPrimaryButton(
                  label: _selectedActionLabel(state),
                  icon: Icons.restore_rounded,
                  onPressed: () {
                    final selected =
                        <MediaCandidate>[
                              ...state.verifiedItems,
                              ...state.possibleCopies,
                            ]
                            .where((item) => _selectedIds.contains(item.id))
                            .toList(growable: false);
                    _reviewSelected(selected);
                  },
                ),
              ),
            ),
    );
  }

  void _reviewSelected(List<MediaCandidate> selected) {
    if (widget.onRestoreReview != null) {
      widget.onRestoreReview!(
        selected.map(widget.controller.reviewItemFor).toList(growable: false),
      );
      return;
    }
    widget.onRestoreIntent?.call(selected);
  }

  String _selectedActionLabel(RecoveryScanViewState state) {
    final selected = <MediaCandidate>[
      ...state.verifiedItems,
      ...state.possibleCopies,
    ].where((item) => _selectedIds.contains(item.id)).toList(growable: false);
    final copyCount = selected
        .where(
          (item) =>
              item.classification == RecoveryClassification.possibleCopy ||
              item.classification == RecoveryClassification.existingMedia,
        )
        .length;
    if (selected.isNotEmpty && copyCount == selected.length) {
      return 'Save copies (${selected.length})';
    }
    if (copyCount > 0) return 'Review selected (${selected.length})';
    return 'Restore selected (${selected.length})';
  }

  Widget _body(RecoveryScanViewState state) => switch (state.status) {
    RecoveryScanViewStatus.idle => _ScanningState(
      state: state,
      onCancel: widget.controller.cancel,
    ),
    RecoveryScanViewStatus.running || RecoveryScanViewStatus.cancelling =>
      state.verifiedItems.isNotEmpty || state.possibleCopies.isNotEmpty
          ? _resultsView(state, isScanning: true)
          : _ScanningState(state: state, onCancel: widget.controller.cancel),
    RecoveryScanViewStatus.cancelled =>
      state.verifiedItems.isNotEmpty || state.possibleCopies.isNotEmpty
          ? _resultsView(state)
          : _MessageState(
              icon: Icons.stop_circle_outlined,
              title: 'Scan cancelled',
              message:
                  state.message ??
                  'The scan was cancelled. Any completed results are retained.',
            ),
    RecoveryScanViewStatus.empty => _MessageState(
      icon: Icons.search_off_rounded,
      title: 'No recoverable photos found',
      message: state.message?.isNotEmpty == true ? state.message! : 'No recoverable photos were found in the locations available to this device. Existing photos are never shown as deleted.',
    ),
    RecoveryScanViewStatus.emptyRestricted => _MessageState(
      icon: Icons.info_outline_rounded,
      title: 'Scan complete',
      message: state.message?.isNotEmpty == true ? state.message! : 'No recoverable photos were found. Some protected locations could not be checked.',
    ),
    RecoveryScanViewStatus.partial =>
      state.verifiedItems.isNotEmpty || state.possibleCopies.isNotEmpty
          ? _resultsView(state)
          : _MessageState(
              icon: Icons.warning_amber_rounded,
              title: 'Scan ended with partial coverage',
              message:
                  state.message ??
                  'Coverage was partial. Results already found are retained.',
            ),
    RecoveryScanViewStatus.unsupported => const _MessageState(
      icon: Icons.info_outline_rounded,
      title: 'This scan is not supported',
      message: 'Deleted-photo discovery is unavailable for this source.',
    ),
    RecoveryScanViewStatus.accessUnavailable => _MessageState(
      icon: Icons.lock_outline_rounded,
      title: 'Media access required',
      message: state.message ?? 'Access is unavailable for this source.',
    ),
    RecoveryScanViewStatus.deepAccessRequired => _DeepAccessState(
      message:
          state.message ??
          'Photo Recovery Access is required for the full scan.',
      onEnable: widget.controller.openDeepScanSettings,
    ),
    RecoveryScanViewStatus.failure => _MessageState(
      icon: Icons.error_outline_rounded,
      title: 'Scan could not finish',
      message: state.message ?? 'Try again when the source is available.',
    ),
    RecoveryScanViewStatus.complete ||
    RecoveryScanViewStatus.completeRestricted => _resultsView(state),
  };

  Widget _resultsView(RecoveryScanViewState state, {bool isScanning = false}) =>
      _ResultsState(
        state: state,
        controller: widget.controller,
        currentGroups: () => _groupsFor(widget.controller.state),
        groups: _groupsFor(state),
        isScanning: isScanning,
        onCancel: widget.controller.cancel,
        selectedIds: _selectedIds,
        onSelectionChanged: (id, selected) => setState(() {
          selected ? _selectedIds.add(id) : _selectedIds.remove(id);
        }),
        onSelectionBatch: (ids, selected) => setState(() {
          selected ? _selectedIds.addAll(ids) : _selectedIds.removeAll(ids);
        }),
        onSelectAll: () => setState(() {
          _selectedIds.addAll([
            ...state.verifiedItems.map((item) => item.id),
            ...state.possibleCopies.map((item) => item.id),
          ]);
        }),
        onClear: () => setState(_selectedIds.clear),
        onOpenDetails: _openDetails,
        onReviewSelected: _reviewSelected,
      );

  List<_SourceGroup> _groupsFor(RecoveryScanViewState state) {
    if (_cachedGroups != null &&
        identical(_groupVerifiedItems, state.verifiedItems) &&
        identical(_groupPossibleCopies, state.possibleCopies)) {
      return _cachedGroups!;
    }
    final groups = _sourceGroups([
      ...state.verifiedItems,
      ...state.possibleCopies,
    ]);
    _groupVerifiedItems = state.verifiedItems;
    _groupPossibleCopies = state.possibleCopies;
    _cachedGroups = groups;
    return groups;
  }

  Future<void> _openDetails(MediaCandidate candidate) async {
    final item = widget.controller.reviewItemFor(candidate);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PhotoDetailScreen(
          item: item,
          coordinator: widget.restoreCoordinator,
        ),
      ),
    );
  }
}

class _ScanTopBar extends StatelessWidget {
  const _ScanTopBar({required this.source, required this.selectedCount});
  final RecoveryScanSource source;
  final int selectedCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    child: Row(
      children: [
        AccessibleIconAction(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            selectedCount == 0 ? 'Results' : '$selectedCount selected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    ),
  );
}

class _ScanningState extends StatelessWidget {
  const _ScanningState({required this.state, required this.onCancel});
  final RecoveryScanViewState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ResponsiveContent(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSpacing.md,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: PremiumSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _ScanProgressPanel(state: state, onCancel: onCancel),
        ),
      ),
    ),
  );
}

class _ScanProgressPanel extends StatelessWidget {
  const _ScanProgressPanel({required this.state, required this.onCancel});

  final RecoveryScanViewState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelling = state.status == RecoveryScanViewStatus.cancelling;
    final headline = _scanHeadline(state);
    final currentArea = _friendlyScanArea(state);

    return Semantics(
      liveRegion: true,
      label: cancelling ? 'Stopping scan safely.' : '$headline. $currentArea.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ScanActivityIndicator(cancelling: cancelling),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cancelling ? 'Stopping safely…' : headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      currentArea,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      cancelling
                          ? 'Keeping completed work safe'
                          : 'Searching accessible photo locations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: const LinearProgressIndicator(minHeight: 6),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ScanStatistics(state: state),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppSecondaryButton(
              label: cancelling ? 'Cancelling' : 'Cancel scan',
              onPressed: cancelling ? null : onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanStatistics extends StatelessWidget {
  const _ScanStatistics({required this.state});

  final RecoveryScanViewState state;

  @override
  Widget build(BuildContext context) {
    final statistics = [
      _ScanStatistic('${state.progress.processedCount}', 'photos checked'),
      _ScanStatistic('${state.deepCandidatesFound}', 'possible recoveries'),
      _ScanStatistic(
        '${state.progress.discoveredVerifiedCount}',
        'verified deleted',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 460 ? 3 : 1;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.xs) / columns;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final statistic in statistics)
              SizedBox(width: itemWidth, child: _ScanStatisticTile(statistic)),
          ],
        );
      },
    );
  }
}

class _ScanActivityIndicator extends StatelessWidget {
  const _ScanActivityIndicator({required this.cancelling});

  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: cancelling ? 'Stopping scan' : 'Scan in progress',
      child: ExcludeSemantics(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.large),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
              Icon(
                cancelling ? Icons.pause_rounded : Icons.image_search_rounded,
                size: AppIconSizes.medium,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanStatistic {
  const _ScanStatistic(this.value, this.description);

  final String value;
  final String description;
}

class _ScanStatisticTile extends StatelessWidget {
  const _ScanStatisticTile(this.statistic);

  final _ScanStatistic statistic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '${statistic.value} ${statistic.description}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .36),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Text(
            '${statistic.value} ${statistic.description}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}

String _scanHeadline(RecoveryScanViewState state) {
  if (state.scanPhase.toLowerCase().contains('selected folder')) {
    return 'Scanning a folder you chose';
  }
  if (state.scanPhase.toLowerCase().contains('deep')) {
    final area = (state.currentScanArea ?? '').toLowerCase();
    if (area.contains('cache') ||
        area.contains('thumb') ||
        area.contains('hidden') ||
        area.contains('preview')) {
      return 'Checking cached and hidden images';
    }
    if (area.contains('shared app') ||
        area.contains('android/media') ||
        area.contains('messag')) {
      return 'Searching shared media';
    }
    if (area.contains('trash')) return 'Looking for recoverable copies';
    return 'Reviewing storage';
  }
  return 'Scanning your photos';
}

String _friendlyScanArea(RecoveryScanViewState state) {
  final area = (state.currentScanArea ?? '').toLowerCase();
  if (area.contains('waiting for folder')) return 'Folder selection';
  if (area.contains('user-authorized folder')) return 'Selected folder';
  if (area.contains('screenshot')) return 'Screenshots';
  if (area.contains('download')) return 'Downloads';
  if (area.contains('messag') ||
      area.contains('whatsapp') ||
      area.contains('telegram') ||
      area.contains('signal') ||
      area.contains('viber')) {
    return 'Messaging';
  }
  if (area.contains('cache') ||
      area.contains('thumb') ||
      area.contains('hidden') ||
      area.contains('preview')) {
    return 'Cached images';
  }
  if (area.contains('shared app') || area.contains('android/media')) {
    return 'Shared app media';
  }
  if (area.contains('sd') || area.contains('removable')) return 'SD card';
  if (area.contains('camera') ||
      area.contains('dcim') ||
      area.contains('gallery') ||
      area.contains('pictures')) {
    return 'Camera & Gallery';
  }
  if (area.isNotEmpty) return 'Other storage';

  return switch (state.source) {
    RecoveryScanSource.cameraGallery => 'Camera & Gallery',
    RecoveryScanSource.screenshots => 'Screenshots',
    RecoveryScanSource.downloads => 'Downloads',
    RecoveryScanSource.messaging => 'Messaging',
    RecoveryScanSource.sdCard => 'SD card',
    RecoveryScanSource.allPhotos => 'Shared media',
  };
}

class _CompactScanProgress extends StatelessWidget {
  const _CompactScanProgress({required this.state, required this.onCancel});

  final RecoveryScanViewState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => PremiumSurface(
    child: Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scanning photos',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${state.progress.processedCount} checked · ${state.verifiedItems.length + state.possibleCopies.length} found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    ),
  );
}

class _CoverageNotice extends StatelessWidget {
  const _CoverageNotice();

  @override
  Widget build(BuildContext context) => PremiumSurface(
    child: Text(
      'Some locations could not be checked. Photos already found are still available.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _ResultsState extends StatelessWidget {
  const _ResultsState({
    required this.state,
    required this.controller,
    required this.currentGroups,
    required this.groups,
    required this.isScanning,
    required this.onCancel,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onSelectionBatch,
    required this.onSelectAll,
    required this.onClear,
    required this.onOpenDetails,
    required this.onReviewSelected,
  });
  final RecoveryScanViewState state;
  final RecoveryScanController controller;
  final List<_SourceGroup> Function() currentGroups;
  final List<_SourceGroup> groups;
  final bool isScanning;
  final VoidCallback onCancel;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(Iterable<String> ids, bool selected) onSelectionBatch;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final ValueChanged<MediaCandidate> onOpenDetails;
  final ValueChanged<List<MediaCandidate>> onReviewSelected;

  @override
  Widget build(BuildContext context) {
    return ResponsiveContent(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: CustomScrollView(
        slivers: [
          if (isScanning)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _CompactScanProgress(state: state, onCancel: onCancel),
              ),
            ),
          if (!isScanning &&
              (state.status == RecoveryScanViewStatus.partial ||
                  state.status == RecoveryScanViewStatus.completeRestricted ||
                  state.isLimitedAccess))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: const _CoverageNotice(),
              ),
            ),
          SliverToBoxAdapter(
            child: AppSectionHeader(
              title: 'Deleted Photos',
              description: 'Verified deletions and possible surviving copies are separate; a possible copy is not confirmed deleted.',
              action: selectedIds.isEmpty
                  ? TextButton(
                      onPressed: onSelectAll,
                      child: const Text('Select all'),
                    )
                  : TextButton(onPressed: onClear, child: const Text('Clear')),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _ResultsSummary(
                verifiedDeletedCount: state.verifiedItems.length,
                possibleCopyCount: state.possibleCopies.length,
              ),
            ),
          ),
          if (groups.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('No recovery candidates found yet.'),
              ),
            ),
          for (final group in groups) ...[
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
            SliverToBoxAdapter(
              child: _CategoryCard(
                group: group,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => _CategoryGridScreen(
                      group: group,
                      controller: controller,
                      currentGroup: () => currentGroups()
                          .where((value) => value.label == group.label)
                          .firstOrNull,
                      onOpenDetails: onOpenDetails,
                      selectedIds: selectedIds,
                      onSelectionChanged: onSelectionChanged,
                      onSelectionBatch: onSelectionBatch,
                      onReviewSelected: onReviewSelected,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultsSummary extends StatelessWidget {
  const _ResultsSummary({
    required this.verifiedDeletedCount,
    required this.possibleCopyCount,
  });

  final int verifiedDeletedCount;
  final int possibleCopyCount;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.xs,
    children: [
      Text('Recovery candidates  ${verifiedDeletedCount + possibleCopyCount}'),
      Semantics(
        label: '$verifiedDeletedCount verified deleted photos',
        child: Text(
          'Verified Deleted  $verifiedDeletedCount',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      if (possibleCopyCount > 0)
        Semantics(
          label: '$possibleCopyCount recoverable copies, not verified deleted',
          child: Text(
            'Recoverable Copies  $possibleCopyCount',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
    ],
  );
}

class _SourceGroup {
  const _SourceGroup({
    required this.label,
    required this.verifiedDeleted,
    required this.possibleCopies,
  });

  final String label;
  final List<MediaCandidate> verifiedDeleted;
  final List<MediaCandidate> possibleCopies;

  List<MediaCandidate> get items => [...verifiedDeleted, ...possibleCopies];
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.group, required this.onTap});
  final _SourceGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${group.label}, ${group.items.length} photos',
    child: PremiumSurface(
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              _categoryIcon(group.label),
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${group.items.length} photos · ${_groupSummary(group)}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final visible = (constraints.maxWidth / 60).floor().clamp(
                        1,
                        4,
                      );
                      return SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            for (final indexed
                                in group.items.take(visible).indexed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.xs,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        RecoveryThumbnail(
                                          semanticLabel:
                                              '${group.label} preview',
                                          contentUri:
                                              indexed.$2.contentUri ??
                                              indexed.$2.documentUri,
                                          filePath: indexed.$2.filePath,
                                        ),
                                        if (indexed.$1 == visible - 1 &&
                                            group.items.length > visible)
                                          ColoredBox(
                                            color: Colors.black54,
                                            child: Center(
                                              child: Text(
                                                '+${group.items.length - visible}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _CategoryGridScreen extends StatefulWidget {
  const _CategoryGridScreen({
    required this.group,
    required this.controller,
    required this.currentGroup,
    required this.onOpenDetails,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onSelectionBatch,
    required this.onReviewSelected,
  });
  final _SourceGroup group;
  final RecoveryScanController controller;
  final _SourceGroup? Function() currentGroup;
  final ValueChanged<MediaCandidate> onOpenDetails;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(Iterable<String> ids, bool selected) onSelectionBatch;
  final ValueChanged<List<MediaCandidate>> onReviewSelected;

  @override
  State<_CategoryGridScreen> createState() => _CategoryGridScreenState();
}

class _CategoryGridScreenState extends State<_CategoryGridScreen> {
  late final Set<String> _selectedIds = widget.group.items
      .where((item) => widget.selectedIds.contains(item.id))
      .map((item) => item.id)
      .toSet();

  void _toggle(String id, bool selected) {
    setState(() => selected ? _selectedIds.add(id) : _selectedIds.remove(id));
    widget.onSelectionChanged(id, selected);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final group = widget.currentGroup() ?? widget.group;
      return _buildGrid(context, group);
    },
  );

  Widget _buildGrid(BuildContext context, _SourceGroup group) => Scaffold(
    appBar: AppBar(
      title: Text(group.label),
      actions: [
        TextButton(
          onPressed: () {
            final visibleIds = group.items.map((item) => item.id).toSet();
            final allSelected = visibleIds.every(_selectedIds.contains);
            setState(() {
              if (allSelected) {
                _selectedIds.removeAll(visibleIds);
              } else {
                _selectedIds.addAll(visibleIds);
              }
            });
            widget.onSelectionBatch(visibleIds, !allSelected);
          },
          child: Text(
            group.items.every((item) => _selectedIds.contains(item.id))
                ? 'Deselect all'
                : 'Select all',
          ),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ResultSectionHeader(
              title: 'Photos',
              count: group.items.length,
              description: 'Each photo retains its actual status in details.',
            ),
          ),
          _ResultPhotoGrid(
            items: group.items,
            crossAxisCount: AppPhotoGrid.columnsFor(
              constraints.maxWidth,
              minimumWidth: 150,
            ),
            onOpenDetails: widget.onOpenDetails,
            selectedIds: _selectedIds,
            onSelectionChanged: _toggle,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
      ),
    ),
    bottomNavigationBar: _selectedIds.isEmpty
        ? null
        : SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.md),
            child: AppPrimaryButton(
              label: 'Review selected (${_selectedIds.length})',
              icon: Icons.restore_rounded,
              onPressed: () => widget.onReviewSelected(
                group.items
                    .where((item) => _selectedIds.contains(item.id))
                    .toList(growable: false),
              ),
            ),
          ),
  );
}

class _ResultSectionHeader extends StatelessWidget {
  const _ResultSectionHeader({
    required this.title,
    required this.count,
    required this.description,
  });

  final String title;
  final int count;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Semantics(
      header: true,
      label: '$title, $count photos. $description',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title  $count',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _ResultPhotoGrid extends StatelessWidget {
  const _ResultPhotoGrid({
    required this.items,
    required this.crossAxisCount,
    required this.onOpenDetails,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final List<MediaCandidate> items;
  final int crossAxisCount;
  final ValueChanged<MediaCandidate> onOpenDetails;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    sliver: SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = items[index];
        return Semantics(
          key: ValueKey(item.id),
          button: true,
          label: '${item.displayName ?? 'Photo'}, ${stateLabel(item)}',
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                onTap: () => onOpenDetails(item),
                child: RecoveryThumbnail(
                  semanticLabel: '${item.displayName ?? 'Photo'} preview',
                  contentUri: item.contentUri ?? item.documentUri,
                  filePath: item.filePath,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Checkbox(
                  value: selectedIds.contains(item.id),
                  onChanged: (value) =>
                      onSelectionChanged(item.id, value ?? false),
                ),
              ),
            ],
          ),
        );
      }, childCount: items.length),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
    ),
  );
}

IconData _categoryIcon(String label) => switch (label) {
  'Camera & Gallery' => Icons.photo_camera_outlined,
  'Screenshots' => Icons.screenshot_outlined,
  'Downloads & Saved' => Icons.download_outlined,
  'WhatsApp & Messaging' => Icons.forum_outlined,
  'Thumbnails & Cache' => Icons.collections_outlined,
  'Hidden Images' => Icons.visibility_off_outlined,
  'SD Card' => Icons.sd_card_outlined,
  _ => Icons.folder_outlined,
};

String stateLabel(MediaCandidate candidate) =>
    switch (resultKindFor(candidate)) {
      RecoveryResultKind.verifiedDeleted => 'Verified deleted',
      RecoveryResultKind.possibleRecoverable =>
        'Possible copy, deletion not confirmed',
      RecoveryResultKind.recoverableCopy => 'Recoverable copy',
      RecoveryResultKind.cachedImage => 'Cached image, deletion not confirmed',
      RecoveryResultKind.thumbnail =>
        'Thumbnail copy, original quality unavailable',
      RecoveryResultKind.existingPhoto => 'Existing photo',
      RecoveryResultKind.unavailableOrCorrupt => 'Unavailable or invalid image',
    };

List<_SourceGroup> _sourceGroups(Iterable<MediaCandidate> candidates) {
  const order = [
    'Camera & Gallery',
    'Screenshots',
    'WhatsApp & Messaging',
    'Downloads & Saved',
    'Thumbnails & Cache',
    'Hidden Images',
    'SD Card',
    'Other Recovery Images',
  ];
  final grouped = <String, List<MediaCandidate>>{};
  final seen = <String>{};
  for (final candidate in candidates) {
    final identity =
        candidate.contentUri?.toString() ??
        candidate.documentUri?.toString() ??
        candidate.filePath ??
        candidate.id;
    if (!seen.add(identity)) continue;
    final key = _sourceLabel(candidate);
    (grouped[key] ??= []).add(candidate);
  }
  return [
    for (final key in order)
      if (grouped[key] case final items?)
        _SourceGroup(
          label: key,
          verifiedDeleted: List.unmodifiable(
            items.where((item) => item.isDeletedRecoveryResult).toList(),
          ),
          possibleCopies: List.unmodifiable(
            items
                .where(
                  (item) =>
                      item.classification ==
                      RecoveryClassification.possibleCopy,
                )
                .toList(),
          ),
        ),
  ];
}

String _groupSummary(_SourceGroup group) {
  final segments = <String>[];
  if (group.verifiedDeleted.isNotEmpty) {
    segments.add('${group.verifiedDeleted.length} verified deleted');
  }
  if (group.possibleCopies.isNotEmpty) {
    segments.add(
      '${group.possibleCopies.length} possible ${group.possibleCopies.length == 1 ? 'copy' : 'copies'}',
    );
  }
  return segments.join(' • ');
}

String _sourceLabel(MediaCandidate candidate) {
  if (candidate.discoveryEvidence.isCacheLike ||
      candidate.discoveryEvidence.isThumbnailLike ||
      (candidate.relativeLocation ?? '').toLowerCase().contains(
        '.thumbnails',
      )) {
    return 'Thumbnails & Cache';
  }
  if (candidate.discoveryEvidence.isHidden ||
      (candidate.relativeLocation ?? '')
          .split('/')
          .any((part) => part.startsWith('.'))) {
    return 'Hidden Images';
  }
  return switch (candidate.source) {
    MediaSource.cameraGallery => 'Camera & Gallery',
    MediaSource.screenshots => 'Screenshots',
    MediaSource.downloadsSavedMedia => 'Downloads & Saved',
    MediaSource.messagingSharedMedia => 'WhatsApp & Messaging',
    MediaSource.sdCard => 'SD Card',
    _ => 'Other Recovery Images',
  };
}

class _DeepAccessState extends StatelessWidget {
  const _DeepAccessState({required this.message, required this.onEnable});
  final String message;
  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) => ResponsiveContent(
    child: Center(
      child: AppEmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Photo Recovery Access required',
        message: message,
        action: AppPrimaryButton(
          label: 'Enable Photo Recovery Access',
          onPressed: onEnable,
        ),
      ),
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ResponsiveContent(
    child: Center(
      child: AppEmptyState(icon: icon, title: title, message: message),
    ),
  );
}
