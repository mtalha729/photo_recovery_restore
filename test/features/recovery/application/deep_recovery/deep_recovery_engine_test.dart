import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_classifier.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_engine.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/possible_copies/possible_copy_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/scan_cancellation.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  final emptyIndex = ExistingMediaIndex.build(records: const []);

  test('pages every provider, suppresses duplicates, and classifies explicit trash only', () async {
    final deleted = candidate(
      id: 'deleted',
      evidence: const [DeletionEvidenceReason.systemTrashRecord],
      capability: RestoreCapability.originalFullQuality,
      quality: RecoveryQuality.original,
    );
    final orphan = candidate(id: 'orphan');
    final provider = _PagedProvider([
      DeepRecoveryProviderPage(
        items: [record(deleted), record(orphan)],
        nextContinuationToken: 'page-2',
        filesExamined: 2,
        volumesScanned: const {'external_primary'},
      ),
      DeepRecoveryProviderPage(
        items: [record(orphan)],
        volumesScanned: const {'0123-4567'},
      ),
    ]);

    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
    );

    expect(result.completed, isTrue);
    expect(provider.calls, 2);
    expect(result.duplicateRecordsSuppressed, 1);
    expect(result.volumesScanned, {'external_primary', '0123-4567'});
    expect(result.byDisposition[DeepRecoveryDisposition.verifiedDeleted], [
      deleted,
    ]);
    expect(result.byDisposition[DeepRecoveryDisposition.unclassified], [
      orphan,
    ]);
  });

  test(
    'accessible SAF-style discovery always remains existing media',
    () async {
      final accessible = candidate(
        id: 'accessible',
        evidence: const [DeletionEvidenceReason.systemTrashRecord],
      );
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            DeepRecoveryProviderPage(
              items: [record(accessible, accessible: true)],
            ),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );
      expect(result.byDisposition[DeepRecoveryDisposition.existingMedia], [
        accessible,
      ]);
      expect(
        result.byDisposition[DeepRecoveryDisposition.verifiedDeleted],
        isNull,
      );
    },
  );

  test(
    'strong copy relation is separate and does not inflate deleted count',
    () async {
      final deleted = candidate(
        id: 'deleted',
        evidence: const [DeletionEvidenceReason.systemTrashRecord],
        capability: RestoreCapability.originalFullQuality,
        quality: RecoveryQuality.original,
      );
      final copy = candidate(
        id: 'copy',
        classification: RecoveryClassification.possibleCopy,
        capability: RestoreCapability.lowerResolutionCopy,
        quality: RecoveryQuality.reducedResolutionCopy,
        width: 320,
        height: 240,
      );
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            DeepRecoveryProviderPage(
              items: [
                record(deleted),
                DeepRecoveryDiscoveryRecord(
                  candidate: copy,
                  provider: DeepRecoveryProviderKind.thumbnailCache,
                  relatedDeletedCandidateId: deleted.id,
                  provenCopyType: PossibleCopyType.thumbnailSized,
                  relationshipEvidence:
                      PossibleCopyRelationshipEvidence.trustedPlatformMetadata,
                ),
              ],
            ),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );
      expect(result.possibleCopies.verifiedDeletedCount, 1);
      expect(result.possibleCopies.possibleCopyCount, 1);
      expect(result.byDisposition[DeepRecoveryDisposition.thumbnailCopy], [
        copy,
      ]);
    },
  );

  test('existing index blocks contradictory trash evidence', () async {
    final uri = Uri.parse('content://media/external/images/media/9');
    final value = candidate(
      id: 'same',
      uri: uri,
      evidence: const [DeletionEvidenceReason.systemTrashRecord],
    );
    final index = ExistingMediaIndex.build(
      records: [CurrentMediaRecord(mediaStoreId: 9, contentUri: uri)],
    );
    final result = await const DeepRecoveryEngine().scan(
      providers: [
        _PagedProvider([
          DeepRecoveryProviderPage(items: [record(value)]),
        ]),
      ],
      existingMediaIndex: index,
      source: MediaSource.cameraGallery,
    );
    expect(result.byDisposition[DeepRecoveryDisposition.existingMedia], [
      value,
    ]);
  });

  test('cancellation never reports partial discovery as complete', () async {
    final token = ScanCancellationToken()..cancel();
    final provider = _PagedProvider([
      DeepRecoveryProviderPage(items: [record(candidate(id: 'x'))]),
    ]);
    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
      cancellationToken: token,
    );
    expect(result.completed, isFalse);
    expect(result.byDisposition, isEmpty);
    expect(provider.calls, 0);
  });

  test('source isolation rejects cross-domain discoveries', () async {
    final messaging = candidate(
      id: 'message',
      source: MediaSource.messagingSharedMedia,
    );
    final result = await const DeepRecoveryEngine().scan(
      providers: [
        _PagedProvider([
          DeepRecoveryProviderPage(items: [record(messaging)]),
        ]),
      ],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
    );
    expect(result.recordsDiscovered, 0);
  });

  test(
    'unknown-source discoveries never leak into a source-specific scan',
    () async {
      final unknown = candidate(
        id: 'unknown-copy',
        source: MediaSource.unknown,
        classification: RecoveryClassification.possibleCopy,
        capability: RestoreCapability.alternateFullQualityCopy,
        quality: RecoveryQuality.completeCopy,
      );
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            DeepRecoveryProviderPage(items: [record(unknown)]),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );
      expect(result.recordsDiscovered, 0);
      expect(result.byDisposition, isEmpty);
      expect(unknown.source, MediaSource.unknown);
    },
  );

  test(
    'repeated continuation terminates and preserves discovered results',
    () async {
      final first = candidate(id: 'first-copy');
      final second = candidate(id: 'second-copy');
      final provider = _PagedProvider([
        DeepRecoveryProviderPage(
          items: [record(first)],
          nextContinuationToken: 'same-state',
        ),
        DeepRecoveryProviderPage(
          items: [record(second)],
          nextContinuationToken: 'same-state',
        ),
      ]);

      final result = await const DeepRecoveryEngine().scan(
        providers: [provider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.completed, isTrue);
      expect(provider.calls, 2);
      expect(result.repeatedCursorDetections, 1);
      expect(result.completionReason, 'repeatedCursor');
      expect(result.recordsDiscovered, 2);
    },
  );

  test('zero-record final page exhausts normally', () async {
    final provider = _PagedProvider([
      const DeepRecoveryProviderPage(
        items: [],
        providerExhausted: true,
        completionReason: 'exhausted',
      ),
    ]);

    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
    );

    expect(result.completed, isTrue);
    expect(provider.calls, 1);
    expect(result.recordsDiscovered, 0);
    expect(result.completionReason, 'exhausted');
  });

  test(
    'fast and thorough profiles use the same engine with distinct depth',
    () async {
      final fastProvider = _PagedProvider([
        const DeepRecoveryProviderPage(items: [], providerExhausted: true),
      ]);
      final thoroughProvider = _PagedProvider([
        const DeepRecoveryProviderPage(items: [], providerExhausted: true),
      ]);

      await const DeepRecoveryEngine().scan(
        providers: [fastProvider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.unknown,
        profile: PhotoRecoveryProfile.fastDeep,
      );
      await const DeepRecoveryEngine().scan(
        providers: [thoroughProvider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.unknown,
        profile: PhotoRecoveryProfile.thorough,
      );

      expect(fastProvider.profiles, [PhotoRecoveryProfile.fastDeep]);
      expect(thoroughProvider.profiles, [PhotoRecoveryProfile.thorough]);
    },
  );

  test('explicit provider exhaustion overrides a stray continuation', () async {
    final provider = _PagedProvider([
      const DeepRecoveryProviderPage(
        items: [],
        nextContinuationToken: 'must-not-be-requested',
        providerExhausted: true,
        completionReason: 'exhausted',
      ),
    ]);

    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
    );

    expect(result.completed, isTrue);
    expect(provider.calls, 1);
    expect(result.completionReason, 'exhausted');
  });

  test('unchanged no-progress continuation terminates', () async {
    final provider = _PagedProvider([
      const DeepRecoveryProviderPage(items: [], nextContinuationToken: 'same'),
      const DeepRecoveryProviderPage(items: [], nextContinuationToken: 'same'),
    ]);

    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: emptyIndex,
      source: MediaSource.cameraGallery,
    );

    expect(result.completed, isTrue);
    expect(provider.calls, 2);
    expect(result.completionReason, 'repeatedCursor');
  });
  test(
    'passes exact current-media identities only when a provider session starts',
    () async {
      final provider = _PagedProvider([
        const DeepRecoveryProviderPage(
          items: [],
          nextContinuationToken: 'next',
          entriesExamined: 200,
          currentFilesSkipped: 199,
          signatureCacheHits: 1,
          nativeTraversalMillis: 12,
        ),
        const DeepRecoveryProviderPage(
          items: [],
          providerExhausted: true,
          completionReason: 'exhausted',
          entriesExamined: 3,
          signatureCacheMisses: 2,
          nativeTraversalMillis: 18,
        ),
      ]);

      final result = await const DeepRecoveryEngine().scan(
        providers: [provider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
        currentMediaLocationKeys: const {
          'external_primary|dcim/camera|live.jpg|12',
        },
      );

      expect(provider.requests, hasLength(2));
      expect(provider.requests.first.currentMediaLocationKeys, hasLength(1));
      expect(provider.requests.last.currentMediaLocationKeys, isEmpty);
      expect(result.entriesExamined, 203);
      expect(result.currentFilesSkipped, 199);
      expect(result.signatureCacheHits, 1);
      expect(result.signatureCacheMisses, 2);
      expect(result.nativeTraversalMillis, 18);
    },
  );
}

