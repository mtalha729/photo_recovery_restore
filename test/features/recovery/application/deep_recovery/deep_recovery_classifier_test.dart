import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_classifier.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/possible_copies/possible_copy_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  const classifier = DeepRecoveryClassifier();
  const noMatch = ExistingMediaDecision.noExistingMatch();

  MediaCandidate candidate({
    MediaSource source = MediaSource.cameraGallery,
    RecoveryClassification classification = RecoveryClassification.unclassified,
    Iterable<DeletionEvidenceReason> evidence = const [],
    bool isRecoveryShieldBackup = false,
    RestoreCapability capability = RestoreCapability.notRestorable,
    RecoveryQuality quality = RecoveryQuality.metadataOnly,
    int? width,
    int? height,
  }) => MediaCandidate(
    id: 'candidate',
    source: source,
    classification: classification,
    deletionEvidence: DeletionEvidence(reasons: evidence),
    restoreCapability: capability,
    recoveryQuality: quality,
    width: width,
    height: height,
    discoveryEvidence: RecoveryDiscoveryEvidence(
      isRecoveryShieldBackup: isRecoveryShieldBackup,
    ),
  );

  test('existing identity always blocks deleted presentation', () {
    const existing = ExistingMediaDecision.definitelyExisting(
      ExistingMediaReference(record: CurrentMediaRecord(mediaStoreId: 7)),
    );
    final value = candidate(
      evidence: const [DeletionEvidenceReason.systemTrashRecord],
      capability: RestoreCapability.originalFullQuality,
      quality: RecoveryQuality.original,
    );

    expect(
      classifier.classify(candidate: value, existingMediaDecision: existing),
      DeepRecoveryDisposition.existingMedia,
    );
  });

  test('system trash is deleted evidence; Shield records stay protected copies', () {
    expect(
      classifier.classify(
        candidate: candidate(
          evidence: const [DeletionEvidenceReason.systemTrashRecord],
        ),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.verifiedDeleted,
    );
    expect(
      classifier.classify(
        candidate: candidate(
          isRecoveryShieldBackup: true,
          evidence: const [DeletionEvidenceReason.systemTrashRecord],
        ),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.protectedCopy,
    );
    expect(
      classifier.classify(
        candidate: candidate(),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.unclassified,
    );
  });

  test('proven alternate copies preserve objective quality buckets', () {
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.alternateFullQualityCopy,
          quality: RecoveryQuality.completeCopy,
        ),
        existingMediaDecision: noMatch,
        provenCopyType: PossibleCopyType.alternateFullQuality,
      ),
      DeepRecoveryDisposition.possibleFullQualityCopy,
    );
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
          width: 1600,
          height: 900,
        ),
        existingMediaDecision: noMatch,
        provenCopyType: PossibleCopyType.lowerResolution,
      ),
      DeepRecoveryDisposition.possibleLowerQualityCopy,
    );
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
          width: 320,
          height: 240,
        ),
        existingMediaDecision: noMatch,
        provenCopyType: PossibleCopyType.thumbnailSized,
      ),
      DeepRecoveryDisposition.thumbnailCopy,
    );
  });

  test('unknown-quality copies remain recoverable without a quality claim', () {
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.unknownQualityCopy,
          quality: RecoveryQuality.unknownQualityCopy,
        ),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.possibleUnknownQualityCopy,
    );
  });

  test('classification never changes source ownership', () {
    final value = candidate(
      source: MediaSource.messagingSharedMedia,
      evidence: const [DeletionEvidenceReason.systemTrashRecord],
    );
    classifier.classify(candidate: value, existingMediaDecision: noMatch);
    expect(value.source, MediaSource.messagingSharedMedia);
  });

  test('corrupted and unavailable remain explicit non-deleted states', () {
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.corrupted,
          quality: RecoveryQuality.corrupted,
        ),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.corrupted,
    );
    expect(
      classifier.classify(
        candidate: candidate(
          classification: RecoveryClassification.unavailable,
          quality: RecoveryQuality.unavailable,
        ),
        existingMediaDecision: noMatch,
      ),
      DeepRecoveryDisposition.unavailable,
    );
  });}
