import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_breakpoints.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/media_source.dart';
import '../../restore_ux/application/restore_ux_coordinator.dart';
import '../../restore_ux/application/restore_ux_models.dart';
import '../../restore_ux/presentation/photo_detail_screen.dart';
import '../application/recovery_scan_controller.dart';
import '../application/recovery_scan_models.dart';
import 'recovery_thumbnail.dart';

class RecoveryScanScreen extends StatefulWidget {
  const RecoveryScanScreen({
    required this.controller,
    this.onRestoreIntent,
    this.onRestoreReview,
    this.restoreCoordinator,
    super.key,
  });

  final RecoveryScanController controller;
  final ValueChanged<List<MediaCandidate>>? onRestoreIntent;
  final ValueChanged<List<RestoreReviewItem>>? onRestoreReview;
  final RestoreUxCoordinator? restoreCoordinator;

  @override
  State<RecoveryScanScreen> createState() => _RecoveryScanScreenState();
}

class _RecoveryScanScreenState extends State<RecoveryScanScreen>
    with WidgetsBindingObserver {
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.start();
    });
  }

  @override
  void didUpdateWidget(covariant RecoveryScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_refresh);
    widget.controller.addListener(_refresh);
    _selectedIds.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

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
                  label: 'Restore selected (${_selectedIds.length})',
                  icon: Icons.restore_rounded,
                  onPressed: () {
                    final selected = state.verifiedItems
                        .where((item) => _selectedIds.contains(item.id))
                        .toList(growable: false);
                    if (widget.onRestoreReview != null) {
                      widget.onRestoreReview!(
                        selected
                            .map(widget.controller.reviewItemFor)
                            .toList(growable: false),
                      );
                      return;
                    }
                    widget.onRestoreIntent?.call(selected);
                  },
                ),
              ),
            ),
    );
  }

  Widget _body(RecoveryScanViewState state) => switch (state.status) {
    RecoveryScanViewStatus.idle ||
    RecoveryScanViewStatus.running ||
    RecoveryScanViewStatus.cancelling => _ScanningState(
      state: state,
      onCancel: widget.controller.cancel,
    ),
    RecoveryScanViewStatus.cancelled => const _MessageState(
      icon: Icons.stop_circle_outlined,
      title: 'Scan cancelled',
      message: 'No incomplete scan is presented as a finished result.',
    ),
    RecoveryScanViewStatus.empty => _MessageState(
      icon: Icons.search_off_rounded,
      title: state.deepCapabilityMessage == null
          ? 'No recoverable photos found'
          : 'Photo scan complete',
      message: state.deepCapabilityMessage ?? 'No verified deleted photos or recoverable copies were found. Existing photos are never shown as deleted.',
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
    RecoveryScanViewStatus.complete => _ResultsState(
      state: state,
      selectedIds: _selectedIds,
      onSelectionChanged: (id, selected) => setState(() {
        selected ? _selectedIds.add(id) : _selectedIds.remove(id);
      }),
      onSelectAll: () => setState(() {
        _selectedIds.addAll(state.verifiedItems.map((item) => item.id));
      }),
      onClear: () => setState(_selectedIds.clear),
      onOpenDetails: _openDetails,
    ),
  };

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
            selectedCount == 0 ? source.label : '$selectedCount selected',
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
    RecoveryScanSource.customFolder => 'Other storage',
    RecoveryScanSource.allPhotos => 'Shared media',
  };
}

class _ResultsState extends StatefulWidget {
  const _ResultsState({
    required this.state,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.onSelectAll,
    required this.onClear,
    required this.onOpenDetails,
  });
  final RecoveryScanViewState state;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final ValueChanged<MediaCandidate> onOpenDetails;

  @override
  State<_ResultsState> createState() => _ResultsStateState();
}

class _ResultsStateState extends State<_ResultsState> {
  bool _deletedOnly = false;

