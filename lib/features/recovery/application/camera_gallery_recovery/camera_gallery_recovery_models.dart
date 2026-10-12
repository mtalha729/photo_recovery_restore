import '../../domain/media_candidate.dart';
import '../recovery_evidence_classifier/recovery_classification_decision.dart';
import '../restore/system_trash_restore_models.dart';

class CameraGalleryRecoveryItem {
  const CameraGalleryRecoveryItem({
    required this.candidate,
    required this.classificationDecision,
    required this.restoreEligibility,
  });

  final MediaCandidate candidate;
  final RecoveryClassificationDecision classificationDecision;
  final SystemTrashRestoreEligibility restoreEligibility;
}

class CameraGalleryRecoveryDiagnostics {
  const CameraGalleryRecoveryDiagnostics({
    required this.examinedCount,
    required this.excludedExistingCount,
    required this.filteredOtherSourceCount,
    required this.filteredIneligibleCount,
  });

  final int examinedCount;
  final int excludedExistingCount;
  final int filteredOtherSourceCount;
  final int filteredIneligibleCount;
}

enum CameraGalleryRecoveryFailureCode { accessUnavailable, platformFailure }

sealed class CameraGalleryRecoveryResult {
  const CameraGalleryRecoveryResult();
}

class CameraGalleryRecoverySuccess extends CameraGalleryRecoveryResult {
  const CameraGalleryRecoverySuccess({
    required this.items,
    required this.diagnostics,
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
  });

  final List<CameraGalleryRecoveryItem> items;
  final CameraGalleryRecoveryDiagnostics diagnostics;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}

class CameraGalleryRecoveryUnsupported extends CameraGalleryRecoveryResult {
  const CameraGalleryRecoveryUnsupported({this.androidApiLevel});

  final int? androidApiLevel;
}

class CameraGalleryRecoveryFailure extends CameraGalleryRecoveryResult {
  const CameraGalleryRecoveryFailure({required this.code, this.message});

  final CameraGalleryRecoveryFailureCode code;
  final String? message;
}
