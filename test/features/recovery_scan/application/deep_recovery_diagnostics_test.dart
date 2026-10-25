import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/deep_recovery_diagnostics.dart';

void main() {
  test('diagnostics expose truthful candidate accounting', () {
    const diagnostics = DeepRecoveryDiagnostics(
      rawTrashRows: 3,
      deepRecordsDiscovered: 7,
      invalidFilesRejected: 2,
      ineligibleRecordsRejected: 1,
      duplicateRecordsSuppressed: 4,
      finalVerifiedDeleted: 5,
      finalFullQualityCopies: 2,
      finalReducedCopies: 1,
      finalUnknownQualityCopies: 1,
      finalThumbnailCopies: 3,
    );

    expect(diagnostics.discoveredCandidates, 10);
    expect(diagnostics.rejectedCandidates, 3);
    expect(diagnostics.finalPossibleCopies, 7);
    expect(diagnostics.visibleFinalResults, 12);
    expect(
      diagnostics.toDebugSummary(),
      contains(
        'candidateCounts: discovered=10, rejected=3, duplicates=4, possibleRecoverable=7, verifiedDeleted=5',
      ),
    );
  });
}
