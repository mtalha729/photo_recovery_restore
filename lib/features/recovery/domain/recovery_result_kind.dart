import 'media_candidate.dart';
import 'recovery_classification.dart';
import 'recovery_quality.dart';

enum RecoveryResultKind {
  verifiedDeleted,
  possibleRecoverable,
  recoverableCopy,
  cachedImage,
  thumbnail,
  existingPhoto,
  unavailableOrCorrupt,
}

RecoveryResultKind resultKindFor(MediaCandidate candidate) {
  switch (candidate.classification) {
    case RecoveryClassification.verifiedDeleted:
      return RecoveryResultKind.verifiedDeleted;
    case RecoveryClassification.existingMedia:
      return RecoveryResultKind.existingPhoto;
    case RecoveryClassification.unavailable:
    case RecoveryClassification.corrupted:
    case RecoveryClassification.unclassified:
      return RecoveryResultKind.unavailableOrCorrupt;
    case RecoveryClassification.protectedCopy:
      return RecoveryResultKind.recoverableCopy;
    case RecoveryClassification.possibleCopy:
      if (candidate.discoveryEvidence.isThumbnailLike) {
        return RecoveryResultKind.thumbnail;
      }
      if (candidate.discoveryEvidence.isCacheLike) {
        return RecoveryResultKind.cachedImage;
      }
      if (candidate.recoveryQuality == RecoveryQuality.completeCopy ||
          candidate.recoveryQuality == RecoveryQuality.reducedResolutionCopy) {
        return RecoveryResultKind.recoverableCopy;
      }
      return RecoveryResultKind.possibleRecoverable;
  }
}
