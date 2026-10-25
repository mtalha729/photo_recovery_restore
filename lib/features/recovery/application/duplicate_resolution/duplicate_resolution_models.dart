import '../../domain/media_candidate.dart';

enum CopyRelationshipType { alternateVariant }

class CopyRelationship {
  const CopyRelationship({
    required this.firstCandidateId,
    required this.secondCandidateId,
    required this.type,
  });

  final String firstCandidateId;
  final String secondCandidateId;
  final CopyRelationshipType type;
}

enum DuplicateGroupingEvidence {
  stablePlatformIdentity,
  verifiedContentDigest,
  explicitRelatedVariant,
}

enum BestCopySelectionCategory {
  intactOriginal,
  protectedOriginal,
  alternateFullQuality,
  lowerResolution,
  unknownQuality,
  metadataOnly,
  unusable,
}

class ResolvedCopyGroup {
  const ResolvedCopyGroup({
    required this.canonicalCandidate,
    required this.confirmedExactDuplicates,
    required this.alternateVariants,
    required this.groupingEvidence,
    required this.selectionCategory,
  });

  final MediaCandidate canonicalCandidate;
  final List<MediaCandidate> confirmedExactDuplicates;
  final List<MediaCandidate> alternateVariants;
  final Set<DuplicateGroupingEvidence> groupingEvidence;
  final BestCopySelectionCategory selectionCategory;

  int get groupedRecordCount =>
      1 + confirmedExactDuplicates.length + alternateVariants.length;

  List<MediaCandidate> get allCandidates => List.unmodifiable([
    canonicalCandidate,
    ...confirmedExactDuplicates,
    ...alternateVariants,
  ]);
}

class DuplicateResolutionResult {
  const DuplicateResolutionResult({required this.groups});

  final List<ResolvedCopyGroup> groups;

  int get uniquePhotoCount => groups.length;
  int get inputRecordCount =>
      groups.fold(0, (total, group) => total + group.groupedRecordCount);
}
