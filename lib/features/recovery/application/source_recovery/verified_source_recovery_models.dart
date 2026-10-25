import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../recovery_evidence_classifier/recovery_classification_decision.dart';
import '../restore/system_trash_restore_models.dart';

class VerifiedSourceRecoveryItem {
  const VerifiedSourceRecoveryItem({
    required this.candidate,
    required this.classificationDecision,
    required this.restoreEligibility,
  });

  final MediaCandidate candidate;
  final RecoveryClassificationDecision classificationDecision;
  final SystemTrashRestoreEligibility restoreEligibility;
}

class VerifiedSourceRecoveryDiagnostics {
  const VerifiedSourceRecoveryDiagnostics({
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

enum VerifiedSourceRecoveryFailureCode {
  accessUnavailable,
  platformFailure,
  resourceLimit,
}

sealed class VerifiedSourceRecoveryResult {
  const VerifiedSourceRecoveryResult();
}

class VerifiedSourceRecoverySuccess extends VerifiedSourceRecoveryResult {
  const VerifiedSourceRecoverySuccess({
    required this.source,
    required this.items,
    required this.diagnostics,
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
  });

  final MediaSource source;
  final List<VerifiedSourceRecoveryItem> items;
  final VerifiedSourceRecoveryDiagnostics diagnostics;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}

class VerifiedSourceRecoveryUnsupported extends VerifiedSourceRecoveryResult {
  const VerifiedSourceRecoveryUnsupported({
    required this.source,
    this.androidApiLevel,
  });

  final MediaSource source;
  final int? androidApiLevel;
}

class VerifiedSourceRecoveryFailure extends VerifiedSourceRecoveryResult {
  const VerifiedSourceRecoveryFailure({
    required this.source,
    required this.code,
    this.message,
  });

  final MediaSource source;
  final VerifiedSourceRecoveryFailureCode code;
  final String? message;
}
