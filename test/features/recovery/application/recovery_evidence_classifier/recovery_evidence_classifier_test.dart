import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_evidence_classifier.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  const classifier = RecoveryEvidenceClassifier();
  const noMatch = ExistingMediaDecision.noExistingMatch();
  const uncertain = ExistingMediaDecision.uncertainIdentity();
  const currentRecord = CurrentMediaRecord(mediaStoreId: 1);
  const existing = ExistingMediaDecision.definitelyExisting(
    ExistingMediaReference(record: currentRecord),
  );

  MediaCandidate candidate({
    RecoveryClassification classification = RecoveryClassification.unclassified,
    Iterable<DeletionEvidenceReason> evidence = const [],
    bool isRecoveryShieldBackup = false,
    RestoreCapability restoreCapability = RestoreCapability.notRestorable,
    RecoveryQuality recoveryQuality = RecoveryQuality.unavailable,
  }) {
    return MediaCandidate(
      id: 'candidate',
      source: MediaSource.unknown,
      classification: classification,
      deletionEvidence: DeletionEvidence(reasons: evidence),
      restoreCapability: restoreCapability,
      recoveryQuality: recoveryQuality,
      discoveryEvidence: RecoveryDiscoveryEvidence(
        isRecoveryShieldBackup: isRecoveryShieldBackup,
      ),
    );
  }

  test('definite existing match is excluded from deleted results', () {
    final decision = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: existing,
    );

    expect(decision.classification, RecoveryClassification.existingMedia);
    expect(decision.mustBeExcludedFromRecoveryResults, isTrue);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test(
    'system trash evidence becomes verified deleted without a definite match',
    () {
      final decision = classifier.classify(
        candidate: candidate(
          evidence: [DeletionEvidenceReason.systemTrashRecord],
        ),
        existingMediaDecision: noMatch,
      );

      expect(decision.classification, RecoveryClassification.verifiedDeleted);
      expect(
        decision.reason,
        RecoveryClassificationReason.verifiedSystemTrashEvidence,
      );
      expect(decision.isEligibleForVerifiedDeletedResults, isTrue);
    },
  );

  test('Recovery Shield backup evidence is protected, never deleted proof', () {
    final withoutEvidence = classifier.classify(
      candidate: candidate(
        classification: RecoveryClassification.protectedCopy,
      ),
      existingMediaDecision: noMatch,
    );
    final withEvidence = classifier.classify(
      candidate: candidate(isRecoveryShieldBackup: true),
      existingMediaDecision: noMatch,
    );
    final shieldWithSourceTrashMetadata = classifier.classify(
      candidate: candidate(
        isRecoveryShieldBackup: true,
        evidence: [DeletionEvidenceReason.systemTrashRecord],
      ),
      existingMediaDecision: noMatch,
    );

    expect(withoutEvidence.classification, RecoveryClassification.unclassified);
    expect(withEvidence.classification, RecoveryClassification.protectedCopy);
    expect(withEvidence.isProtectedCopy, isTrue);
    expect(withEvidence.isEligibleForVerifiedDeletedResults, isFalse);
    expect(withEvidence.deletionEvidence, isEmpty);
    expect(
      shieldWithSourceTrashMetadata.classification,
      RecoveryClassification.protectedCopy,
    );
    expect(
      shieldWithSourceTrashMetadata.isEligibleForVerifiedDeletedResults,
      isFalse,
    );
  });

  test('possible copy never upgrades to verified deleted automatically', () {
    final decision = classifier.classify(
      candidate: candidate(classification: RecoveryClassification.possibleCopy),
      existingMediaDecision: noMatch,
    );

    expect(decision.classification, RecoveryClassification.possibleCopy);
    expect(decision.belongsOnlyInPossibleCopies, isTrue);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('no current-media match alone never means deleted', () {
    final decision = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: noMatch,
    );

    expect(decision.classification, RecoveryClassification.unclassified);
    expect(decision.reason, RecoveryClassificationReason.insufficientEvidence);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('readable unindexed cache image remains a possible copy, not deleted', () {
    final decision = classifier.classify(
      candidate: MediaCandidate(
        id: 'cached-frame',
        source: MediaSource.unknown,
        filePath: '/shared/Android/media/example/cache/frame.jpg',
        classification: RecoveryClassification.unclassified,
        deletionEvidence: DeletionEvidence(),
        restoreCapability: RestoreCapability.lowerResolutionCopy,
        recoveryQuality: RecoveryQuality.reducedResolutionCopy,
      ),
      existingMediaDecision: noMatch,
    );

    expect(decision.classification, RecoveryClassification.possibleCopy);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('uncertain identity alone never means deleted', () {
    final decision = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: uncertain,
    );

    expect(decision.classification, RecoveryClassification.unclassified);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('existing identity overrides contradictory deletion evidence', () {
    final decision = classifier.classify(
      candidate: candidate(
        evidence: [DeletionEvidenceReason.systemTrashRecord],
      ),
      existingMediaDecision: existing,
    );

    expect(decision.classification, RecoveryClassification.existingMedia);
    expect(decision.hasContradictoryDeletionEvidence, isTrue);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('corrupted classification requires explicit corruption state', () {
    final implicit = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: noMatch,
    );
    final explicit = classifier.classify(
      candidate: candidate(recoveryQuality: RecoveryQuality.corrupted),
      existingMediaDecision: noMatch,
    );

    expect(implicit.classification, isNot(RecoveryClassification.corrupted));
    expect(explicit.classification, RecoveryClassification.corrupted);
    expect(explicit.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('unavailable classification requires explicit unavailable state', () {
    final implicit = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: noMatch,
    );
    final explicit = classifier.classify(
      candidate: candidate(classification: RecoveryClassification.unavailable),
      existingMediaDecision: noMatch,
    );

    expect(implicit.classification, RecoveryClassification.unclassified);
    expect(explicit.classification, RecoveryClassification.unavailable);
  });

  test('explicit source unavailability is unavailable, not deleted', () {
    final decision = classifier.classify(
      candidate: candidate(
        evidence: [DeletionEvidenceReason.sourceNoLongerAvailable],
      ),
      existingMediaDecision: noMatch,
    );

    expect(decision.classification, RecoveryClassification.unavailable);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('deleted status is independent from restore capability', () {
    final restorable = classifier.classify(
      candidate: candidate(
        evidence: [DeletionEvidenceReason.systemTrashRecord],
        restoreCapability: RestoreCapability.originalFullQuality,
      ),
      existingMediaDecision: noMatch,
    );
    final notRestorable = classifier.classify(
      candidate: candidate(
        evidence: [DeletionEvidenceReason.systemTrashRecord],
        restoreCapability: RestoreCapability.notRestorable,
      ),
      existingMediaDecision: noMatch,
    );

    expect(restorable.classification, RecoveryClassification.verifiedDeleted);
    expect(
      notRestorable.classification,
      RecoveryClassification.verifiedDeleted,
    );
  });

  test('lower-resolution recoverability proves only a possible copy', () {
    final decision = classifier.classify(
      candidate: candidate(
        restoreCapability: RestoreCapability.lowerResolutionCopy,
      ),
      existingMediaDecision: noMatch,
    );

    expect(decision.classification, RecoveryClassification.possibleCopy);
    expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
  });

  test('decision uses categorical evidence without numeric confidence', () {
    final decision = classifier.classify(
      candidate: candidate(
        evidence: [DeletionEvidenceReason.systemTrashRecord],
      ),
      existingMediaDecision: noMatch,
    );

    expect(decision.deletionEvidence, {
      DeletionEvidenceReason.systemTrashRecord,
    });
    expect(
      decision.reason,
      RecoveryClassificationReason.verifiedSystemTrashEvidence,
    );
  });

  test('identical inputs produce deterministic decisions', () {
    final input = candidate(
      evidence: [DeletionEvidenceReason.systemTrashRecord],
    );
    final first = classifier.classify(
      candidate: input,
      existingMediaDecision: uncertain,
    );
    final second = classifier.classify(
      candidate: input,
      existingMediaDecision: uncertain,
    );

    expect(second.classification, first.classification);
    expect(second.reason, first.reason);
    expect(second.deletionEvidence, first.deletionEvidence);
    expect(
      second.isEligibleForVerifiedDeletedResults,
      first.isEligibleForVerifiedDeletedResults,
    );
  });

  test('existing and possible-copy decisions are never deleted-eligible', () {
    final existingDecision = classifier.classify(
      candidate: candidate(),
      existingMediaDecision: existing,
    );
    final copyDecision = classifier.classify(
      candidate: candidate(classification: RecoveryClassification.possibleCopy),
      existingMediaDecision: noMatch,
    );

    expect(existingDecision.isEligibleForVerifiedDeletedResults, isFalse);
    expect(copyDecision.isEligibleForVerifiedDeletedResults, isFalse);
  });
}
