import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  MediaCandidate candidate({
    required RecoveryClassification classification,
    RestoreCapability restoreCapability = RestoreCapability.notRestorable,
    bool isRecoveryShieldBackup = false,
  }) {
    return MediaCandidate(
      id: 'candidate-1',
      source: MediaSource.unknown,
      classification: classification,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: restoreCapability,
      recoveryQuality: RecoveryQuality.unavailable,
      discoveryEvidence: RecoveryDiscoveryEvidence(
        isRecoveryShieldBackup: isRecoveryShieldBackup,
      ),
    );
  }

  group('Recovery classification invariants', () {
    test('existing media is never a verified deleted result', () {
      final existing = candidate(
        classification: RecoveryClassification.existingMedia,
      );

      expect(existing.isVerifiedDeleted, isFalse);
      expect(existing.isDeletedRecoveryResult, isFalse);
    });

    test('possible copies remain distinct from verified deleted media', () {
      final possibleCopy = candidate(
        classification: RecoveryClassification.possibleCopy,
      );

      expect(possibleCopy.isVerifiedDeleted, isFalse);
      expect(possibleCopy.isDeletedRecoveryResult, isFalse);
    });

    test('Recovery Shield backups are not deletion evidence', () {
      final protected = candidate(
        classification: RecoveryClassification.protectedCopy,
        isRecoveryShieldBackup: true,
      );

      expect(protected.isVerifiedDeleted, isFalse);
      expect(protected.isDeletedRecoveryResult, isFalse);
      expect(protected.deletionEvidence.isEmpty, isTrue);
      expect(protected.discoveryEvidence.isRecoveryShieldBackup, isTrue);
    });
  });

  test('unknown metadata is represented without placeholder values', () {
    final unknown = candidate(
      classification: RecoveryClassification.unavailable,
    );

    expect(unknown.contentUri, isNull);
    expect(unknown.filePath, isNull);
    expect(unknown.displayName, isNull);
    expect(unknown.byteSize, isNull);
    expect(unknown.width, isNull);
    expect(unknown.takenAt, isNull);
    expect(unknown.deletionEvidence.isEmpty, isTrue);
  });

  test(
    'restore capability distinguishes full quality, lower quality, and none',
    () {
      expect(RestoreCapability.originalFullQuality.isFullQuality, isTrue);
      expect(RestoreCapability.lowerResolutionCopy.isFullQuality, isFalse);
      expect(RestoreCapability.lowerResolutionCopy.hasRecoverableBytes, isTrue);
      expect(RestoreCapability.metadataOnly.hasRecoverableBytes, isFalse);
      expect(RestoreCapability.notRestorable.hasRecoverableBytes, isFalse);
    },
  );
}
