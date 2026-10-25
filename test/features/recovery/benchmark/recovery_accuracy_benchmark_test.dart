import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/benchmark/recovery_accuracy_benchmark.dart';
import 'package:photo_recovery_restore/features/recovery/benchmark/recovery_accuracy_benchmark_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';

import '../../../support/recovery_accuracy_fixture.dart';

void main() {
  const benchmark = RecoveryAccuracyBenchmark();

  Set<String> expectedPresentedIds(RecoveryAccuracyFixture fixture) {
    final selectedLogicalIds = <String>{};
    final result = <String>{};
    final sorted = fixture.groundTruth.toList()
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    for (final expected in sorted) {
      if (expected.expectedVerifiedDeleted &&
          selectedLogicalIds.add(expected.logicalPhotoId)) {
        result.add(expected.candidateId);
      }
    }
    return result;
  }

  RecoveryAccuracyBenchmarkReport runFixture(RecoveryAccuracyFixture fixture) {
    final observations = observeFixture(
      fixture,
      presentedCandidateIds: expectedPresentedIds(fixture),
    );
    return benchmark.evaluate(
      groundTruth: fixture.groundTruth,
      observations: observations,
    );
  }

  test('metric calculations are mathematically correct', () {
    const truth = [
      RecoveryBenchmarkGroundTruth(
        candidateId: 'tp',
        logicalPhotoId: 'tp',
        expectedClassification: RecoveryClassification.verifiedDeleted,
        expectedSource: MediaSource.cameraGallery,
        expectedSystemRestoreEligible: true,
        expectedShieldRestoreEligible: false,
      ),
      RecoveryBenchmarkGroundTruth(
        candidateId: 'fn',
        logicalPhotoId: 'fn',
        expectedClassification: RecoveryClassification.verifiedDeleted,
        expectedSource: MediaSource.cameraGallery,
        expectedSystemRestoreEligible: true,
        expectedShieldRestoreEligible: false,
      ),
      RecoveryBenchmarkGroundTruth(
        candidateId: 'fp',
        logicalPhotoId: 'fp',
        expectedClassification: RecoveryClassification.existingMedia,
        expectedSource: MediaSource.cameraGallery,
        expectedSystemRestoreEligible: false,
        expectedShieldRestoreEligible: false,
      ),
      RecoveryBenchmarkGroundTruth(
        candidateId: 'tn',
        logicalPhotoId: 'tn',
        expectedClassification: RecoveryClassification.existingMedia,
        expectedSource: MediaSource.cameraGallery,
        expectedSystemRestoreEligible: false,
        expectedShieldRestoreEligible: false,
      ),
    ];
    const observations = [
      RecoveryBenchmarkObservation(
        candidateId: 'tp',
        logicalPhotoId: 'tp',
        classification: RecoveryClassification.verifiedDeleted,
        source: MediaSource.cameraGallery,
        presentedInVerifiedResults: true,
        systemRestoreEligible: true,
        shieldRestoreEligible: false,
      ),
      RecoveryBenchmarkObservation(
        candidateId: 'fn',
        logicalPhotoId: 'fn',
        classification: RecoveryClassification.verifiedDeleted,
        source: MediaSource.cameraGallery,
        presentedInVerifiedResults: false,
        systemRestoreEligible: true,
        shieldRestoreEligible: false,
      ),
      RecoveryBenchmarkObservation(
        candidateId: 'fp',
        logicalPhotoId: 'fp',
        classification: RecoveryClassification.existingMedia,
        source: MediaSource.cameraGallery,
        presentedInVerifiedResults: true,
        systemRestoreEligible: false,
        shieldRestoreEligible: false,
      ),
      RecoveryBenchmarkObservation(
        candidateId: 'tn',
        logicalPhotoId: 'tn',
        classification: RecoveryClassification.existingMedia,
        source: MediaSource.cameraGallery,
        presentedInVerifiedResults: false,
        systemRestoreEligible: false,
        shieldRestoreEligible: false,
      ),
    ];
    final report = benchmark.evaluate(
      groundTruth: truth,
      observations: observations,
    );
    expect(report.truePositives, 1);
    expect(report.falsePositives, 1);
    expect(report.falseNegatives, 1);
    expect(report.trueNegatives, 1);
    expect(report.precision, 0.5);
    expect(report.recall, 0.5);
    expect(report.falsePositiveRate, 0.5);
  });

  test('zero denominators are safe', () {
    final report = benchmark.evaluate(
      groundTruth: const [],
      observations: const [],
    );
    expect(report.precision, 0);
    expect(report.recall, 0);
    expect(report.falsePositiveRate, 0);
    expect(report.restoreEligibilityAccuracy, 0);
  });

  test('mixed ground truth matches engine classifications', () {
    final fixture = buildMixedAccuracyFixture();
    final observations = observeFixture(
      fixture,
      presentedCandidateIds: expectedPresentedIds(fixture),
    );
    final actualById = {
      for (final observation in observations)
        observation.candidateId: observation.classification,
    };
    for (final expected in fixture.groundTruth) {
      expect(actualById[expected.candidateId], expected.expectedClassification);
    }
  });

  test('controlled benchmark has zero false positives and false negatives', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(report.groundTruthDeleted, 6);
    expect(report.truePositives, 6);
    expect(report.falsePositives, 0);
    expect(report.falseNegatives, 0);
    expect(report.precision, 1);
    expect(report.recall, 1);
  });

  test('current and contradictory existing media never leak', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(report.existingMediaLeakageCount, 0);
  });

  test('possible copies and unknown items never leak', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(report.possibleCopyLeakageCount, 0);
    expect(report.unknownItemLeakageCount, 0);
  });

  test('all source domains have zero contamination', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(report.sourceDomainContaminationCount, 0);
  });

  test('exact duplicate records produce one logical result', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(report.duplicateResultInflationCount, 0);
  });

  test('no-existing-match and Shield protection alone are not deleted', () {
    final fixture = buildMixedAccuracyFixture();
    final observations = observeFixture(
      fixture,
      presentedCandidateIds: expectedPresentedIds(fixture),
    );
    for (final id in ['no-match-only', 'shield-protected-only']) {
      final observation = observations.singleWhere(
        (value) => value.candidateId == id,
      );
      expect(observation.presentedInVerifiedResults, isFalse);
      expect(observation.classification, RecoveryClassification.unclassified);
    }
  });

  test('restore eligibility is benchmarked separately and is correct', () {
    final report = runFixture(buildMixedAccuracyFixture());
    expect(
      report.restoreEligibilityCorrectCount,
      report.restoreEligibilityCheckCount,
    );
    expect(report.restoreEligibilityAccuracy, 1);
  });

  test('source resolver retains locked domain boundaries', () {
    expect(
      resolveBenchmarkSource(path: 'DCIM/Camera/'),
      MediaSource.cameraGallery,
    );
    expect(
      resolveBenchmarkSource(path: 'Pictures/Screenshots/'),
      MediaSource.screenshots,
    );
    expect(
      resolveBenchmarkSource(path: 'Download/'),
      MediaSource.downloadsSavedMedia,
    );
    expect(
      resolveBenchmarkSource(path: 'Pictures/Telegram/'),
      MediaSource.messagingSharedMedia,
    );
    expect(
      resolveBenchmarkSource(
        path: 'Pictures/',
        volume: '1234-5678',
        removable: true,
      ),
      MediaSource.sdCard,
    );
  });

  test('diagnostic summary is internal and factual', () {
    final summary = runFixture(buildMixedAccuracyFixture()).diagnosticSummary;
    expect(summary, contains('False positives:            0'));
    expect(summary, isNot(contains('% recovery')));
    expect(summary, isNot(contains('confidence')));
  });

  test('output is deterministic independent of input order', () {
    final fixture = buildMixedAccuracyFixture();
    final observations = observeFixture(
      fixture,
      presentedCandidateIds: expectedPresentedIds(fixture),
    );
    final forward = benchmark.evaluate(
      groundTruth: fixture.groundTruth,
      observations: observations,
    );
    final reverse = benchmark.evaluate(
      groundTruth: fixture.groundTruth.reversed,
      observations: observations.reversed,
    );
    expect(reverse.diagnosticSummary, forward.diagnosticSummary);
    expect(reverse.precision, forward.precision);
    expect(
      reverse.restoreEligibilityAccuracy,
      forward.restoreEligibilityAccuracy,
    );
  });

  for (final count in [1000, 10000]) {
    test('$count-record indexed fixture preserves correctness', () {
      final fixture = buildLargeAccuracyFixture(count);
      final report = runFixture(fixture);
      expect(report.totalRecords, count);
      expect(report.groundTruthDeleted, count ~/ 10);
      expect(report.falsePositives, 0);
      expect(report.falseNegatives, 0);
      expect(report.existingMediaLeakageCount, 0);
      expect(report.sourceDomainContaminationCount, 0);
      expect(report.duplicateResultInflationCount, 0);
    });
  }
}
