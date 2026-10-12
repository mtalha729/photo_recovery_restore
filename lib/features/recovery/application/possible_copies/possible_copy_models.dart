import '../../domain/media_candidate.dart';
import '../duplicate_resolution/duplicate_resolution_models.dart';
import '../recovery_evidence_classifier/recovery_classification_decision.dart';

enum PossibleCopyType {
  alternateFullQuality,
  lowerResolution,
  thumbnailSized,
  accessibleCachedRepresentation,
  explicitlyRelatedAlternate,
  unknownQualityAlternate,
}

enum PossibleCopyRelationshipEvidence {
  explicitRelationship,
  verifiedContentDigest,
  trustedPlatformMetadata,
}

class PossibleCopyRelationship {
  const PossibleCopyRelationship({
    required this.originalCandidateId,
    required this.copyCandidateId,
    required this.type,
    required this.evidence,
  });

  final String originalCandidateId;
  final String copyCandidateId;
  final PossibleCopyType type;
  final PossibleCopyRelationshipEvidence evidence;
}

class PossibleCopyRepresentation {
  const PossibleCopyRepresentation({
    required this.candidate,
    required this.classificationDecision,
    required this.type,
    required this.relationshipEvidence,
    required this.duplicateRecordCount,
  });

  final MediaCandidate candidate;
  final RecoveryClassificationDecision classificationDecision;
  final PossibleCopyType type;
  final Set<PossibleCopyRelationshipEvidence> relationshipEvidence;
  final int duplicateRecordCount;
}

class PossibleCopyGroup {
  const PossibleCopyGroup({
    required this.verifiedDeletedCandidate,
    required this.copies,
    required this.bestCopyCandidate,
    required this.bestCopySelectionCategory,
  });

  final MediaCandidate verifiedDeletedCandidate;
  final List<PossibleCopyRepresentation> copies;
  final MediaCandidate bestCopyCandidate;
  final BestCopySelectionCategory bestCopySelectionCategory;
}

class PossibleCopiesDiscoveryResult {
  const PossibleCopiesDiscoveryResult({
    required this.groups,
    required this.verifiedDeletedCount,
  });

  final List<PossibleCopyGroup> groups;
  final int verifiedDeletedCount;

  int get possibleCopyCount =>
      groups.fold(0, (count, group) => count + group.copies.length);
}
