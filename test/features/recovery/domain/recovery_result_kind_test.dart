import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_result_kind.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  MediaCandidate candidate(
    RecoveryClassification classification, {
    RecoveryDiscoveryEvidence evidence = const RecoveryDiscoveryEvidence(),
    RecoveryQuality quality = RecoveryQuality.unknownQualityCopy,
  }) => MediaCandidate(
    id: 'photo:${classification.name}:${evidence.hashCode}',
    source: MediaSource.unknown,
    classification: classification,
    deletionEvidence: DeletionEvidence(),
    restoreCapability: RestoreCapability.unknownQualityCopy,
    recoveryQuality: quality,
    discoveryEvidence: evidence,
  );

  test(
    'existing and possible photos remain distinct from verified deletion',
    () {
      expect(
        resultKindFor(candidate(RecoveryClassification.existingMedia)),
        RecoveryResultKind.existingPhoto,
      );
      expect(
        resultKindFor(candidate(RecoveryClassification.possibleCopy)),
        RecoveryResultKind.possibleRecoverable,
      );
      expect(
        resultKindFor(candidate(RecoveryClassification.verifiedDeleted)),
        RecoveryResultKind.verifiedDeleted,
      );
    },
  );

  test('cache and thumbnail evidence override generic copy quality', () {
    expect(
      resultKindFor(
        candidate(
          RecoveryClassification.possibleCopy,
          evidence: const RecoveryDiscoveryEvidence(isThumbnailLike: true),
        ),
      ),
      RecoveryResultKind.thumbnail,
    );
    expect(
      resultKindFor(
        candidate(
          RecoveryClassification.possibleCopy,
          evidence: const RecoveryDiscoveryEvidence(isCacheLike: true),
        ),
      ),
      RecoveryResultKind.cachedImage,
    );
    expect(
      resultKindFor(
        candidate(
          RecoveryClassification.possibleCopy,
          quality: RecoveryQuality.completeCopy,
        ),
      ),
      RecoveryResultKind.recoverableCopy,
    );
  });
}