MediaCandidate candidate({
  required String id,
  MediaSource source = MediaSource.cameraGallery,
  Uri? uri,
  RecoveryClassification classification = RecoveryClassification.unclassified,
  Iterable<DeletionEvidenceReason> evidence = const [],
  RestoreCapability capability = RestoreCapability.notRestorable,
  RecoveryQuality quality = RecoveryQuality.metadataOnly,
  int? width,
  int? height,
}) => MediaCandidate(
  id: id,
  source: source,
  contentUri: uri,
  classification: classification,
  deletionEvidence: DeletionEvidence(reasons: evidence),
  restoreCapability: capability,
  recoveryQuality: quality,
  width: width,
  height: height,
);

DeepRecoveryDiscoveryRecord record(
  MediaCandidate candidate, {
  bool accessible = false,
}) => DeepRecoveryDiscoveryRecord(
  candidate: candidate,
  provider: DeepRecoveryProviderKind.unindexedOrphan,
  isAccessibleCurrentMedia: accessible,
);

class _PagedProvider implements DeepRecoveryDiscoveryProvider {
  _PagedProvider(this.pages);
  final List<DeepRecoveryProviderPage> pages;
  int calls = 0;
  final List<PhotoRecoveryProfile> profiles = [];
  final List<DeepRecoveryProviderRequest> requests = [];

  @override
  DeepRecoveryProviderKind get kind => DeepRecoveryProviderKind.unindexedOrphan;

  @override
  Set<DeepStorageAccessCapability> get requiredCapabilities => const {
    DeepStorageAccessCapability.persistedSafTree,
  };

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) async {
    profiles.add(request.profile);
    requests.add(request);
    return pages[calls++];
  }
}
