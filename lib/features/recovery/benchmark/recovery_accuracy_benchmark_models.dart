import '../domain/media_source.dart';
import '../domain/recovery_classification.dart';

class RecoveryBenchmarkGroundTruth {
  const RecoveryBenchmarkGroundTruth({
    required this.candidateId,
    required this.logicalPhotoId,
    required this.expectedClassification,
    required this.expectedSource,
    required this.expectedSystemRestoreEligible,
    required this.expectedShieldRestoreEligible,
  });

  final String candidateId;
  final String logicalPhotoId;
  final RecoveryClassification expectedClassification;
  final MediaSource expectedSource;
  final bool expectedSystemRestoreEligible;
  final bool expectedShieldRestoreEligible;

  bool get expectedVerifiedDeleted =>
      expectedClassification == RecoveryClassification.verifiedDeleted;
}

class RecoveryBenchmarkObservation {
  const RecoveryBenchmarkObservation({
    required this.candidateId,
    required this.logicalPhotoId,
    required this.classification,
    required this.source,
    required this.presentedInVerifiedResults,
    required this.systemRestoreEligible,
    required this.shieldRestoreEligible,
  });

  final String candidateId;
  final String logicalPhotoId;
  final RecoveryClassification classification;
  final MediaSource source;
  final bool presentedInVerifiedResults;
  final bool systemRestoreEligible;
  final bool shieldRestoreEligible;
}

class RecoveryAccuracyBenchmarkReport {
  const RecoveryAccuracyBenchmarkReport({
    required this.totalRecords,
    required this.groundTruthDeleted,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.trueNegatives,
    required this.sourceDomainContaminationCount,
    required this.duplicateResultInflationCount,
    required this.existingMediaLeakageCount,
    required this.possibleCopyLeakageCount,
    required this.unknownItemLeakageCount,
    required this.restoreEligibilityCorrectCount,
    required this.restoreEligibilityCheckCount,
  });

  final int totalRecords;
  final int groundTruthDeleted;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int trueNegatives;
  final int sourceDomainContaminationCount;
  final int duplicateResultInflationCount;
  final int existingMediaLeakageCount;
  final int possibleCopyLeakageCount;
  final int unknownItemLeakageCount;
  final int restoreEligibilityCorrectCount;
  final int restoreEligibilityCheckCount;

  double get precision => _ratio(truePositives, truePositives + falsePositives);

  double get recall => _ratio(truePositives, truePositives + falseNegatives);

  double get falsePositiveRate =>
      _ratio(falsePositives, falsePositives + trueNegatives);

  double get restoreEligibilityAccuracy =>
      _ratio(restoreEligibilityCorrectCount, restoreEligibilityCheckCount);

  String get diagnosticSummary => [
    'Total ground-truth deleted: $groundTruthDeleted',
    'Correctly identified:       $truePositives',
    'False positives:            $falsePositives',
    'False negatives:            $falseNegatives',
    'Existing leaked:            $existingMediaLeakageCount',
    'Source contamination:       $sourceDomainContaminationCount',
    'Possible-copy leakage:      $possibleCopyLeakageCount',
    'Unknown-item leakage:       $unknownItemLeakageCount',
    'Duplicate inflation:        $duplicateResultInflationCount',
  ].join('\n');

  static double _ratio(int numerator, int denominator) =>
      denominator == 0 ? 0 : numerator / denominator;
}
