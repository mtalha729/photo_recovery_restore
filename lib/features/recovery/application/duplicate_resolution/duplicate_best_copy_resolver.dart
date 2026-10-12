import '../../domain/media_candidate.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import 'duplicate_resolution_models.dart';

class DuplicateBestCopyResolver {
  const DuplicateBestCopyResolver();

  DuplicateResolutionResult resolve({
    required Iterable<MediaCandidate> candidates,
    Iterable<CopyRelationship> relationships = const [],
  }) {
    final byId = <String, MediaCandidate>{};
    for (final candidate in candidates) {
      if (byId.containsKey(candidate.id)) {
        throw ArgumentError.value(candidate.id, 'candidates', 'Duplicate ID');
      }
      byId[candidate.id] = candidate;
    }

    final allGroups = <ResolvedCopyGroup>[];
    final bySource = <Object, List<MediaCandidate>>{};
    for (final candidate in byId.values) {
      (bySource[candidate.source] ??= []).add(candidate);
    }

    for (final sourceCandidates in bySource.values) {
      final sourceIds = {for (final value in sourceCandidates) value.id};
      final exact = _DisjointSet(sourceIds);
      final related = _DisjointSet(sourceIds);
      final evidenceByCandidate = <String, Set<DuplicateGroupingEvidence>>{};
      final identityIndex = <String, String>{};
      final digestIndex = <String, String>{};

      for (final candidate in sourceCandidates) {
        final identity = _stableIdentity(candidate);
        if (identity != null) {
          final prior = identityIndex[identity];
          if (prior == null) {
            identityIndex[identity] = candidate.id;
          } else {
            exact.union(prior, candidate.id);
            related.union(prior, candidate.id);
            _addEvidence(
              evidenceByCandidate,
              prior,
              candidate.id,
              DuplicateGroupingEvidence.stablePlatformIdentity,
            );
          }
        }
        final digest = candidate.verifiedContentDigest?.identityKey;
        if (digest != null) {
          final prior = digestIndex[digest];
          if (prior == null) {
            digestIndex[digest] = candidate.id;
          } else {
            exact.union(prior, candidate.id);
            related.union(prior, candidate.id);
            _addEvidence(
              evidenceByCandidate,
              prior,
              candidate.id,
              DuplicateGroupingEvidence.verifiedContentDigest,
            );
          }
        }
      }

      for (final relationship in relationships) {
        if (!sourceIds.contains(relationship.firstCandidateId) ||
            !sourceIds.contains(relationship.secondCandidateId)) {
          continue;
        }
        related.union(
          relationship.firstCandidateId,
          relationship.secondCandidateId,
        );
        _addEvidence(
          evidenceByCandidate,
          relationship.firstCandidateId,
          relationship.secondCandidateId,
          DuplicateGroupingEvidence.explicitRelatedVariant,
        );
      }

      final components = <String, List<MediaCandidate>>{};
      for (final candidate in sourceCandidates) {
        (components[related.find(candidate.id)] ??= []).add(candidate);
      }
      for (final component in components.values) {
        component.sort(_compareBest);
        final best = component.first;
        final bestExactRoot = exact.find(best.id);
        final exactDuplicates =
            component
                .where(
                  (value) =>
                      value.id != best.id &&
                      exact.find(value.id) == bestExactRoot,
                )
                .toList()
              ..sort((a, b) => a.id.compareTo(b.id));
        final exactIds = {best.id, ...exactDuplicates.map((value) => value.id)};
        final variants =
            component.where((value) => !exactIds.contains(value.id)).toList()
              ..sort(_compareBest);
        final groupEvidence = <DuplicateGroupingEvidence>{};
        for (final candidate in component) {
          groupEvidence.addAll(evidenceByCandidate[candidate.id] ?? const {});
        }
        allGroups.add(
          ResolvedCopyGroup(
            canonicalCandidate: best,
            confirmedExactDuplicates: List.unmodifiable(exactDuplicates),
            alternateVariants: List.unmodifiable(variants),
            groupingEvidence: Set.unmodifiable(groupEvidence),
            selectionCategory: _category(best),
          ),
        );
      }
    }

    allGroups.sort(
      (a, b) => a.canonicalCandidate.id.compareTo(b.canonicalCandidate.id),
    );
    return DuplicateResolutionResult(groups: List.unmodifiable(allGroups));
  }

