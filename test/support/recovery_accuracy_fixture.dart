import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_engine.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_evidence_classifier.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_resolution/media_source_resolver.dart';
import 'package:photo_recovery_restore/features/recovery/benchmark/recovery_accuracy_benchmark_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/current_media_metadata.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery/domain/verified_content_digest.dart';

class RecoveryAccuracyFixture {
  const RecoveryAccuracyFixture({
    required this.candidates,
    required this.groundTruth,
    required this.existingMediaIndex,
  });

  final List<MediaCandidate> candidates;
  final List<RecoveryBenchmarkGroundTruth> groundTruth;
  final ExistingMediaIndex existingMediaIndex;
}

RecoveryAccuracyFixture buildMixedAccuracyFixture() {
  final candidates = <MediaCandidate>[];
  final truth = <RecoveryBenchmarkGroundTruth>[];
  final currentRecords = <CurrentMediaRecord>[];

  void add({
    required String id,
    required MediaSource source,
    required RecoveryClassification expected,
    required bool current,
    String? logicalId,
    Iterable<DeletionEvidenceReason> evidence = const [],
    RestoreCapability capability = RestoreCapability.originalFullQuality,
    RecoveryQuality quality = RecoveryQuality.original,
    VerifiedContentDigest? digest,
    bool shieldRestoreEligible = false,
    bool missingMetadata = false,
  }) {
    final number = candidates.length + 1;
    final uri = Uri.parse('content://benchmark/images/$number');
    final candidate = MediaCandidate(
      id: id,
      source: source,
      contentUri: missingMetadata ? null : uri,
      mediaStoreId: missingMetadata ? null : number,
      storageVolumeName: missingMetadata ? null : 'external_primary',
      displayName: missingMetadata ? null : '$id.jpg',
      mimeType: missingMetadata ? null : 'image/jpeg',
      width: missingMetadata ? null : 1200,
      height: missingMetadata ? null : 800,
      verifiedContentDigest: digest,
      classification:
          expected == RecoveryClassification.possibleCopy ||
              expected == RecoveryClassification.corrupted ||
              expected == RecoveryClassification.unavailable
          ? expected
          : RecoveryClassification.unclassified,
      deletionEvidence: DeletionEvidence(reasons: evidence),
      restoreCapability: capability,
      recoveryQuality: quality,
    );
    candidates.add(candidate);
    if (current) {
      currentRecords.add(
        CurrentMediaRecord(mediaStoreId: number, contentUri: uri),
      );
    }
    truth.add(
      RecoveryBenchmarkGroundTruth(
        candidateId: id,
        logicalPhotoId: logicalId ?? id,
        expectedClassification: expected,
        expectedSource: source,
        expectedSystemRestoreEligible:
            expected == RecoveryClassification.verifiedDeleted,
        expectedShieldRestoreEligible: shieldRestoreEligible,
      ),
    );
  }

  for (final entry in const [
    ('camera-current', MediaSource.cameraGallery),
    ('screenshot-current', MediaSource.screenshots),
    ('download-current', MediaSource.downloadsSavedMedia),
    ('messaging-current', MediaSource.messagingSharedMedia),
  ]) {
    add(
      id: entry.$1,
      source: entry.$2,
      expected: RecoveryClassification.existingMedia,
      current: true,
    );
  }
  for (final entry in const [
    ('camera-deleted', MediaSource.cameraGallery),
    ('screenshot-deleted', MediaSource.screenshots),
    ('download-deleted', MediaSource.downloadsSavedMedia),
    ('messaging-deleted', MediaSource.messagingSharedMedia),
    ('sd-deleted', MediaSource.sdCard),
  ]) {
    add(
      id: entry.$1,
      source: entry.$2,
      expected: RecoveryClassification.verifiedDeleted,
      current: false,
      evidence: const [DeletionEvidenceReason.systemTrashRecord],
    );
  }
  final duplicateDigest = VerifiedContentDigest(
    algorithm: 'sha-256',
    value: 'duplicate',
  );
  add(
    id: 'duplicate-a',
    logicalId: 'duplicate-photo',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.verifiedDeleted,
    current: false,
    evidence: const [DeletionEvidenceReason.systemTrashRecord],
    digest: duplicateDigest,
  );
  add(
    id: 'duplicate-b',
    logicalId: 'duplicate-photo',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.verifiedDeleted,
    current: false,
    evidence: const [DeletionEvidenceReason.systemTrashRecord],
    digest: duplicateDigest,
  );
  add(
    id: 'possible-copy',
    logicalId: 'camera-deleted',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.possibleCopy,
    current: false,
    capability: RestoreCapability.lowerResolutionCopy,
    quality: RecoveryQuality.reducedResolutionCopy,
  );
  add(
    id: 'corrupted',
    source: MediaSource.downloadsSavedMedia,
    expected: RecoveryClassification.corrupted,
    current: false,
    capability: RestoreCapability.notRestorable,
    quality: RecoveryQuality.corrupted,
  );
  add(
    id: 'unavailable',
    source: MediaSource.messagingSharedMedia,
    expected: RecoveryClassification.unavailable,
    current: false,
    capability: RestoreCapability.notRestorable,
    quality: RecoveryQuality.unavailable,
  );
  add(
    id: 'shield-protected-only',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.unclassified,
    current: false,
    capability: RestoreCapability.protectedOriginal,
    shieldRestoreEligible: true,
  );
  add(
    id: 'unknown',
    source: MediaSource.unknown,
    expected: RecoveryClassification.unclassified,
    current: false,
    missingMetadata: true,
  );
  add(
    id: 'no-match-only',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.unclassified,
    current: false,
  );
  add(
    id: 'contradictory-existing-trash',
    source: MediaSource.cameraGallery,
    expected: RecoveryClassification.existingMedia,
    current: true,
    evidence: const [DeletionEvidenceReason.systemTrashRecord],
  );

  return RecoveryAccuracyFixture(
    candidates: List.unmodifiable(candidates),
    groundTruth: List.unmodifiable(truth),
    existingMediaIndex: ExistingMediaIndex.build(records: currentRecords),
  );
}

