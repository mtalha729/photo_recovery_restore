import '../domain/media_source.dart';
import '../domain/recovery_classification.dart';
import 'recovery_accuracy_benchmark_models.dart';

class RecoveryAccuracyBenchmark {
  const RecoveryAccuracyBenchmark();

  RecoveryAccuracyBenchmarkReport evaluate({
    required Iterable<RecoveryBenchmarkGroundTruth> groundTruth,
    required Iterable<RecoveryBenchmarkObservation> observations,
  }) {
    final expectedById = <String, RecoveryBenchmarkGroundTruth>{};
    for (final expected in groundTruth) {
      if (expectedById.containsKey(expected.candidateId)) {
        throw ArgumentError.value(
          expected.candidateId,
          'groundTruth',
          'Duplicate candidate ID',
        );
      }
      expectedById[expected.candidateId] = expected;
    }
    final actualById = <String, RecoveryBenchmarkObservation>{};
    for (final actual in observations) {
      if (actualById.containsKey(actual.candidateId)) {
        throw ArgumentError.value(
          actual.candidateId,
          'observations',
          'Duplicate candidate ID',
        );
      }
      actualById[actual.candidateId] = actual;
    }

    var sourceContamination = 0;
    var existingLeakage = 0;
    var possibleCopyLeakage = 0;
    var unknownLeakage = 0;
    var restoreCorrect = 0;
    var restoreChecks = 0;
    final verifiedByLogicalPhoto = <String, int>{};
    final deletedLogicalPhotos = <String>{};
    final allLogicalPhotos = <String>{};

    for (final expected in expectedById.values) {
      final actual = actualById[expected.candidateId];
      final presented = actual?.presentedInVerifiedResults == true;
      allLogicalPhotos.add(expected.logicalPhotoId);
      if (expected.expectedVerifiedDeleted) {
        deletedLogicalPhotos.add(expected.logicalPhotoId);
      }

      if (presented) {
        verifiedByLogicalPhoto.update(
          expected.logicalPhotoId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (actual!.source != expected.expectedSource) sourceContamination++;
        if (expected.expectedClassification ==
            RecoveryClassification.existingMedia) {
          existingLeakage++;
        }
        if (expected.expectedClassification ==
            RecoveryClassification.possibleCopy) {
          possibleCopyLeakage++;
        }
        if (expected.expectedClassification ==
                RecoveryClassification.unclassified ||
            expected.expectedSource == MediaSource.unknown) {
          unknownLeakage++;
        }
      }

      restoreChecks += 2;
      if ((actual?.systemRestoreEligible ?? false) ==
          expected.expectedSystemRestoreEligible) {
        restoreCorrect++;
      }
      if ((actual?.shieldRestoreEligible ?? false) ==
          expected.expectedShieldRestoreEligible) {
        restoreCorrect++;
      }
    }

    final duplicateInflation = verifiedByLogicalPhoto.values.fold<int>(
      0,
      (total, count) => total + (count > 1 ? count - 1 : 0),
    );
    final presentedLogicalPhotos = verifiedByLogicalPhoto.keys.toSet();
    final truePositives = presentedLogicalPhotos
        .intersection(deletedLogicalPhotos)
        .length;
    final falsePositives = presentedLogicalPhotos
        .difference(deletedLogicalPhotos)
        .length;
    final falseNegatives = deletedLogicalPhotos
        .difference(presentedLogicalPhotos)
        .length;
    final trueNegatives = allLogicalPhotos
        .difference(deletedLogicalPhotos)
        .difference(presentedLogicalPhotos)
        .length;
    return RecoveryAccuracyBenchmarkReport(
      totalRecords: expectedById.length,
      groundTruthDeleted: deletedLogicalPhotos.length,
      truePositives: truePositives,
      falsePositives: falsePositives,
      falseNegatives: falseNegatives,
      trueNegatives: trueNegatives,
      sourceDomainContaminationCount: sourceContamination,
      duplicateResultInflationCount: duplicateInflation,
      existingMediaLeakageCount: existingLeakage,
      possibleCopyLeakageCount: possibleCopyLeakage,
      unknownItemLeakageCount: unknownLeakage,
      restoreEligibilityCorrectCount: restoreCorrect,
      restoreEligibilityCheckCount: restoreChecks,
    );
  }
}