  @override
  Widget build(BuildContext context) {
    final items = _deletedOnly
        ? widget.state.verifiedItems.where(
            (item) => item.isDeletedRecoveryResult,
          )
        : <MediaCandidate>[
            ...widget.state.verifiedItems,
            ...widget.state.possibleCopies,
          ];
    final groups = _sourceGroups(items);
    return ResponsiveContent(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: CustomScrollView(
        slivers: [
          if (widget.state.deepCapabilityMessage != null)
            SliverToBoxAdapter(
              child: PremiumSurface(
                child: Text(widget.state.deepCapabilityMessage!),
              ),
            ),
          if (widget.state.deepCapabilityMessage != null)
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          if (widget.state.isLimitedAccess)
            const SliverToBoxAdapter(
              child: PremiumSurface(
                child: Text(
                  'Limited photo access: only user-selected accessible photos were checked. This is not a full-library scan.',
                ),
              ),
            ),
          if (widget.state.isLimitedAccess)
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          SliverToBoxAdapter(
            child: AppSectionHeader(
              title: 'Results',
              description: _deletedOnly
                  ? 'Only items with verified deletion evidence are shown.'
                  : 'Deleted photos and surviving recoverable copies are separate.',
              action: widget.selectedIds.isEmpty
                  ? TextButton(
                      onPressed: widget.onSelectAll,
                      child: const Text('Select all'),
                    )
                  : TextButton(
                      onPressed: widget.onClear,
                      child: const Text('Clear'),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _ResultsSummary(
                verifiedDeletedCount: widget.state.verifiedItems.length,
                possibleCopyCount: widget.state.possibleCopies.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('All Recoveries')),
                  ButtonSegment(value: true, label: Text('Deleted Photos')),
                ],
                selected: {_deletedOnly},
                onSelectionChanged: (selection) =>
                    setState(() => _deletedOnly = selection.first),
              ),
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
                      onOpenDetails: widget.onOpenDetails,
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
                  Text(_groupSummary(group)),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        for (final item in group.items.take(4))
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.xs,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: RecoveryThumbnail(
                                  semanticLabel: '${group.label} preview',
                                  contentUri: item.contentUri,
                                  filePath: item.filePath,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _CategoryGridScreen extends StatelessWidget {
  const _CategoryGridScreen({required this.group, required this.onOpenDetails});
  final _SourceGroup group;
  final ValueChanged<MediaCandidate> onOpenDetails;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(group.label)),
    body: LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        slivers: [
          if (group.verifiedDeleted.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _ResultSectionHeader(
                title: 'Verified deleted',
                count: group.verifiedDeleted.length,
                description: 'Items with explicit deletion evidence',
              ),
            ),
            _ResultPhotoGrid(
              items: group.verifiedDeleted,
              crossAxisCount: AppPhotoGrid.columnsFor(
                constraints.maxWidth,
                minimumWidth: 150,
              ),
              onOpenDetails: onOpenDetails,
            ),
          ],
          if (group.possibleCopies.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _ResultSectionHeader(
                title: 'Possible copies',
                count: group.possibleCopies.length,
                description:
                    'Accessible copies, not verified deleted originals',
              ),
            ),
            _ResultPhotoGrid(
              items: group.possibleCopies,
              crossAxisCount: AppPhotoGrid.columnsFor(
                constraints.maxWidth,
                minimumWidth: 150,
              ),
              onOpenDetails: onOpenDetails,
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        ],
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
  });

  final List<MediaCandidate> items;
  final int crossAxisCount;
  final ValueChanged<MediaCandidate> onOpenDetails;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    sliver: SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = items[index];
        return Semantics(
          button: true,
          label: '${item.displayName ?? 'Photo'}, ${stateLabel(item)}',
          child: InkWell(
            onTap: () => onOpenDetails(item),
            child: RecoveryThumbnail(
              semanticLabel: '${item.displayName ?? 'Photo'} preview',
              contentUri: item.contentUri,
              filePath: item.filePath,
            ),
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
  'Downloads / Saved' => Icons.download_outlined,
  'Messaging' => Icons.forum_outlined,
  'Cache & Thumbnails' => Icons.collections_outlined,
  'App Media' => Icons.apps_outlined,
  'SD Card' => Icons.sd_card_outlined,
  _ => Icons.folder_outlined,
};

String stateLabel(MediaCandidate candidate) =>
    candidate.classification.isDeletedRecoveryResult
    ? 'Verified deleted'
    : 'Recoverable copy';

List<_SourceGroup> _sourceGroups(Iterable<MediaCandidate> candidates) {
  const order = [
    'Camera & Gallery',
    'Screenshots',
    'Downloads / Saved',
    'Messaging',
    'App Media',
    'Cache & Thumbnails',
    'Hidden / Other',
    'SD Card',
    'Unknown',
  ];
  final grouped = <String, List<MediaCandidate>>{};
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!seen.add(candidate.id)) continue;
    final label = _sourceLabel(candidate);
    (grouped[label] ??= []).add(candidate);
  }
  return [
    for (final label in order)
      if (grouped[label] case final items?)
        _SourceGroup(
          label: label,
          verifiedDeleted: List.unmodifiable(
            items.where((item) => item.isDeletedRecoveryResult).toList(),
          ),
          possibleCopies: List.unmodifiable(
            items.where((item) => !item.isDeletedRecoveryResult).toList(),
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
      candidate.discoveryEvidence.isThumbnailLike) {
    return 'Cache & Thumbnails';
  }
  final location = candidate.relativeLocation?.toLowerCase() ?? '';
  if (location.contains('android/media')) return 'App Media';
  if (candidate.discoveryEvidence.isHidden) return 'Hidden / Other';
  return switch (candidate.source) {
    MediaSource.cameraGallery => 'Camera & Gallery',
    MediaSource.screenshots => 'Screenshots',
    MediaSource.downloadsSavedMedia => 'Downloads / Saved',
    MediaSource.messagingSharedMedia => 'Messaging',
    MediaSource.sdCard || MediaSource.customFolder => 'SD Card',
    _ => 'Unknown',
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
