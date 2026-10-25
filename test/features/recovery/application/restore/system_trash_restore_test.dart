import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_policy.dart';
import 'package:photo_recovery_restore/features/recovery/data/restore/platform_system_trash_restore.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  const policy = SystemTrashRestorePolicy();
  const planBuilder = SystemTrashRestorePlanBuilder();

  SystemTrashRestoreRequest request({
    int id = 1,
    RecoveryClassification classification =
        RecoveryClassification.verifiedDeleted,
    Iterable<DeletionEvidenceReason> evidence = const [
      DeletionEvidenceReason.systemTrashRecord,
    ],
    RestoreCapability restoreCapability = RestoreCapability.originalFullQuality,
    Uri? contentUri,
  }) {
    final evidenceSet = DeletionEvidence(reasons: evidence);
    final candidate = MediaCandidate(
      id: 'candidate-$id',
      source: MediaSource.cameraGallery,
      contentUri:
          contentUri ?? Uri.parse('content://media/external/images/media/$id'),
      classification: classification,
      deletionEvidence: evidenceSet,
      restoreCapability: restoreCapability,
      recoveryQuality: RecoveryQuality.original,
    );
    return SystemTrashRestoreRequest(
      requestId: 'request-$id',
      candidate: candidate,
      classificationDecision: RecoveryClassificationDecision(
        classification: classification,
        reason: classification == RecoveryClassification.existingMedia
            ? RecoveryClassificationReason.definiteExistingIdentity
            : RecoveryClassificationReason.verifiedSystemTrashEvidence,
        deletionEvidence: evidence,
      ),
    );
  }

  test('verified system-trash item is eligible on API 30 and later', () {
    final result = policy.evaluate(request(), androidApiLevel: 30);

    expect(result.isEligible, isTrue);
  });

  test('existing media is never eligible', () {
    final result = policy.evaluate(
      request(classification: RecoveryClassification.existingMedia),
      androidApiLevel: 35,
    );

    expect(result.reason, SystemTrashRestoreEligibilityReason.alreadyExisting);
  });

  test('possible copy is never eligible for system untrash', () {
    final result = policy.evaluate(
      request(classification: RecoveryClassification.possibleCopy),
      androidApiLevel: 35,
    );

    expect(
      result.reason,
      SystemTrashRestoreEligibilityReason.possibleCopyNotEligible,
    );
  });

  test('Recovery Shield copies use their dedicated restore flow', () {
    final result = policy.evaluate(
      request(classification: RecoveryClassification.protectedCopy),
      androidApiLevel: 35,
    );

    expect(
      result.reason,
      SystemTrashRestoreEligibilityReason.protectedRestoreUnavailable,
    );
  });

  test('unclassified candidate is not eligible', () {
    final result = policy.evaluate(
      request(classification: RecoveryClassification.unclassified),
      androidApiLevel: 35,
    );

    expect(result.reason, SystemTrashRestoreEligibilityReason.unclassified);
  });

  test('API 24 through 29 is unsupported', () {
    final result = policy.evaluate(request(), androidApiLevel: 29);

    expect(
      result.reason,
      SystemTrashRestoreEligibilityReason.unsupportedPlatform,
    );
  });

  test('verified classification without trash evidence is not eligible', () {
    final result = policy.evaluate(
      request(evidence: const []),
      androidApiLevel: 35,
    );

    expect(
      result.reason,
      SystemTrashRestoreEligibilityReason.missingVerifiedTrashEvidence,
    );
  });

  test(
    'restore capability remains independent from deletion classification',
    () {
      final restorable = policy.evaluate(request(), androidApiLevel: 35);
      final notRestorable = policy.evaluate(
        request(restoreCapability: RestoreCapability.notRestorable),
        androidApiLevel: 35,
      );

      expect(restorable.isEligible, isTrue);
      expect(
        notRestorable.reason,
        SystemTrashRestoreEligibilityReason.incompatibleRestoreCapability,
      );
    },
  );

  test('user cancellation is not reported as success', () {
    final result = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'userDeniedOrCancelled',
    });

    expect(result.status, SystemTrashRestoreStatus.userDeniedOrCancelled);
    expect(result.isConfirmedRestored, isFalse);
  });

  test('platform and security failures are structured', () {
    final access = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'accessFailure',
    });
    final platform = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'platformFailure',
    });

    expect(access.status, SystemTrashRestoreStatus.accessFailure);
    expect(platform.status, SystemTrashRestoreStatus.platformFailure);
  });

  test('stale or missing URI is structured', () {
    final result = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'staleOrMissingMediaItem',
      'unverifiedUris': ['content://media/external/images/media/1'],
    });

    expect(result.status, SystemTrashRestoreStatus.staleOrMissingMediaItem);
    expect(result.unverifiedUris, hasLength(1));
    expect(result.isConfirmedRestored, isFalse);
  });

  test('verification failure is not confirmed success', () {
    final result = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'verificationFailed',
      'unverifiedUris': ['content://media/external/images/media/1'],
    });

    expect(result.status, SystemTrashRestoreStatus.verificationFailed);
    expect(result.isConfirmedRestored, isFalse);
  });

  test('successful verified platform result reports restored', () {
    final result = SystemTrashRestorePlatformMapper.fromResponse({
      'status': 'restored',
      'affectedUris': ['content://media/external/images/media/1'],
    });

    expect(result.status, SystemTrashRestoreStatus.restored);
    expect(result.isConfirmedRestored, isTrue);
    expect(result.affectedUris, hasLength(1));
  });

  test('multiple valid items form one valid bounded batch', () {
    final plan = planBuilder.build([
      request(id: 1),
      request(id: 2),
      request(id: 3),
    ], androidApiLevel: 35);

    expect(plan.batches, hasLength(1));
    expect(plan.batches.single.requests, hasLength(3));
    expect(plan.rejections, isEmpty);
  });

  test('more than 2000 items are split across platform requests', () {
    final inputs = List.generate(2001, (index) => request(id: index));
    final plan = planBuilder.build(inputs, androidApiLevel: 35);

    expect(plan.batches, hasLength(2));
    expect(plan.batches.first.requests, hasLength(2000));
    expect(plan.batches.last.requests, hasLength(1));
    expect(
      plan.batches.every(
        (batch) =>
            batch.requests.length <=
            SystemTrashRestorePlanBuilder.maximumBatchSize,
      ),
      isTrue,
    );
  });

  test('batching preserves every requested item exactly once', () {
    final inputs = List.generate(4001, (index) => request(id: index));
    final plan = planBuilder.build(inputs, androidApiLevel: 35);
    final outputIds = plan.batches
        .expand((batch) => batch.requests)
        .map((value) => value.requestId)
        .toList();

    expect(outputIds, inputs.map((value) => value.requestId).toList());
    expect(outputIds.toSet(), hasLength(inputs.length));
  });

  test('definite existing-media conflict blocks restore', () {
    final result = policy.evaluate(
      request(classification: RecoveryClassification.existingMedia),
      androidApiLevel: 35,
    );

    expect(result.isEligible, isFalse);
    expect(result.reason, SystemTrashRestoreEligibilityReason.alreadyExisting);
  });

  test('repeated identical input produces deterministic eligibility', () {
    final input = request();
    final first = policy.evaluate(input, androidApiLevel: 35);
    final second = policy.evaluate(input, androidApiLevel: 35);

    expect(second.reason, first.reason);
    expect(second.isEligible, first.isEligible);
  });

  test('restore batches expose only existing content URIs to the platform', () {
    final plan = planBuilder.build([
      request(id: 20),
      request(id: 21),
    ], androidApiLevel: 35);

    expect(
      plan.batches.single.contentUris.map((uri) => uri.scheme),
      everyElement('content'),
    );
  });
}
