import '../../domain/deletion_evidence.dart';
import '../../domain/media_candidate.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import '../existing_media_exclusion/existing_media_exclusion_models.dart';
import 'recovery_classification_decision.dart';

class RecoveryEvidenceClassifier {
  const RecoveryEvidenceClassifier();

  RecoveryClassificationDecision classify({
    required MediaCandidate candidate,
    required ExistingMediaDecision existingMediaDecision,
  }) {
    final evidence = candidate.deletionEvidence.reasons;

    if (existingMediaDecision.type ==
        ExistingMediaDecisionType.definitelyExisting) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.existingMedia,
        reason: RecoveryClassificationReason.definiteExistingIdentity,
        deletionEvidence: evidence,
      );
    }

    // A Recovery Shield object is the protected surviving copy itself. Even
    // if source-level metadata carries a trash marker, that marker cannot be
    // transferred to the backup and presented as proof that the backup was
    // deleted.
    if (candidate.discoveryEvidence.isRecoveryShieldBackup) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.protectedCopy,
        reason: RecoveryClassificationReason.protectedCopyEvidence,
        deletionEvidence: evidence,
      );
    }

    if (evidence.contains(DeletionEvidenceReason.systemTrashRecord)) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.verifiedDeleted,
        reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
        deletionEvidence: evidence,
      );
    }

    if (candidate.classification == RecoveryClassification.corrupted ||
        candidate.recoveryQuality == RecoveryQuality.corrupted) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.corrupted,
        reason: RecoveryClassificationReason.explicitCorruptionState,
        deletionEvidence: evidence,
      );
    }

    if (_hasExplicitCopyState(candidate)) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.possibleCopy,
        reason: RecoveryClassificationReason.explicitPossibleCopyState,
        deletionEvidence: evidence,
      );
    }

    if (candidate.classification == RecoveryClassification.unavailable ||
        evidence.contains(DeletionEvidenceReason.sourceNoLongerAvailable)) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.unavailable,
        reason: RecoveryClassificationReason.explicitUnavailableState,
        deletionEvidence: evidence,
      );
    }

    // A valid, directly readable file found by deep discovery is surviving
    // media, not deletion evidence. It can be offered only as a copy.
    if (candidate.filePath != null &&
        candidate.discoveryEvidence.detectedFormat != null) {
      return RecoveryClassificationDecision(
        classification: RecoveryClassification.possibleCopy,
        reason: RecoveryClassificationReason.explicitPossibleCopyState,
        deletionEvidence: evidence,
      );
    }

    return RecoveryClassificationDecision(
      classification: RecoveryClassification.unclassified,
      reason: RecoveryClassificationReason.insufficientEvidence,
      deletionEvidence: evidence,
    );
  }

  bool _hasExplicitCopyState(MediaCandidate candidate) {
    return candidate.classification == RecoveryClassification.possibleCopy ||
        candidate.recoveryQuality == RecoveryQuality.completeCopy ||
        candidate.recoveryQuality == RecoveryQuality.reducedResolutionCopy ||
        candidate.recoveryQuality == RecoveryQuality.unknownQualityCopy ||
        candidate.restoreCapability ==
            RestoreCapability.alternateFullQualityCopy ||
        candidate.restoreCapability == RestoreCapability.lowerResolutionCopy ||
        candidate.restoreCapability == RestoreCapability.unknownQualityCopy;
  }
}
