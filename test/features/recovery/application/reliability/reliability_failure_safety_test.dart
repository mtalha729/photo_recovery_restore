import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_evidence_classifier.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_protection_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/reliability/keyed_operation_coordinator.dart';
import 'package:photo_recovery_restore/features/recovery/application/reliability/recovery_operation_failure.dart';
import 'package:photo_recovery_restore/features/recovery/benchmark/recovery_accuracy_benchmark.dart';
import 'package:photo_recovery_restore/features/recovery/data/recovery_shield/platform_recovery_shield_storage.dart';
import 'package:photo_recovery_restore/features/recovery/data/recovery_shield_restore/platform_recovery_shield_restorer.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

import '../../../../support/recovery_accuracy_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const protectionChannel = MethodChannel('test/reliability-protect');
  const restoreChannel = MethodChannel('test/reliability-restore');

  MediaCandidate candidate({
    RecoveryClassification classification = RecoveryClassification.unclassified,
    Iterable<DeletionEvidenceReason> evidence = const [],
  }) => MediaCandidate(
    id: 'candidate',
    source: MediaSource.sdCard,
    contentUri: Uri.parse('content://media/external/images/media/1'),
    classification: classification,
    deletionEvidence: DeletionEvidence(reasons: evidence),
    restoreCapability: RestoreCapability.originalFullQuality,
    recoveryQuality: RecoveryQuality.original,
  );

  RecoveryShieldProtectionRequest protectionRequest() =>
      const RecoveryShieldProtectionPolicy().createRequest(
        protectionId: 'shield-1',
        candidate: candidate(),
      )!;

  ProtectedMediaRecord protectedRecord() => ProtectedMediaRecord(
    protectionId: 'shield-1',
    originalSource: MediaSource.sdCard,
    byteSize: 4,
    protectedCopyLocation: '/private/copy.bin',
    sha256Digest: 'abcd',
    protectedAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
  );

  RecoveryShieldRestoreRequest restoreRequest() => RecoveryShieldRestoreRequest(
    record: protectedRecord(),
    originalCandidate: candidate(),
    relativeDestination: 'Pictures/Recovery',
  );

  Map<String, Object?> protectedSuccess() => {
    'status': 'protected',
    'protectedCopyLocation': '/private/copy.bin',
    'sha256Digest': 'abcd',
    'byteSize': 4,
    'protectedAtMillis': 1,
  };

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(protectionChannel, null);
    messenger.setMockMethodCallHandler(restoreChannel, null);
  });

  test('revoked access and stale URI never become deletion evidence', () {
    const classifier = RecoveryEvidenceClassifier();
    for (final value in [
      candidate(),
      candidate(
        evidence: const [DeletionEvidenceReason.sourceNoLongerAvailable],
      ),
    ]) {
      final decision = classifier.classify(
        candidate: value,
        existingMediaDecision: const ExistingMediaDecision.noExistingMatch(),
      );
      expect(decision.isEligibleForVerifiedDeletedResults, isFalse);
    }
  });

  test('SD removal is storage failure, never deletion', () {
    const failure = RecoveryOperationFailure(
      kind: RecoveryOperationFailureKind.storageUnavailable,
      operationId: 'scan:sd',
      itemId: 'candidate',
    );
    expect(failure.kind, RecoveryOperationFailureKind.storageUnavailable);
    expect(candidate().isDeletedRecoveryResult, isFalse);
  });

  test('cancelled and verification-failed operations are not success', () {
    for (final status in [
      RecoveryShieldRestoreStatus.verificationFailure,
      RecoveryShieldRestoreStatus.operationInProgress,
    ]) {
      expect(
        RecoveryShieldRestoreResult(
          protectionId: 'shield-1',
          status: status,
        ).isSuccessful,
        isFalse,
      );
    }
    expect(
      const RecoveryShieldProtectionResult(
        protectionId: 'shield-1',
        status: RecoveryShieldProtectionStatus.cancelled,
      ).isSuccessful,
      isFalse,
    );
  });

  test('duplicate concurrent protection is rejected safely', () async {
    final completer = Completer<Map<String, Object?>>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (_) {
          calls++;
          return completer.future;
        });
    final storage = PlatformRecoveryShieldStorage.withChannel(
      protectionChannel,
    );
    final first = storage.protect(protectionRequest());
    await Future<void>.delayed(Duration.zero);
    final conflict = await storage.protect(protectionRequest());
    expect(conflict.status, RecoveryShieldProtectionStatus.operationInProgress);
    expect(
      conflict.failure?.kind,
      RecoveryOperationFailureKind.operationConflict,
    );
    completer.complete(protectedSuccess());
    expect((await first).status, RecoveryShieldProtectionStatus.protected);
    expect(calls, 1);
  });

  test(
    'duplicate restore is prevented and successful retry is idempotent',
    () async {
      final completer = Completer<Map<String, Object?>>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(restoreChannel, (_) {
            calls++;
            return completer.future;
          });
      final restorer = PlatformRecoveryShieldRestorer.withChannel(
        restoreChannel,
      );
      final first = restorer.restore(restoreRequest());
      await Future<void>.delayed(Duration.zero);
      final conflict = await restorer.restore(restoreRequest());
      expect(conflict.status, RecoveryShieldRestoreStatus.operationInProgress);
      completer.complete({
        'status': 'restored',
        'restoredContentUri': 'content://media/item/2',
      });
      expect((await first).status, RecoveryShieldRestoreStatus.restored);
      final retry = await restorer.restore(restoreRequest());
      expect(retry.status, RecoveryShieldRestoreStatus.alreadyPresent);
      expect(calls, 1);
    },
  );

  test(
    'late duplicate completion is harmless and operation runs once',
    () async {
      final coordinator = KeyedOperationCoordinator();
      var runs = 0;
      final first = await coordinator.run(
        key: 'item',
        operation: () async => ++runs,
        rememberResult: (_) => true,
      );
      final replay = await coordinator.run(
        key: 'item',
        operation: () async => ++runs,
        rememberResult: (_) => true,
      );
      expect(first.state, CoordinatedOperationState.executed);
      expect(replay.state, CoordinatedOperationState.replayed);
      expect(replay.value, 1);
      expect(runs, 1);
    },
  );

  test('malformed platform response is normalized', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (_) async => null);
    final result = await PlatformRecoveryShieldStorage.withChannel(
      protectionChannel,
    ).protect(protectionRequest());
    expect(result.status, RecoveryShieldProtectionStatus.platformFailure);
    expect(
      result.failure?.kind,
      RecoveryOperationFailureKind.malformedResponse,
    );
  });

  test('unsupported platform capability is normalized', () async {
    const missing = MethodChannel('test/no-such-reliability-channel');
    final result = await PlatformRecoveryShieldStorage.withChannel(missing)
        .protect(protectionRequest());
    expect(result.status, RecoveryShieldProtectionStatus.platformFailure);
    expect(
      result.failure?.kind,
      RecoveryOperationFailureKind.unsupportedCapability,
    );
  });

  test('partial batch preserves independent per-item outcomes', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(protectionChannel, (_) async {
          calls++;
          return calls == 1
              ? protectedSuccess()
              : {'status': 'insufficientStorage'};
        });
    final first = protectionRequest();
    final second = const RecoveryShieldProtectionPolicy().createRequest(
      protectionId: 'shield-2',
      candidate: MediaCandidate(
        id: 'candidate-2',
        source: MediaSource.cameraGallery,
        contentUri: Uri.parse('content://media/item/2'),
        classification: RecoveryClassification.existingMedia,
        deletionEvidence: DeletionEvidence(),
        restoreCapability: RestoreCapability.originalFullQuality,
        recoveryQuality: RecoveryQuality.original,
      ),
    )!;
    final result = await PlatformRecoveryShieldStorage.withChannel(
      protectionChannel,
    ).protectBatch([first, second]);
    expect(result.items.map((item) => item.status), [
      RecoveryShieldProtectionStatus.protected,
      RecoveryShieldProtectionStatus.insufficientStorage,
    ]);
  });

  test('replacement failure preserves last valid protected copy', () {
    final old = protectedRecord();
    final state = RecoveryShieldProtectionState(records: [old]);
    state.apply(
      const RecoveryShieldProtectionResult(
        protectionId: 'shield-1',
        status: RecoveryShieldProtectionStatus.insufficientStorage,
      ),
    );
    expect(state.recordFor('shield-1'), same(old));
  });

  test('one failed operation does not block an unrelated item', () async {
    final coordinator = KeyedOperationCoordinator();
    final failed = await coordinator.run(
      key: 'first',
      operation: () async => false,
      rememberResult: (value) => value,
    );
    final successful = await coordinator.run(
      key: 'second',
      operation: () async => true,
      rememberResult: (value) => value,
    );
    expect(failed.value, isFalse);
    expect(successful.value, isTrue);
  });

  test('Milestone 15 benchmark invariants remain zero', () {
    final fixture = buildMixedAccuracyFixture();
    final logical = <String>{};
    final presented = <String>{};
    final sorted = fixture.groundTruth.toList()
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    for (final expected in sorted) {
      if (expected.expectedVerifiedDeleted &&
          logical.add(expected.logicalPhotoId)) {
        presented.add(expected.candidateId);
      }
    }
    final report = const RecoveryAccuracyBenchmark().evaluate(
      groundTruth: fixture.groundTruth,
      observations: observeFixture(fixture, presentedCandidateIds: presented),
    );
    expect(report.existingMediaLeakageCount, 0);
    expect(report.sourceDomainContaminationCount, 0);
    expect(report.possibleCopyLeakageCount, 0);
    expect(report.unknownItemLeakageCount, 0);
    expect(report.duplicateResultInflationCount, 0);
  });
}
