import '../../domain/deletion_evidence.dart';
import '../../domain/recovery_classification.dart';

enum RecoveryClassificationReason {
  definiteExistingIdentity,
  protectedDeletionEvidence,
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
      classification == RecoveryClassification.verifiedDeleted ||
      classification == RecoveryClassification.protectedDeleted;

  bool get belongsOnlyInPossibleCopies =>
      classification == RecoveryClassification.possibleCopy;

  bool get mustBeExcludedFromRecoveryResults =>
      classification == RecoveryClassification.existingMedia;

  bool get hasContradictoryDeletionEvidence =>
      mustBeExcludedFromRecoveryResults &&
      (deletionEvidence.contains(DeletionEvidenceReason.systemTrashRecord) ||
          deletionEvidence.contains(
            DeletionEvidenceReason.recoveryShieldRecord,
          ));
}
