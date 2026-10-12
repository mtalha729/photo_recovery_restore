import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/duplicate_resolution/duplicate_best_copy_resolver.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/paginated_recovery_scanner.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/recovery_image_memory_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/scan_cancellation.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/benchmark/recovery_accuracy_benchmark.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery/domain/verified_content_digest.dart';

import '../../../../support/recovery_accuracy_fixture.dart';

void main() {
  const scanner = PaginatedRecoveryScanner();

  MediaCandidate candidate(int id, {VerifiedContentDigest? digest}) =>
      MediaCandidate(
        id: 'candidate-$id',
        source: MediaSource.cameraGallery,
        contentUri: Uri.parse('content://benchmark/$id'),
        verifiedContentDigest: digest,
        classification: RecoveryClassification.unclassified,
        deletionEvidence: DeletionEvidence(
          reasons: const [DeletionEvidenceReason.systemTrashRecord],
        ),
        restoreCapability: RestoreCapability.originalFullQuality,
        recoveryQuality: RecoveryQuality.original,
      );

  VerifiedSourceRecoveryItem item(int id) => VerifiedSourceRecoveryItem(
    candidate: candidate(id),
    classificationDecision: RecoveryClassificationDecision(
      classification: RecoveryClassification.verifiedDeleted,
      reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
      deletionEvidence: const [DeletionEvidenceReason.systemTrashRecord],
    ),
    restoreEligibility: const SystemTrashRestoreEligibility(
      reason: SystemTrashRestoreEligibilityReason.eligible,
    ),
  );

  VerifiedSourceRecoverySuccess page({
    required int start,
    required int count,
    int? next,
  }) => VerifiedSourceRecoverySuccess(
    source: MediaSource.cameraGallery,
    items: List.generate(count, (index) => item(start + index)),
    diagnostics: VerifiedSourceRecoveryDiagnostics(
      examinedCount: count,
      excludedExistingCount: 0,
      filteredOtherSourceCount: 0,
      filteredIneligibleCount: 0,
    ),
    nextAfterMediaStoreId: next,
  );

  test('paginated processing preserves every record exactly once', () async {
    final consumed = <String>[];
    final summary = await scanner.scan(
      pageSize: 3,
      loadPage: (request) async => switch (request.afterMediaStoreId) {
        null => page(start: 0, count: 3, next: 2),
        2 => page(start: 3, count: 3, next: 5),
        _ => page(start: 6, count: 2),
      },
      consumePage: (value) async {
        consumed.addAll(value.items.map((item) => item.candidate.id));
      },
      cancellationToken: ScanCancellationToken(),
    );
    expect(summary.isCompleteSuccess, isTrue);
    expect(consumed, List.generate(8, (index) => 'candidate-$index'));
    expect(consumed.toSet(), hasLength(8));
  });

  test('progress reports counts without a fake percentage', () async {
    final progressEvents = <RecoveryScanProgress>[];
    final summary = await scanner.scan(
      pageSize: 2,
      loadPage: (request) async => request.afterMediaStoreId == null
          ? page(start: 0, count: 2, next: 1)
          : page(start: 2, count: 1),
      consumePage: (_) async {},
      cancellationToken: ScanCancellationToken(),
      onProgress: progressEvents.add,
    );
    expect(summary.progress.processedCount, 3);
    expect(summary.progress.pageCount, 2);
    expect(summary.progress.discoveredVerifiedCount, 3);
    expect(progressEvents, hasLength(2));
  });

  test('cancellation stops between pages safely', () async {
    final token = ScanCancellationToken();
    var loadCount = 0;
    final summary = await scanner.scan(
      pageSize: 2,
      loadPage: (_) async {
        loadCount++;
        return page(start: 0, count: 2, next: 1);
      },
      consumePage: (_) async => token.cancel(),
      cancellationToken: token,
    );
    expect(loadCount, 1);
    expect(summary.completion, RecoveryScanCompletion.cancelled);
    expect(summary.isCompleteSuccess, isFalse);
    expect(summary.progress.processedCount, 2);
  });

  test(
    'cancellation before a fetched page prevents partial publication',
    () async {
      final token = ScanCancellationToken();
      var consumedPages = 0;
      final summary = await scanner.scan(
        pageSize: 2,
        loadPage: (_) async {
          token.cancel();
          return page(start: 0, count: 2);
        },
        consumePage: (_) async => consumedPages++,
        cancellationToken: token,
      );
      expect(consumedPages, 0);
      expect(summary.completion, RecoveryScanCompletion.cancelled);
    },
  );

  test('repeated continuation exhausts instead of looping', () async {
    final summary = await scanner.scan(
      pageSize: 1,
      loadPage: (_) async => page(start: 0, count: 1, next: 1),
      consumePage: (_) async {},
      cancellationToken: ScanCancellationToken(),
    );
    expect(summary.completion, RecoveryScanCompletion.completed);
    expect(summary.progress.pageCount, 2);
  });

  test('duplicate resolver index is deterministic after optimization', () {
    const resolver = DuplicateBestCopyResolver();
    final values = List.generate(
      10000,
      (index) => candidate(
        index,
        digest: VerifiedContentDigest(
          algorithm: 'sha-256',
          value: 'digest-${index ~/ 2}',
        ),
      ),
    );
    final forward = resolver.resolve(candidates: values);
    final reverse = resolver.resolve(candidates: values.reversed);
    expect(forward.uniquePhotoCount, 5000);
    expect(reverse.uniquePhotoCount, 5000);
    expect(
      forward.groups.map((group) => group.canonicalCandidate.id),
      reverse.groups.map((group) => group.canonicalCandidate.id),
    );
  });

  for (final count in [10000, 50000]) {
    test('$count lightweight records process in bounded pages', () async {
      const pageSize = 200;
      var consumed = 0;
      var maximumRetainedPage = 0;
      final summary = await scanner.scan(
        pageSize: pageSize,
        loadPage: (request) async {
          final start = (request.afterMediaStoreId ?? -1) + 1;
          final remaining = count - start;
          final size = remaining > pageSize ? pageSize : remaining;
          final next = start + size < count ? start + size - 1 : null;
          return page(start: start, count: size, next: next);
        },
        consumePage: (value) async {
          maximumRetainedPage = value.items.length > maximumRetainedPage
              ? value.items.length
              : maximumRetainedPage;
          consumed += value.items.length;
        },
        cancellationToken: ScanCancellationToken(),
      );
      expect(summary.isCompleteSuccess, isTrue);
      expect(consumed, count);
      expect(summary.progress.processedCount, count);
      expect(maximumRetainedPage, lessThanOrEqualTo(pageSize));
    });
  }

  test('Milestone 15 accuracy invariants remain unchanged', () {
    final fixture = buildMixedAccuracyFixture();
    final presented = <String>{};
    final logicalIds = <String>{};
    final sorted = fixture.groundTruth.toList()
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    for (final value in sorted) {
      if (value.expectedVerifiedDeleted &&
          logicalIds.add(value.logicalPhotoId)) {
        presented.add(value.candidateId);
      }
    }
    final report = const RecoveryAccuracyBenchmark().evaluate(
      groundTruth: fixture.groundTruth,
      observations: observeFixture(fixture, presentedCandidateIds: presented),
    );
    expect(report.falsePositives, 0);
    expect(report.falseNegatives, 0);
    expect(report.existingMediaLeakageCount, 0);
    expect(report.sourceDomainContaminationCount, 0);
    expect(report.possibleCopyLeakageCount, 0);
    expect(report.unknownItemLeakageCount, 0);
    expect(report.duplicateResultInflationCount, 0);
  });

  test('thumbnail rule requires bounded size-appropriate requests', () {
    expect(
      RecoveryImageMemoryPolicy.isSizeAppropriateThumbnailRequest(
        width: 512,
        height: 384,
      ),
      isTrue,
    );
    expect(
      RecoveryImageMemoryPolicy.isSizeAppropriateThumbnailRequest(
        width: 4032,
        height: 3024,
      ),
      isFalse,
    );
  });

  test(
    'opaque continuations exhaust every simulated MediaStore volume',
    () async {
      final requestedTokens = <String?>[];
      final summary = await scanner.scan(
        pageSize: 2,
        loadPage: (request) async {
          requestedTokens.add(request.continuationToken);
          return switch (request.continuationToken) {
            null => VerifiedSourceRecoverySuccess(
              source: MediaSource.cameraGallery,
              items: [item(1), item(2)],
              diagnostics: const VerifiedSourceRecoveryDiagnostics(
                examinedCount: 2,
                excludedExistingCount: 0,
                filteredOtherSourceCount: 0,
                filteredIneligibleCount: 0,
              ),
              nextContinuationToken: 'mv1:1:0',
              scannedVolumeName: 'external_primary',
            ),
            'mv1:1:0' => VerifiedSourceRecoverySuccess(
              source: MediaSource.cameraGallery,
              items: [item(3)],
              diagnostics: const VerifiedSourceRecoveryDiagnostics(
                examinedCount: 1,
                excludedExistingCount: 0,
                filteredOtherSourceCount: 0,
                filteredIneligibleCount: 0,
              ),
              scannedVolumeName: '1234-5678',
            ),
            _ => throw StateError('Unexpected continuation'),
          };
        },
        consumePage: (_) async {},
        cancellationToken: ScanCancellationToken(),
      );

      expect(summary.isCompleteSuccess, isTrue);
      expect(summary.progress.processedCount, 3);
      expect(requestedTokens, [null, 'mv1:1:0']);
    },
  );
}
