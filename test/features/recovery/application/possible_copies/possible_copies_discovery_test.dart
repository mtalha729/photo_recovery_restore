import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/duplicate_resolution/duplicate_resolution_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/possible_copies/possible_copies_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/application/possible_copies/possible_copy_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery/domain/verified_content_digest.dart';

void main() {
  const discovery = PossibleCopiesDiscovery();
  final emptyIndex = ExistingMediaIndex.build(records: const []);

  MediaCandidate candidate(
    String id, {
    MediaSource source = MediaSource.cameraGallery,
    RecoveryClassification classification = RecoveryClassification.unclassified,
    RestoreCapability capability = RestoreCapability.originalFullQuality,
    RecoveryQuality quality = RecoveryQuality.original,
    Iterable<DeletionEvidenceReason> evidence = const [],
    Uri? uri,
    VerifiedContentDigest? digest,
    String? name,
    int? size,
    int? width,
    int? height,
    DateTime? takenAt,
  }) => MediaCandidate(
    id: id,
    source: source,
    contentUri: uri,
    displayName: name,
    byteSize: size,
    width: width,
    height: height,
    takenAt: takenAt,
    verifiedContentDigest: digest,
    classification: classification,
    deletionEvidence: DeletionEvidence(reasons: evidence),
    restoreCapability: capability,
    recoveryQuality: quality,
  );

  MediaCandidate deleted(
    String id, {
    MediaSource source = MediaSource.cameraGallery,
    VerifiedContentDigest? digest,
    RecoveryQuality quality = RecoveryQuality.original,
    String? name,
  }) => candidate(
    id,
    source: source,
    classification: RecoveryClassification.verifiedDeleted,
    evidence: const [DeletionEvidenceReason.systemTrashRecord],
    digest: digest,
    quality: quality,
    name: name,
  );

  PossibleCopyRelationship relationship(
    String original,
    String copy,
    PossibleCopyType type, {
    PossibleCopyRelationshipEvidence evidence =
        PossibleCopyRelationshipEvidence.explicitRelationship,
  }) => PossibleCopyRelationship(
    originalCandidateId: original,
    copyCandidateId: copy,
    type: type,
    evidence: evidence,
  );

  test('possible copy never enters or increases Verified Deleted', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [
        candidate(
          'copy',
          classification: RecoveryClassification.possibleCopy,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
      ],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'copy', PossibleCopyType.lowerResolution),
      ],
    );
    expect(result.verifiedDeletedCount, 1);
    expect(result.possibleCopyCount, 1);
    expect(
      result.groups.single.copies.single.classificationDecision.classification,
      RecoveryClassification.possibleCopy,
    );
  });

  test('explicit lower-resolution relationship works', () {
    final copy = candidate(
      'copy',
      capability: RestoreCapability.lowerResolutionCopy,
      quality: RecoveryQuality.reducedResolutionCopy,
    );
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [copy],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'copy', PossibleCopyType.lowerResolution),
      ],
    );
    expect(
      result.groups.single.copies.single.type,
      PossibleCopyType.lowerResolution,
    );
  });

  test('explicit alternate full-quality relationship works', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [
        candidate(
          'copy',
          capability: RestoreCapability.alternateFullQualityCopy,
        ),
      ],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'copy', PossibleCopyType.alternateFullQuality),
      ],
    );
    expect(
      result.groups.single.copies.single.type,
      PossibleCopyType.alternateFullQuality,
    );
  });

  test('verified digest creates a strong relationship', () {
    final digest = VerifiedContentDigest(algorithm: 'sha-256', value: 'abc');
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted', digest: digest)],
      accessibleCandidates: [candidate('copy', digest: digest)],
      existingMediaIndex: emptyIndex,
    );
    expect(result.possibleCopyCount, 1);
    expect(
      result.groups.single.copies.single.relationshipEvidence,
      contains(PossibleCopyRelationshipEvidence.verifiedContentDigest),
    );
  });

  test('filename alone is rejected', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted', name: 'same.jpg')],
      accessibleCandidates: [candidate('copy', name: 'same.jpg')],
      existingMediaIndex: emptyIndex,
    );
    expect(result.possibleCopyCount, 0);
  });

  test('size alone is rejected', () {
    expect(
      discovery
          .discover(
            verifiedDeletedCandidates: [deleted('deleted')],
            accessibleCandidates: [candidate('copy', size: 100)],
            existingMediaIndex: emptyIndex,
          )
          .possibleCopyCount,
      0,
    );
  });

  test('dimensions alone are rejected', () {
    expect(
      discovery
          .discover(
            verifiedDeletedCandidates: [deleted('deleted')],
            accessibleCandidates: [candidate('copy', width: 10, height: 10)],
            existingMediaIndex: emptyIndex,
          )
          .possibleCopyCount,
      0,
    );
  });

  test('timestamp alone is rejected', () {
    expect(
      discovery
          .discover(
            verifiedDeletedCandidates: [deleted('deleted')],
            accessibleCandidates: [
              candidate('copy', takenAt: DateTime.utc(2025)),
            ],
            existingMediaIndex: emptyIndex,
          )
          .possibleCopyCount,
      0,
    );
  });

  test('existing media remains existing when related to deleted media', () {
    final uri = Uri.parse('content://media/external/images/media/2');
    final copy = candidate('copy', uri: uri);
    final index = ExistingMediaIndex.build(
      records: [CurrentMediaRecord(mediaStoreId: 2, contentUri: uri)],
    );
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [copy],
      existingMediaIndex: index,
      relationships: [
        relationship(
          'deleted',
          'copy',
          PossibleCopyType.explicitlyRelatedAlternate,
        ),
      ],
    );
    expect(
      result.groups.single.copies.single.classificationDecision.classification,
      RecoveryClassification.existingMedia,
    );
    expect(copy.classification, RecoveryClassification.unclassified);
  });

  test('deletion classification and evidence are unchanged', () {
    final original = deleted('deleted');
    final copy = candidate(
      'copy',
      capability: RestoreCapability.lowerResolutionCopy,
    );
    discovery.discover(
      verifiedDeletedCandidates: [original],
      accessibleCandidates: [copy],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'copy', PossibleCopyType.lowerResolution),
      ],
    );
    expect(original.classification, RecoveryClassification.verifiedDeleted);
    expect(original.deletionEvidence.reasons, {
      DeletionEvidenceReason.systemTrashRecord,
    });
    expect(copy.deletionEvidence.isEmpty, isTrue);
  });

  test('source ownership is unchanged', () {
    final copy = candidate('copy', source: MediaSource.downloadsSavedMedia);
    discovery.discover(
      verifiedDeletedCandidates: [
        deleted('deleted', source: MediaSource.downloadsSavedMedia),
      ],
      accessibleCandidates: [copy],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship(
          'deleted',
          'copy',
          PossibleCopyType.explicitlyRelatedAlternate,
        ),
      ],
    );
    expect(copy.source, MediaSource.downloadsSavedMedia);
  });

  test('cross-domain relationship is rejected without leaking sources', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [
        candidate('copy', source: MediaSource.messagingSharedMedia),
      ],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship(
          'deleted',
          'copy',
          PossibleCopyType.explicitlyRelatedAlternate,
        ),
      ],
    );
    expect(result.groups, isEmpty);
    expect(result.verifiedDeletedCount, 1);
  });

  test('best-copy selection reuses Milestone 12 ordering', () {
    final original = deleted('deleted', quality: RecoveryQuality.corrupted);
    final full = candidate(
      'full',
      capability: RestoreCapability.alternateFullQualityCopy,
    );
    final lower = candidate(
      'lower',
      capability: RestoreCapability.lowerResolutionCopy,
      quality: RecoveryQuality.reducedResolutionCopy,
    );
    final result = discovery.discover(
      verifiedDeletedCandidates: [original],
      accessibleCandidates: [lower, full],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'lower', PossibleCopyType.lowerResolution),
        relationship('deleted', 'full', PossibleCopyType.alternateFullQuality),
      ],
    );
    expect(result.groups.single.bestCopyCandidate.id, 'full');
    expect(
      result.groups.single.bestCopySelectionCategory,
      BestCopySelectionCategory.alternateFullQuality,
    );
  });

  test('thumbnail does not outrank full-quality copy', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [
        deleted('deleted', quality: RecoveryQuality.corrupted),
      ],
      accessibleCandidates: [
        candidate(
          'thumb',
          width: 100,
          height: 100,
          capability: RestoreCapability.lowerResolutionCopy,
          quality: RecoveryQuality.reducedResolutionCopy,
        ),
        candidate(
          'full',
          capability: RestoreCapability.alternateFullQualityCopy,
        ),
      ],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship('deleted', 'thumb', PossibleCopyType.thumbnailSized),
        relationship('deleted', 'full', PossibleCopyType.alternateFullQuality),
      ],
    );
    expect(result.groups.single.bestCopyCandidate.id, 'full');
  });

  test('corrupted copy does not outrank intact copy', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [
        deleted('deleted', quality: RecoveryQuality.corrupted),
      ],
      accessibleCandidates: [
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
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship(
          'deleted',
          'corrupt',
          PossibleCopyType.unknownQualityAlternate,
        ),
        relationship('deleted', 'intact', PossibleCopyType.lowerResolution),
      ],
    );
    expect(result.groups.single.bestCopyCandidate.id, 'intact');
  });

  test('unknown relationship remains unclassified and undiscovered', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [candidate('unknown')],
      existingMediaIndex: emptyIndex,
    );
    expect(result.groups, isEmpty);
  });

  test('duplicate copy records do not inflate logical copy count', () {
    final digest = VerifiedContentDigest(algorithm: 'sha-256', value: 'copy');
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [
        candidate('copy-a', digest: digest),
        candidate('copy-b', digest: digest),
      ],
      existingMediaIndex: emptyIndex,
      relationships: [
        relationship(
          'deleted',
          'copy-a',
          PossibleCopyType.alternateFullQuality,
        ),
        relationship(
          'deleted',
          'copy-b',
          PossibleCopyType.alternateFullQuality,
        ),
      ],
    );
    expect(result.possibleCopyCount, 1);
    expect(result.groups.single.copies.single.duplicateRecordCount, 2);
  });

  test('output is deterministic regardless of input order', () {
    final a = candidate('a', capability: RestoreCapability.lowerResolutionCopy);
    final b = candidate(
      'b',
      capability: RestoreCapability.alternateFullQualityCopy,
    );
    final links = [
      relationship('deleted', 'a', PossibleCopyType.lowerResolution),
      relationship('deleted', 'b', PossibleCopyType.alternateFullQuality),
    ];
    final first = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [a, b],
      existingMediaIndex: emptyIndex,
      relationships: links,
    );
    final second = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: [b, a],
      existingMediaIndex: emptyIndex,
      relationships: links.reversed,
    );
    expect(
      first.groups.single.copies.map((value) => value.candidate.id),
      second.groups.single.copies.map((value) => value.candidate.id),
    );
    expect(
      first.groups.single.bestCopyCandidate.id,
      second.groups.single.bestCopyCandidate.id,
    );
  });

  test('large indexed relationship set avoids pairwise discovery', () {
    final originals = <MediaCandidate>[];
    final copies = <MediaCandidate>[];
    for (var index = 0; index < 1000; index++) {
      final digest = VerifiedContentDigest(
        algorithm: 'sha-256',
        value: 'digest-$index',
      );
      originals.add(deleted('deleted-$index', digest: digest));
      copies.add(candidate('copy-$index', digest: digest));
    }
    final result = discovery.discover(
      verifiedDeletedCandidates: originals,
      accessibleCandidates: copies,
      existingMediaIndex: emptyIndex,
    );
    expect(result.groups, hasLength(1000));
    expect(result.possibleCopyCount, 1000);
  });

  test('pipeline exposes metadata only and performs no image operations', () {
    final result = discovery.discover(
      verifiedDeletedCandidates: [deleted('deleted')],
      accessibleCandidates: const [],
      existingMediaIndex: emptyIndex,
    );
    expect(result.verifiedDeletedCount, 1);
    expect(result.possibleCopyCount, 0);
  });
}