  String? _stableIdentity(MediaCandidate candidate) {
    final uri = candidate.contentUri?.toString().trim();
    if (uri != null && uri.isNotEmpty) return 'uri:$uri';
    final volume = candidate.storageVolumeName?.trim().toLowerCase();
    final id = candidate.mediaStoreId;
    return volume != null && volume.isNotEmpty && id != null && id >= 0
        ? 'media:$volume:$id'
        : null;
  }

  void _addEvidence(
    Map<String, Set<DuplicateGroupingEvidence>> index,
    String first,
    String second,
    DuplicateGroupingEvidence evidence,
  ) {
    (index[first] ??= {}).add(evidence);
    (index[second] ??= {}).add(evidence);
  }

  int _compareBest(MediaCandidate a, MediaCandidate b) {
    final category = _category(a).index.compareTo(_category(b).index);
    if (category != 0) return category;
    final quality = _qualityRank(a).compareTo(_qualityRank(b));
    if (quality != 0) return quality;
    final pixels = _pixels(b).compareTo(_pixels(a));
    if (pixels != 0) return pixels;
    final bytes = (b.byteSize ?? -1).compareTo(a.byteSize ?? -1);
    if (bytes != 0) return bytes;
    return a.id.compareTo(b.id);
  }

  BestCopySelectionCategory _category(MediaCandidate candidate) {
    if (_isUnusable(candidate)) return BestCopySelectionCategory.unusable;
    return switch (candidate.restoreCapability) {
      RestoreCapability.originalFullQuality =>
        BestCopySelectionCategory.intactOriginal,
      RestoreCapability.protectedOriginal =>
        BestCopySelectionCategory.protectedOriginal,
      RestoreCapability.alternateFullQualityCopy =>
        BestCopySelectionCategory.alternateFullQuality,
      RestoreCapability.lowerResolutionCopy =>
        BestCopySelectionCategory.lowerResolution,
      RestoreCapability.metadataOnly => BestCopySelectionCategory.metadataOnly,
      RestoreCapability.notRestorable => BestCopySelectionCategory.unusable,
    };
  }

  bool _isUnusable(MediaCandidate candidate) =>
      candidate.classification == RecoveryClassification.corrupted ||
      candidate.classification == RecoveryClassification.unavailable ||
      candidate.recoveryQuality == RecoveryQuality.corrupted ||
      candidate.recoveryQuality == RecoveryQuality.unavailable ||
      candidate.restoreCapability == RestoreCapability.notRestorable;

  int _qualityRank(MediaCandidate candidate) =>
      switch (candidate.recoveryQuality) {
        RecoveryQuality.original => 0,
        RecoveryQuality.completeCopy => 1,
        RecoveryQuality.reducedResolutionCopy => 2,
        RecoveryQuality.metadataOnly => 3,
        RecoveryQuality.unavailable => 4,
        RecoveryQuality.corrupted => 5,
      };

  int _pixels(MediaCandidate candidate) {
    final width = candidate.width;
    final height = candidate.height;
    return width != null && width > 0 && height != null && height > 0
        ? width * height
        : -1;
  }
}

class _DisjointSet {
  _DisjointSet(Iterable<String> values)
    : _parent = {for (final value in values) value: value};

  final Map<String, String> _parent;

  String find(String value) {
    final parent = _parent[value]!;
    if (parent == value) return value;
    return _parent[value] = find(parent);
  }

  void union(String first, String second) {
    final firstRoot = find(first);
    final secondRoot = find(second);
    if (firstRoot == secondRoot) return;
    if (firstRoot.compareTo(secondRoot) <= 0) {
      _parent[secondRoot] = firstRoot;
    } else {
      _parent[firstRoot] = secondRoot;
    }
  }
}
