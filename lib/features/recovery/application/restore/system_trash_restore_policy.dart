import '../../domain/deletion_evidence.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/restore_capability.dart';
import 'system_trash_restore_models.dart';

class SystemTrashRestorePolicy {
  const SystemTrashRestorePolicy();

  SystemTrashRestoreEligibility evaluate(
    SystemTrashRestoreRequest request, {
    required int androidApiLevel,
  }) {
    final classification = request.classificationDecision.classification;

    if (classification == RecoveryClassification.existingMedia ||
        request.classificationDecision.mustBeExcludedFromRecoveryResults) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.alreadyExisting,
      );
    }
    if (androidApiLevel < 30) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.unsupportedPlatform,
      );
    }
    if (classification == RecoveryClassification.protectedDeleted) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.protectedRestoreUnavailable,
      );
    }
    if (classification == RecoveryClassification.possibleCopy) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.possibleCopyNotEligible,
      );
    }
    if (classification == RecoveryClassification.corrupted) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.corruptedNotEligible,
      );
    }
    if (classification == RecoveryClassification.unavailable) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.unavailable,
      );
    }
    if (classification == RecoveryClassification.unclassified) {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.unclassified,
      );
    }
    if (classification != RecoveryClassification.verifiedDeleted ||
        !request.classificationDecision.deletionEvidence.contains(
          DeletionEvidenceReason.systemTrashRecord,
        )) {
      return const SystemTrashRestoreEligibility(
        reason:
            SystemTrashRestoreEligibilityReason.missingVerifiedTrashEvidence,
      );
    }
    if (request.candidate.restoreCapability !=
        RestoreCapability.originalFullQuality) {
      return const SystemTrashRestoreEligibility(
        reason:
            SystemTrashRestoreEligibilityReason.incompatibleRestoreCapability,
      );
    }
    final uri = request.candidate.contentUri;
    if (uri == null || uri.scheme != 'content') {
      return const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.missingContentUri,
      );
    }
    return const SystemTrashRestoreEligibility(
      reason: SystemTrashRestoreEligibilityReason.eligible,
    );
  }
}

class SystemTrashRestorePlanBuilder {
  const SystemTrashRestorePlanBuilder({
    this.policy = const SystemTrashRestorePolicy(),
  });

  static const maximumBatchSize = 2000;

  final SystemTrashRestorePolicy policy;

  SystemTrashRestorePlan build(
    Iterable<SystemTrashRestoreRequest> requests, {
    required int androidApiLevel,
  }) {
    final eligible = <SystemTrashRestoreRequest>[];
    final rejections = <SystemTrashRestoreRejection>[];

    for (final request in requests) {
      final eligibility = policy.evaluate(
        request,
        androidApiLevel: androidApiLevel,
      );
      if (eligibility.isEligible) {
        eligible.add(request);
      } else {
        rejections.add(
          SystemTrashRestoreRejection(
            request: request,
            eligibility: eligibility,
          ),
        );
      }
    }

    final batches = <SystemTrashRestoreBatch>[];
    for (var start = 0; start < eligible.length; start += maximumBatchSize) {
      final proposedEnd = start + maximumBatchSize;
      final end = proposedEnd < eligible.length ? proposedEnd : eligible.length;
      batches.add(
        SystemTrashRestoreBatch(
          List.unmodifiable(eligible.sublist(start, end)),
        ),
      );
    }

    return SystemTrashRestorePlan(
      batches: List.unmodifiable(batches),
      rejections: List.unmodifiable(rejections),
    );
  }
}
