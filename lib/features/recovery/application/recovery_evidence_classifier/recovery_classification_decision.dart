import '../../domain/deletion_evidence.dart';
import '../../domain/recovery_classification.dart';

enum RecoveryClassificationReason {
  definiteExistingIdentity,
  protectedCopyEvidence,
  verifiedSystemTrashEvidence,
  explicitCorruptionState,
  explicitPossibleCopyState,
  explicitUnavailableState,
  insufficientEvidence,
}

class RecoveryClassificationDecision {
  RecoveryClassificationDecision({
    required this.classification,
    required this.reason,
    Iterable<DeletionEvidenceReason> deletionEvidence = const [],
  }) : deletionEvidence = Set.unmodifiable(deletionEvidence);

  final RecoveryClassification classification;
  final RecoveryClassificationReason reason;
  final Set<DeletionEvidenceReason> deletionEvidence;

  bool get isEligibleForVerifiedDeletedResults =>
      classification == RecoveryClassification.verifiedDeleted;

  bool get isProtectedCopy =>
      classification == RecoveryClassification.protectedCopy;

  bool get belongsOnlyInPossibleCopies =>
      classification == RecoveryClassification.possibleCopy;

  bool get mustBeExcludedFromRecoveryResults =>
      classification == RecoveryClassification.existingMedia;

  bool get hasContradictoryDeletionEvidence =>
      mustBeExcludedFromRecoveryResults &&
      deletionEvidence.contains(DeletionEvidenceReason.systemTrashRecord);
}