RecoveryAccuracyFixture buildLargeAccuracyFixture(int count) {
  final candidates = <MediaCandidate>[];
  final truth = <RecoveryBenchmarkGroundTruth>[];
  final currentRecords = <CurrentMediaRecord>[];
  for (var index = 0; index < count; index++) {
    final deleted = index % 10 == 0;
    final source = MediaSource.values[index % 6];
    final uri = Uri.parse('content://benchmark/large/$index');
    candidates.add(
      MediaCandidate(
        id: 'large-$index',
        source: source,
        contentUri: uri,
        mediaStoreId: index,
        storageVolumeName: 'external_primary',
        classification: RecoveryClassification.unclassified,
        deletionEvidence: DeletionEvidence(
          reasons: deleted
              ? const [DeletionEvidenceReason.systemTrashRecord]
              : const [],
        ),
        restoreCapability: RestoreCapability.originalFullQuality,
        recoveryQuality: RecoveryQuality.original,
      ),
    );
    if (!deleted) {
      currentRecords.add(
        CurrentMediaRecord(mediaStoreId: index, contentUri: uri),
      );
    }
    truth.add(
      RecoveryBenchmarkGroundTruth(
        candidateId: 'large-$index',
        logicalPhotoId: 'large-$index',
        expectedClassification: deleted
            ? RecoveryClassification.verifiedDeleted
            : RecoveryClassification.existingMedia,
        expectedSource: source,
        expectedSystemRestoreEligible: deleted,
        expectedShieldRestoreEligible: false,
      ),
    );
  }
  return RecoveryAccuracyFixture(
    candidates: List.unmodifiable(candidates),
    groundTruth: List.unmodifiable(truth),
    existingMediaIndex: ExistingMediaIndex.build(records: currentRecords),
  );
}

List<RecoveryBenchmarkObservation> observeFixture(
  RecoveryAccuracyFixture fixture, {
  Set<String> presentedCandidateIds = const {},
}) {
  const classifier = RecoveryEvidenceClassifier();
  const restorePolicy = SystemTrashRestorePolicy();
  final truthById = {
    for (final expected in fixture.groundTruth) expected.candidateId: expected,
  };
  return fixture.candidates
      .map((candidate) {
        final decision = classifier.classify(
          candidate: candidate,
          existingMediaDecision: const ExistingMediaExclusionEngine().evaluate(
            candidate,
            fixture.existingMediaIndex,
          ),
        );
        final restore = restorePolicy.evaluate(
          SystemTrashRestoreRequest(
            requestId: candidate.id,
            candidate: candidate,
            classificationDecision: decision,
          ),
          androidApiLevel: 35,
        );
        return RecoveryBenchmarkObservation(
          candidateId: candidate.id,
          logicalPhotoId: truthById[candidate.id]!.logicalPhotoId,
          classification: decision.classification,
          source: candidate.source,
          presentedInVerifiedResults: presentedCandidateIds.contains(
            candidate.id,
          ),
          systemRestoreEligible: restore.isEligible,
          shieldRestoreEligible: candidate.id == 'shield-protected-only',
        );
      })
      .toList(growable: false);
}

MediaSource resolveBenchmarkSource({
  required String path,
  String volume = 'external_primary',
  bool removable = false,
}) => const MediaSourceResolver().resolve(
  CurrentMediaMetadata(
    mediaStoreId: 1,
    contentUri: Uri.parse('content://benchmark/1'),
    relativePath: path,
    storageVolumeName: volume,
    isRemovableStorage: removable,
  ),
);
