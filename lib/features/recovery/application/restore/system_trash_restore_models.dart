import '../../domain/media_candidate.dart';
import '../recovery_evidence_classifier/recovery_classification_decision.dart';

enum SystemTrashRestoreEligibilityReason {
  eligible,
  unsupportedPlatform,
  alreadyExisting,
  missingVerifiedTrashEvidence,
  protectedRestoreUnavailable,
  possibleCopyNotEligible,
  corruptedNotEligible,
  unavailable,
  unclassified,
  incompatibleRestoreCapability,
  missingContentUri,
}

class SystemTrashRestoreEligibility {
  const SystemTrashRestoreEligibility({required this.reason});

  final SystemTrashRestoreEligibilityReason reason;

  bool get isEligible => reason == SystemTrashRestoreEligibilityReason.eligible;
}

class SystemTrashRestoreRequest {
  const SystemTrashRestoreRequest({
    required this.requestId,
    required this.candidate,
    required this.classificationDecision,
  });

  final String requestId;
  final MediaCandidate candidate;
  final RecoveryClassificationDecision classificationDecision;
}

class SystemTrashRestoreRejection {
  const SystemTrashRestoreRejection({
    required this.request,
    required this.eligibility,
  });

  final SystemTrashRestoreRequest request;
  final SystemTrashRestoreEligibility eligibility;
}

class SystemTrashRestoreBatch {
  const SystemTrashRestoreBatch(this.requests);

  final List<SystemTrashRestoreRequest> requests;

  List<Uri> get contentUris => List.unmodifiable(
    requests.map((request) => request.candidate.contentUri!),
  );
}

class SystemTrashRestorePlan {
  const SystemTrashRestorePlan({
    required this.batches,
    required this.rejections,
  });

  final List<SystemTrashRestoreBatch> batches;
  final List<SystemTrashRestoreRejection> rejections;
}

enum SystemTrashRestoreStatus {
  restored,
  userDeniedOrCancelled,
  unsupportedPlatform,
  staleOrMissingMediaItem,
  accessFailure,
  platformFailure,
  verificationFailed,
  operationInProgress,
}

class SystemTrashRestoreResult {
  const SystemTrashRestoreResult({
    required this.status,
    this.message,
    this.affectedUris = const [],
    this.unverifiedUris = const [],
  });

  final SystemTrashRestoreStatus status;
  final String? message;
  final List<Uri> affectedUris;
  final List<Uri> unverifiedUris;

  bool get isConfirmedRestored => status == SystemTrashRestoreStatus.restored;
}
