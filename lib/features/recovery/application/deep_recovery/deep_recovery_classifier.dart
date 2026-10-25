import '../../domain/media_candidate.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import '../existing_media_exclusion/existing_media_exclusion_models.dart';
import '../possible_copies/possible_copy_models.dart';
import '../recovery_evidence_classifier/recovery_evidence_classifier.dart';

/// Exhaustive-scan presentation buckets. These do not replace the core
/// recovery classification or manufacture deletion evidence.
enum DeepRecoveryDisposition {
  verifiedDeleted,
  protectedCopy,
  possibleFullQualityCopy,
  possibleLowerQualityCopy,
  possibleUnknownQualityCopy,
  thumbnailCopy,
  existingMedia,
  corrupted,
  unavailable,
  unclassified,
}

class DeepRecoveryClassifier {
  const DeepRecoveryClassifier({
    this.evidenceClassifier = const RecoveryEvidenceClassifier(),
  });

  final RecoveryEvidenceClassifier evidenceClassifier;

  DeepRecoveryDisposition classify({
    required MediaCandidate candidate,
    required ExistingMediaDecision existingMediaDecision,
    PossibleCopyType? provenCopyType,
  }) {
    final decision = evidenceClassifier.classify(
      candidate: candidate,
      existingMediaDecision: existingMediaDecision,
    );
    if (decision.classification == RecoveryClassification.existingMedia) {
      return DeepRecoveryDisposition.existingMedia;
    }
    if (decision.classification == RecoveryClassification.verifiedDeleted) {
      return DeepRecoveryDisposition.verifiedDeleted;
    }
    if (decision.classification == RecoveryClassification.protectedCopy) {
      return DeepRecoveryDisposition.protectedCopy;
    }
    if (decision.classification == RecoveryClassification.corrupted) {
      return DeepRecoveryDisposition.corrupted;
    }
    if (decision.classification == RecoveryClassification.unavailable) {
      return DeepRecoveryDisposition.unavailable;
    }
    if (decision.classification != RecoveryClassification.possibleCopy &&
        provenCopyType == null) {
      return DeepRecoveryDisposition.unclassified;
    }
    return switch (provenCopyType) {
      PossibleCopyType.alternateFullQuality =>
        DeepRecoveryDisposition.possibleFullQualityCopy,
      PossibleCopyType.lowerResolution =>
        DeepRecoveryDisposition.possibleLowerQualityCopy,
      PossibleCopyType.thumbnailSized => DeepRecoveryDisposition.thumbnailCopy,
      PossibleCopyType.accessibleCachedRepresentation ||
      PossibleCopyType.explicitlyRelatedAlternate ||
      PossibleCopyType.unknownQualityAlternate => _copyQuality(candidate),
      null => _copyQuality(candidate),
    };
  }

  DeepRecoveryDisposition _copyQuality(MediaCandidate candidate) {
    if (candidate.restoreCapability ==
            RestoreCapability.alternateFullQualityCopy ||
        candidate.recoveryQuality == RecoveryQuality.completeCopy) {
      return DeepRecoveryDisposition.possibleFullQualityCopy;
    }
    final width = candidate.width;
    final height = candidate.height;
    if (candidate.restoreCapability == RestoreCapability.unknownQualityCopy ||
        candidate.recoveryQuality == RecoveryQuality.unknownQualityCopy) {
      return DeepRecoveryDisposition.possibleUnknownQualityCopy;
    }
    if (candidate.restoreCapability == RestoreCapability.lowerResolutionCopy ||
        candidate.recoveryQuality == RecoveryQuality.reducedResolutionCopy) {
      if (width != null && height != null && width <= 512 && height <= 512) {
        return DeepRecoveryDisposition.thumbnailCopy;
      }
      return DeepRecoveryDisposition.possibleLowerQualityCopy;
    }
    return DeepRecoveryDisposition.unclassified;
  }
}
