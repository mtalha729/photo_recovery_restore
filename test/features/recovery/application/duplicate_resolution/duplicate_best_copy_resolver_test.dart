import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/duplicate_resolution/duplicate_best_copy_resolver.dart';
import 'package:photo_recovery_restore/features/recovery/application/duplicate_resolution/duplicate_resolution_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery/domain/verified_content_digest.dart';

void main() {
  const resolver = DuplicateBestCopyResolver();

  MediaCandidate candidate(
    String id, {
    MediaSource source = MediaSource.cameraGallery,
    Uri? contentUri,
    int? mediaStoreId,
    String? volume,
    VerifiedContentDigest? digest,
    String? name,
    int? byteSize,
    int? width,
    int? height,
    DateTime? takenAt,
    RecoveryClassification classification =
        RecoveryClassification.verifiedDeleted,
    RestoreCapability capability = RestoreCapability.originalFullQuality,
    RecoveryQuality quality = RecoveryQuality.original,
  }) => MediaCandidate(
    id: id,
    source: source,
    contentUri: contentUri,
    mediaStoreId: mediaStoreId,
    storageVolumeName: volume,
    verifiedContentDigest: digest,
    displayName: name,
    byteSize: byteSize,
    width: width,
    height: height,
    takenAt: takenAt,
    classification: classification,
    deletionEvidence: DeletionEvidence(
      reasons: classification == RecoveryClassification.verifiedDeleted
          ? const [DeletionEvidenceReason.systemTrashRecord]
          : const [],
    ),
    restoreCapability: capability,
    recoveryQuality: quality,
  );

  CopyRelationship related(String a, String b) => CopyRelationship(
    firstCandidateId: a,
    secondCandidateId: b,
    type: CopyRelationshipType.alternateVariant,
  );

  test('identical stable platform identity groups correctly', () {
    final result = resolver.resolve(
      candidates: [
        candidate('a', mediaStoreId: 10, volume: 'external_primary'),
        candidate('b', mediaStoreId: 10, volume: 'external_primary'),
      ],
    );
    expect(result.uniquePhotoCount, 1);
    expect(result.groups.single.confirmedExactDuplicates, hasLength(1));
    expect(
      result.groups.single.groupingEvidence,
      contains(DuplicateGroupingEvidence.stablePlatformIdentity),
    );
  });

  test('identical stable content URI groups correctly', () {
    final uri = Uri.parse('content://media/external/images/media/10');
    final result = resolver.resolve(
      candidates: [
        candidate('a', contentUri: uri),
        candidate('b', contentUri: uri),
      ],
    );
    expect(result.uniquePhotoCount, 1);
  });

  test('identical verified digest groups correctly', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'a',
          digest: VerifiedContentDigest(algorithm: 'SHA-256', value: 'ABC'),
        ),
        candidate(
          'b',
          digest: VerifiedContentDigest(algorithm: 'sha-256', value: 'abc'),
        ),
      ],
    );
    expect(result.uniquePhotoCount, 1);
    expect(
      result.groups.single.groupingEvidence,
      contains(DuplicateGroupingEvidence.verifiedContentDigest),
    );
  });

  test('different digest algorithms do not group', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'a',
          digest: VerifiedContentDigest(algorithm: 'sha-256', value: 'abc'),
        ),
        candidate(
          'b',
          digest: VerifiedContentDigest(algorithm: 'sha-512', value: 'abc'),
        ),
      ],
    );
    expect(result.uniquePhotoCount, 2);
  });

  test('filename alone does not group', () {
    final result = resolver.resolve(
      candidates: [
        candidate('a', name: 'photo.jpg'),
        candidate('b', name: 'photo.jpg'),
      ],
    );
    expect(result.uniquePhotoCount, 2);
  });

  test('same size alone does not group', () {
    expect(
      resolver
          .resolve(
            candidates: [
              candidate('a', byteSize: 50),
              candidate('b', byteSize: 50),
            ],
          )
          .uniquePhotoCount,
      2,
    );
  });

  test('same dimensions alone do not group', () {
    expect(
      resolver
          .resolve(
            candidates: [
              candidate('a', width: 100, height: 100),
              candidate('b', width: 100, height: 100),
            ],
          )
          .uniquePhotoCount,
      2,
    );
  });

  test('same timestamp alone does not group', () {
    final time = DateTime.utc(2025);
    expect(
      resolver
          .resolve(
            candidates: [
              candidate('a', takenAt: time),
              candidate('b', takenAt: time),
            ],
          )
          .uniquePhotoCount,
      2,
    );
  });

  test('weak composite metadata does not merge', () {
    final values = [
      candidate('a', name: 'x.jpg', byteSize: 12, width: 4, height: 3),
      candidate('b', name: 'x.jpg', byteSize: 12, width: 4, height: 3),
    ];
    expect(resolver.resolve(candidates: values).uniquePhotoCount, 2);
  });

  test('intact original wins over lower-resolution copy', () {
    final result = resolver.resolve(
      candidates: [
        candidate('original'),
        candidate(
          'lower',
          width: 5000,
          height: 5000,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
      ],
      relationships: [related('original', 'lower')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'original');
  });

  test('protected original wins over alternate full-quality copy', () {
    final result = resolver.resolve(
      candidates: [
        candidate('protected', capability: RestoreCapability.protectedOriginal),
        candidate(
          'alternate',
          capability: RestoreCapability.alternateFullQualityCopy,
        ),
      ],
      relationships: [related('protected', 'alternate')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'protected');
    expect(
      result.groups.single.selectionCategory,
      BestCopySelectionCategory.protectedOriginal,
    );
  });

  test('alternate full quality beats lower-resolution copy', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'alternate',
          capability: RestoreCapability.alternateFullQualityCopy,
        ),
        candidate('lower', capability: RestoreCapability.lowerResolutionCopy),
      ],
      relationships: [related('alternate', 'lower')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'alternate');
  });

  test('highest-resolution intact lower-quality variant wins', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'small',
          width: 320,
          height: 240,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
        candidate(
          'large',
          width: 1920,
          height: 1080,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
      ],
      relationships: [related('small', 'large')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'large');
  });

  test('corrupted candidate does not beat intact candidate', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'corrupt',
          classification: RecoveryClassification.corrupted,
          quality: RecoveryQuality.corrupted,
        ),
        candidate(
          'intact',
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
      ],
      relationships: [related('corrupt', 'intact')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'intact');
  });

  test('unavailable non-restorable candidate does not beat usable copy', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'missing',
          classification: RecoveryClassification.unavailable,
          capability: RestoreCapability.notRestorable,
          quality: RecoveryQuality.unavailable,
        ),
        candidate(
          'usable',
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
      ],
      relationships: [related('missing', 'usable')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'usable');
  });

  test('stable ID deterministically breaks otherwise equal ties', () {
    final result = resolver.resolve(
      candidates: [candidate('z'), candidate('a')],
      relationships: [related('z', 'a')],
    );
    expect(result.groups.single.canonicalCandidate.id, 'a');
  });

  test('input order does not affect grouping or canonical choice', () {
    final forward = resolver.resolve(
      candidates: [candidate('b'), candidate('a')],
      relationships: [related('a', 'b')],
    );
    final reverse = resolver.resolve(
      candidates: [candidate('a'), candidate('b')],
      relationships: [related('a', 'b')],
    );
    expect(
      forward.groups.single.canonicalCandidate.id,
      reverse.groups.single.canonicalCandidate.id,
    );
    expect(
      forward.groups.single.groupedRecordCount,
      reverse.groups.single.groupedRecordCount,
    );
  });

  test('grouping reduces photo count without losing records', () {
    final result = resolver.resolve(
      candidates: [
        candidate('a'),
        candidate('b'),
        candidate('c'),
        candidate('d'),
      ],
      relationships: [related('a', 'b'), related('b', 'c')],
    );
    expect(result.uniquePhotoCount, 2);
    expect(result.inputRecordCount, 4);
    expect(result.groups.map((group) => group.groupedRecordCount), contains(3));
  });

  test('source domains are never merged even with identical digest', () {
    final digest = VerifiedContentDigest(algorithm: 'sha-256', value: 'same');
    final result = resolver.resolve(
      candidates: [
        candidate('camera', digest: digest),
        candidate(
          'message',
          source: MediaSource.messagingSharedMedia,
          digest: digest,
        ),
      ],
      relationships: [related('camera', 'message')],
    );
    expect(result.uniquePhotoCount, 2);
    expect(
      result.groups.map((group) => group.canonicalCandidate.source).toSet(),
      {MediaSource.cameraGallery, MediaSource.messagingSharedMedia},
    );
  });

  test('grouping preserves deletion classification and evidence', () {
    final existing = candidate(
      'existing',
      classification: RecoveryClassification.existingMedia,
    );
    final deleted = candidate('deleted');
    final result = resolver.resolve(
      candidates: [existing, deleted],
      relationships: [related('existing', 'deleted')],
    );
    final retained = result.groups.single.allCandidates;
    expect(
      retained.singleWhere((value) => value.id == 'existing').classification,
      RecoveryClassification.existingMedia,
    );
    expect(
      retained.singleWhere((value) => value.id == 'deleted').classification,
      RecoveryClassification.verifiedDeleted,
    );
  });

  test('possible copy remains distinct from verified deletion', () {
    final result = resolver.resolve(
      candidates: [
        candidate(
          'copy',
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
        candidate('deleted'),
      ],
      relationships: [related('copy', 'deleted')],
    );
    expect(
      result.groups.single.allCandidates
          .singleWhere((value) => value.id == 'copy')
          .classification,
      RecoveryClassification.possibleCopy,
    );
  });

  test('missing metadata is safe and remains ungrouped', () {
    final result = resolver.resolve(
      candidates: [candidate('a'), candidate('b')],
    );
    expect(result.uniquePhotoCount, 2);
  });

  test('indexed grouping handles a large set without pairwise evidence', () {
    final values = List.generate(
      2000,
      (index) => candidate(
        'id-$index',
        digest: VerifiedContentDigest(
          algorithm: 'sha-256',
          value: 'digest-${index ~/ 2}',
        ),
      ),
    );
    final result = resolver.resolve(candidates: values);
    expect(result.uniquePhotoCount, 1000);
    expect(result.inputRecordCount, 2000);
  });

  test('resolver API introduces no image payload or perceptual matching', () {
    final result = resolver.resolve(candidates: [candidate('a')]);
    expect(result.groups.single.canonicalCandidate.id, 'a');
    expect(result.groups.single.groupingEvidence, isEmpty);
  });
}
