import '../../domain/media_candidate.dart';
import '../../domain/restore_capability.dart';
import '../duplicate_resolution/duplicate_best_copy_resolver.dart';
import '../duplicate_resolution/duplicate_resolution_models.dart';
import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../recovery_evidence_classifier/recovery_evidence_classifier.dart';
import '../recovery_evidence_classifier/recovery_classification_decision.dart';
import 'possible_copy_models.dart';

class PossibleCopiesDiscovery {
  const PossibleCopiesDiscovery({
    this.exclusionEngine = const ExistingMediaExclusionEngine(),
    this.classifier = const RecoveryEvidenceClassifier(),
    this.copyResolver = const DuplicateBestCopyResolver(),
  });

  final ExistingMediaExclusionEngine exclusionEngine;
  final RecoveryEvidenceClassifier classifier;
  final DuplicateBestCopyResolver copyResolver;

  PossibleCopiesDiscoveryResult discover({
    required Iterable<MediaCandidate> verifiedDeletedCandidates,
    required Iterable<MediaCandidate> accessibleCandidates,
    required ExistingMediaIndex existingMediaIndex,
    Iterable<PossibleCopyRelationship> relationships = const [],
  }) {
    final deletedById = <String, MediaCandidate>{};
    for (final candidate in verifiedDeletedCandidates) {
      final decision = classifier.classify(
        candidate: candidate,
        existingMediaDecision: exclusionEngine.evaluate(
          candidate,
          existingMediaIndex,
        ),
      );
      if (decision.isEligibleForVerifiedDeletedResults) {
        deletedById[candidate.id] = candidate;
      }
    }

    final accessibleById = <String, MediaCandidate>{
      for (final candidate in accessibleCandidates) candidate.id: candidate,
    };
    final relationshipsByDeleted = <String, List<PossibleCopyRelationship>>{};
    for (final relationship in relationships) {
      final original = deletedById[relationship.originalCandidateId];
      final copy = accessibleById[relationship.copyCandidateId];
      if (original == null || copy == null || original.source != copy.source) {
        continue;
      }
      (relationshipsByDeleted[original.id] ??= []).add(relationship);
    }

    final digestCopies = <String, List<MediaCandidate>>{};
    for (final copy in accessibleById.values) {
      final digest = copy.verifiedContentDigest?.identityKey;
      if (digest != null) {
        (digestCopies[digest] ??= []).add(copy);
      }
    }
    for (final original in deletedById.values) {
      final digest = original.verifiedContentDigest?.identityKey;
      if (digest == null) continue;
      for (final copy in digestCopies[digest] ?? const []) {
        if (copy.source != original.source) continue;
        (relationshipsByDeleted[original.id] ??= []).add(
          PossibleCopyRelationship(
            originalCandidateId: original.id,
            copyCandidateId: copy.id,
            type: _typeFor(copy),
            evidence: PossibleCopyRelationshipEvidence.verifiedContentDigest,
          ),
        );
      }
    }

    final groups = <PossibleCopyGroup>[];
    final sortedDeleted = deletedById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final original in sortedDeleted) {
      final relationshipsForOriginal = relationshipsByDeleted[original.id];
      if (relationshipsForOriginal == null) continue;
      final evidenceByCopy = <String, Set<PossibleCopyRelationshipEvidence>>{};
      final typeByCopy = <String, PossibleCopyType>{};
      for (final relationship in relationshipsForOriginal) {
        (evidenceByCopy[relationship.copyCandidateId] ??= {}).add(
          relationship.evidence,
        );
        typeByCopy.putIfAbsent(
          relationship.copyCandidateId,
          () => relationship.type,
        );
      }

      final eligibleCopies = <MediaCandidate>[];
      final decisions = <String, RecoveryClassificationDecision>{};
      for (final id in evidenceByCopy.keys) {
        final copy = accessibleById[id]!;
        final decision = classifier.classify(
          candidate: copy,
          existingMediaDecision: exclusionEngine.evaluate(
            copy,
            existingMediaIndex,
          ),
        );
        if (decision.isEligibleForVerifiedDeletedResults) continue;
        eligibleCopies.add(copy);
        decisions[id] = decision;
      }
      if (eligibleCopies.isEmpty) continue;

      final copyResolution = copyResolver.resolve(candidates: eligibleCopies);
      final representations = <PossibleCopyRepresentation>[];
      for (final group in copyResolution.groups) {
        final representative = group.canonicalCandidate;
        final ids = group.allCandidates.map((value) => value.id);
        final evidence = <PossibleCopyRelationshipEvidence>{
          for (final id in ids) ...?evidenceByCopy[id],
        };
        final types = ids.map((id) => typeByCopy[id]!).toSet();
        representations.add(
          PossibleCopyRepresentation(
            candidate: representative,
            classificationDecision: decisions[representative.id]!,
            type: _strongestType(types),
            relationshipEvidence: Set.unmodifiable(evidence),
            duplicateRecordCount: group.groupedRecordCount,
          ),
        );
      }
      representations.sort((a, b) => a.candidate.id.compareTo(b.candidate.id));

      final bestResolution = copyResolver.resolve(
        candidates: [
          original,
          ...representations.map((value) => value.candidate),
        ],
        relationships: [
          for (final copy in representations)
            CopyRelationship(
              firstCandidateId: original.id,
              secondCandidateId: copy.candidate.id,
              type: CopyRelationshipType.alternateVariant,
            ),
        ],
      );
      final bestGroup = bestResolution.groups.single;
      groups.add(
        PossibleCopyGroup(
          verifiedDeletedCandidate: original,
          copies: List.unmodifiable(representations),
          bestCopyCandidate: bestGroup.canonicalCandidate,
          bestCopySelectionCategory: bestGroup.selectionCategory,
        ),
      );
    }

    return PossibleCopiesDiscoveryResult(
      groups: List.unmodifiable(groups),
      verifiedDeletedCount: deletedById.length,
    );
  }

  PossibleCopyType _typeFor(MediaCandidate candidate) {
    if (candidate.restoreCapability ==
        RestoreCapability.alternateFullQualityCopy) {
      return PossibleCopyType.alternateFullQuality;
    }
    if (candidate.restoreCapability == RestoreCapability.lowerResolutionCopy) {
      final width = candidate.width;
      final height = candidate.height;
      if (width != null && height != null && width <= 512 && height <= 512) {
        return PossibleCopyType.thumbnailSized;
      }
      return PossibleCopyType.lowerResolution;
    }
    return PossibleCopyType.unknownQualityAlternate;
  }

  PossibleCopyType _strongestType(Set<PossibleCopyType> values) {
    const order = [
      PossibleCopyType.alternateFullQuality,
      PossibleCopyType.explicitlyRelatedAlternate,
      PossibleCopyType.lowerResolution,
      PossibleCopyType.thumbnailSized,
      PossibleCopyType.accessibleCachedRepresentation,
      PossibleCopyType.unknownQualityAlternate,
    ];
    return order.firstWhere(values.contains);
  }
}
