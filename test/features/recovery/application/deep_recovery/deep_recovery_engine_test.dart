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
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
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
        providerExhausted: true,
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
    'Recovery Shield records never enter verified-deleted buckets',
    () async {
      final shieldBackup = candidate(
        id: 'shield-backup',
        evidence: const [DeletionEvidenceReason.systemTrashRecord],
        isRecoveryShieldBackup: true,
      );
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            DeepRecoveryProviderPage(items: [record(shieldBackup)]),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.byDisposition[DeepRecoveryDisposition.protectedCopy], [
        shieldBackup,
      ]);
      expect(
        result.byDisposition[DeepRecoveryDisposition.verifiedDeleted],
        isNull,
      );
      expect(result.possibleCopies.verifiedDeletedCount, 0);
    },
  );

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

  test('indexed thumbnail artifact survives while its ordinary original stays excluded', () async {
    final index = ExistingMediaIndex.build(
      records: [
        const CurrentMediaRecord(
          mediaStoreId: 20,
          storageVolumeName: 'external_primary',
          relativePath: 'DCIM/Camera/',
          displayName: 'photo.jpg',
          byteSize: 4096,
        ),
        const CurrentMediaRecord(
          mediaStoreId: 21,
          storageVolumeName: 'external_primary',
          relativePath: 'DCIM/.thumbnails/',
          displayName: 'thumb.jpg',
          byteSize: 1024,
        ),
      ],
    );
    final thumbnail = MediaCandidate(
      id: 'thumb',
      source: MediaSource.cameraGallery,
      filePath: '/storage/emulated/0/DCIM/.thumbnails/thumb.jpg',
      displayName: 'thumb.jpg',
      relativeLocation: 'DCIM/.thumbnails/',
      storageVolumeName: 'external_primary',
      byteSize: 1024,
      width: 256,
      height: 170,
      classification: RecoveryClassification.possibleCopy,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.lowerResolutionCopy,
      recoveryQuality: RecoveryQuality.reducedResolutionCopy,
      discoveryEvidence: const RecoveryDiscoveryEvidence(
        detectedFormat: 'jpeg',
        isThumbnailLike: true,
      ),
    );
    final original = MediaCandidate(
      id: 'original',
      source: MediaSource.cameraGallery,
      filePath: '/storage/emulated/0/DCIM/Camera/photo.jpg',
      displayName: 'photo.jpg',
      relativeLocation: 'DCIM/Camera/',
      storageVolumeName: 'external_primary',
      byteSize: 4096,
      classification: RecoveryClassification.possibleCopy,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.alternateFullQualityCopy,
      recoveryQuality: RecoveryQuality.completeCopy,
      discoveryEvidence: const RecoveryDiscoveryEvidence(
        detectedFormat: 'jpeg',
      ),
    );
    final provider = _PagedProvider([
      DeepRecoveryProviderPage(items: [record(original), record(thumbnail)]),
    ]);

    final result = await const DeepRecoveryEngine().scan(
      providers: [provider],
      existingMediaIndex: index,
      source: MediaSource.cameraGallery,
    );

    expect(result.byDisposition[DeepRecoveryDisposition.existingMedia], [
      original,
    ]);
    expect(result.byDisposition[DeepRecoveryDisposition.thumbnailCopy], [
      thumbnail,
    ]);
    expect(result.possibleCopies.possibleCopyCount, 0);
    expect(
      provider.requests.single.existingStorageLocationKeys,
      contains('external_primary|dcim/camera|photo.jpg|4096'),
    );
    expect(
      provider.requests.single.existingStorageLocationKeys,
      isNot(contains('external_primary|dcim/.thumbnails|thumb.jpg|1024')),
    );
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

      expect(result.completed, isFalse);
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

    expect(result.completed, isFalse);
    expect(provider.calls, 2);
    expect(result.completionReason, 'repeatedCursor');
  });
  test(
    'unreadable native entries produce an explicit partial outcome',
    () async {
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            const DeepRecoveryProviderPage(
              items: [],
              providerExhausted: true,
              completionReason: 'exhaustedWithUnreadableEntries',
              unavailableFiles: 2,
              unavailableDirectories: 3,
            ),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.completed, isFalse);
      expect(result.failureAvailability, DeepProviderAvailability.failed);
      expect(result.failureMessage, contains('coverage is partial'));
      expect(result.unavailableFiles, 2);
      expect(result.unavailableDirectories, 3);
      expect(result.completionReason, 'exhaustedWithUnreadableEntries');
    },
  );

  test(
    'native directory resource limit is reported as partial coverage',
    () async {
      final result = await const DeepRecoveryEngine().scan(
        providers: [
          _PagedProvider([
            const DeepRecoveryProviderPage(
              items: [],
              providerExhausted: true,
              completionReason: 'exhaustedWithResourceLimit',
            ),
          ]),
        ],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.completed, isFalse);
      expect(result.failureAvailability, DeepProviderAvailability.failed);
      expect(result.failureMessage, contains('resource limit'));
      expect(result.completionReason, 'exhaustedWithResourceLimit');
    },
  );

  test(
    'result retention limit cancels the provider and reports partial coverage',
    () async {
      final pages = <DeepRecoveryProviderPage>[];
      for (var page = 0; page < 51; page++) {
        final count = page < 50 ? 200 : 1;
        final records = List.generate(
          count,
          (index) => record(
            candidate(
              id: 'candidate-${page * 200 + index}',
              classification: RecoveryClassification.possibleCopy,
              capability: RestoreCapability.unknownQualityCopy,
              quality: RecoveryQuality.unknownQualityCopy,
              cacheArtifact: true,
            ),
          ),
        );
        pages.add(
          DeepRecoveryProviderPage(
            items: records,
            nextContinuationToken: page < 50 ? 'page-${page + 1}' : null,
          ),
        );
      }
      final provider = _CancellablePagedProvider(pages);

      final result = await const DeepRecoveryEngine().scan(
        providers: [provider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.completed, isFalse);
      expect(result.recordsDiscovered, 10000);
      expect(result.completionReason, 'resultMemoryLimit');
      expect(result.failureMessage, contains('in-memory result limit'));
      expect(provider.cancelled, isTrue);
    },
  );

  test(
    'generic copies cannot consume the reserved artifact capacity',
    () async {
      final pages = <DeepRecoveryProviderPage>[];
      for (var page = 0; page < 10; page++) {
        pages.add(
          DeepRecoveryProviderPage(
            items: List.generate(
              200,
              (index) => record(
                candidate(
                  id: 'generic-${page * 200 + index}',
                  classification: RecoveryClassification.possibleCopy,
                  capability: RestoreCapability.unknownQualityCopy,
                  quality: RecoveryQuality.unknownQualityCopy,
                ),
              ),
            ),
            nextContinuationToken: 'page-${page + 1}',
          ),
        );
      }
      pages.add(
        DeepRecoveryProviderPage(
          items: [
            record(
              candidate(
                id: 'generic-over-limit',
                classification: RecoveryClassification.possibleCopy,
                capability: RestoreCapability.unknownQualityCopy,
                quality: RecoveryQuality.unknownQualityCopy,
              ),
            ),
            record(
              candidate(
                id: 'late-cache-artifact',
                classification: RecoveryClassification.possibleCopy,
                capability: RestoreCapability.unknownQualityCopy,
                quality: RecoveryQuality.unknownQualityCopy,
                cacheArtifact: true,
              ),
            ),
          ],
          providerExhausted: true,
        ),
      );
      final provider = _PagedProvider(pages);

      final result = await const DeepRecoveryEngine().scan(
        providers: [provider],
        existingMediaIndex: emptyIndex,
        source: MediaSource.cameraGallery,
      );

      expect(result.recordsDiscovered, 2001);
      expect(result.lowerPriorityRecordsOmitted, 1);
      expect(result.completionReason, 'lowerPriorityRetentionLimit');
      expect(
        result.byDisposition[DeepRecoveryDisposition.possibleUnknownQualityCopy]
            ?.map((item) => item.id),
        contains('late-cache-artifact'),
      );
    },
  );

  test(
    'keeps current-media exclusion in Dart without a native key-set transfer',
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
      );

      expect(provider.requests, hasLength(2));
      expect(result.entriesExamined, 203);
      expect(result.currentFilesSkipped, 199);
      expect(result.signatureCacheHits, 1);
      expect(result.signatureCacheMisses, 2);
      expect(result.nativeTraversalMillis, 18);
    },
  );

  test(
    'reuses one immutable current-media key set across deep pages',
    () async {
      final index = ExistingMediaIndex.build(
        records: [
          for (var id = 1; id <= 1000; id++)
            CurrentMediaRecord(
              mediaStoreId: id,
              storageVolumeName: 'external_primary',
              relativePath: 'DCIM/Camera/',
              displayName: 'photo-$id.jpg',
              byteSize: id,
            ),
        ],
      );
      final provider = _PagedProvider([
        const DeepRecoveryProviderPage(
          items: [],
          nextContinuationToken: 'second',
        ),
        const DeepRecoveryProviderPage(items: [], providerExhausted: true),
      ]);

      await const DeepRecoveryEngine().scan(
        providers: [provider],
        existingMediaIndex: index,
        source: MediaSource.cameraGallery,
      );

      expect(provider.requests, hasLength(2));
      expect(
        provider.requests.first.existingStorageLocationKeys,
        hasLength(1000),
      );
      expect(
        identical(
          provider.requests.first.existingStorageLocationKeys,
          provider.requests.last.existingStorageLocationKeys,
        ),
        isTrue,
      );
    },
  );
}

MediaCandidate candidate({
  required String id,
  MediaSource source = MediaSource.cameraGallery,
  Uri? uri,
  RecoveryClassification classification = RecoveryClassification.unclassified,
  Iterable<DeletionEvidenceReason> evidence = const [],
  bool isRecoveryShieldBackup = false,
  RestoreCapability capability = RestoreCapability.notRestorable,
  RecoveryQuality quality = RecoveryQuality.metadataOnly,
  int? width,
  int? height,
  bool cacheArtifact = false,
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
  discoveryEvidence: RecoveryDiscoveryEvidence(
    isRecoveryShieldBackup: isRecoveryShieldBackup,
    isCacheLike: cacheArtifact,
  ),
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
    DeepStorageAccessCapability.mediaStore,
  };

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) async {
    profiles.add(request.profile);
    requests.add(request);
    return pages[calls++];
  }

  @override
  Future<void> cancelActiveScan() async {}
}

class _CancellablePagedProvider extends _PagedProvider {
  _CancellablePagedProvider(super.pages);
  bool cancelled = false;

  @override
  Future<void> cancelActiveScan() async {
    cancelled = true;
  }
}
