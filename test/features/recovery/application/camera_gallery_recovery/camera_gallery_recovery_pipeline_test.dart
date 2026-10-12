import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/camera_gallery_recovery/camera_gallery_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/camera_gallery_recovery/camera_gallery_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_resolution/media_source_resolver.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/current_media_metadata.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  ExistingMediaIndex emptyIndex() =>
      ExistingMediaIndex.build(records: const []);

  VerifiedTrashItem trashItem(
    int id, {
    String? relativePath = 'DCIM/Camera/',
    String? bucketName = 'Camera',
  }) {
    return VerifiedTrashItem.fromPlatformTrash(
      metadata: CurrentMediaMetadata(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
        displayName: 'photo-$id.jpg',
        mimeType: 'image/jpeg',
        byteSize: 4096,
        width: 1200,
        height: 800,
        relativePath: relativePath,
        bucketName: bucketName,
        storageVolumeName: 'external_primary',
      ),
    );
  }

  MediaCandidate candidate({
    required int id,
    MediaSource source = MediaSource.cameraGallery,
    RecoveryClassification classification = RecoveryClassification.unclassified,
    Iterable<DeletionEvidenceReason> evidence = const [],
    Uri? contentUri,
  }) {
    return MediaCandidate(
      id: 'candidate-$id',
      source: source,
      contentUri:
          contentUri ?? Uri.parse('content://media/external/images/media/$id'),
      mediaStoreId: id,
      displayName: 'photo-$id.jpg',
      mimeType: 'image/jpeg',
      relativeLocation: 'DCIM/Camera/',
      bucketName: 'Camera',
      storageVolumeName: 'external_primary',
      byteSize: 4096,
      width: 1200,
      height: 800,
      classification: classification,
      deletionEvidence: DeletionEvidence(reasons: evidence),
      restoreCapability: classification == RecoveryClassification.possibleCopy
          ? RestoreCapability.lowerResolutionCopy
          : RestoreCapability.originalFullQuality,
      recoveryQuality: classification == RecoveryClassification.possibleCopy
          ? RecoveryQuality.reducedResolutionCopy
          : RecoveryQuality.original,
    );
  }

  CameraGalleryRecoveryPipeline pipelineFor(TrashDiscoveryResult result) {
    return CameraGalleryRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery((_) async => result),
    );
  }

  test('verified deleted DCIM Camera item is included', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(TrashDiscoveryPage(items: [trashItem(1)])),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    final success = result as CameraGalleryRecoverySuccess;
    expect(success.items, hasLength(1));
    expect(
      success.items.single.classificationDecision.classification,
      RecoveryClassification.verifiedDeleted,
    );
  });

  test('current Camera photo is excluded', () async {
    final item = trashItem(2);
    final index = ExistingMediaIndex.build(
      records: [
        CurrentMediaRecord(
          mediaStoreId: 2,
          contentUri: item.metadata.contentUri,
        ),
      ],
    );
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(TrashDiscoveryPage(items: [item])),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: index,
      androidApiLevel: 35,
    );

    final success = result as CameraGalleryRecoverySuccess;
    expect(success.items, isEmpty);
    expect(success.diagnostics.excludedExistingCount, 1);
  });

  test('verified deleted Screenshot is filtered out', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [trashItem(3, relativePath: 'Pictures/Screenshots/')],
        ),
      ),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as CameraGalleryRecoverySuccess).items, isEmpty);
  });

  test('verified deleted Download image is filtered out', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(items: [trashItem(4, relativePath: 'Download/')]),
      ),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as CameraGalleryRecoverySuccess).items, isEmpty);
  });

  test('clearly identified messaging image is filtered out', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [trashItem(5, relativePath: 'Pictures/Telegram/')],
        ),
      ),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as CameraGalleryRecoverySuccess).items, isEmpty);
  });

  test('unknown source is not guessed as Camera Gallery', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [trashItem(6, relativePath: null, bucketName: 'Unsorted')],
        ),
      ),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    final success = result as CameraGalleryRecoverySuccess;
    expect(success.items, isEmpty);
    expect(success.diagnostics.filteredOtherSourceCount, 1);
  });

  test('possible copy is not returned as verified deleted', () {
    final pipeline = pipelineFor(
      const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
    );

    final result = pipeline.processCandidates(
      candidates: [
        candidate(id: 7, classification: RecoveryClassification.possibleCopy),
      ],
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.filteredIneligibleCount, 1);
  });

  test('no existing match alone does not create a deleted result', () {
    final pipeline = pipelineFor(
      const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
    );

    final result = pipeline.processCandidates(
      candidates: [candidate(id: 8)],
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
  });

  test('definite existing match overrides contradictory trash evidence', () {
    final recoveryCandidate = candidate(
      id: 9,
      evidence: [DeletionEvidenceReason.systemTrashRecord],
    );
    final index = ExistingMediaIndex.build(
      records: [
        CurrentMediaRecord(
          mediaStoreId: 9,
          contentUri: recoveryCandidate.contentUri,
        ),
      ],
    );
    final pipeline = pipelineFor(
      const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
    );

    final result = pipeline.processCandidates(
      candidates: [recoveryCandidate],
      existingMediaIndex: index,
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('valid Camera Gallery item retains restore eligibility', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(TrashDiscoveryPage(items: [trashItem(10)])),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    final item = (result as CameraGalleryRecoverySuccess).items.single;
    expect(item.restoreEligibility.isEligible, isTrue);
    expect(
      item.restoreEligibility.reason,
      SystemTrashRestoreEligibilityReason.eligible,
    );
  });

  test(
    'scan only annotates restore eligibility and performs no restore',
    () async {
      var discoveryCalls = 0;
      final pipeline = CameraGalleryRecoveryPipeline(
        trashDiscovery: _FakeTrashDiscovery((_) async {
          discoveryCalls++;
          return TrashDiscoverySuccess(
            TrashDiscoveryPage(items: [trashItem(11)]),
          );
        }),
      );

      final result = await pipeline.getPage(
        request: const TrashDiscoveryPageRequest(pageSize: 20),
        existingMediaIndex: emptyIndex(),
        androidApiLevel: 35,
      );

      expect(discoveryCalls, 1);
      expect(result, isA<CameraGalleryRecoverySuccess>());
    },
  );

  test('API 24 through 29 reports system-trash recovery unsupported', () async {
    final pipeline = pipelineFor(
      const TrashDiscoveryUnsupported(androidApiLevel: 29),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 29,
    );

    expect(result, isA<CameraGalleryRecoveryUnsupported>());
  });

  test('empty Camera Gallery trash is a valid empty success', () async {
    final pipeline = pipelineFor(
      const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as CameraGalleryRecoverySuccess).items, isEmpty);
    expect(result.diagnostics.examinedCount, 0);
  });

  test('permission failure remains structured', () async {
    final pipeline = pipelineFor(
      const TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(code: TrashDiscoveryFailureCode.securityDenied),
      ),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(
      (result as CameraGalleryRecoveryFailure).code,
      CameraGalleryRecoveryFailureCode.accessUnavailable,
    );
  });

  test('pagination preserves items without duplication or loss', () async {
    final pages = {
      null: TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [trashItem(12), trashItem(13)],
          nextAfterMediaStoreId: 13,
        ),
      ),
      13: TrashDiscoverySuccess(TrashDiscoveryPage(items: [trashItem(14)])),
    };
    final pipeline = CameraGalleryRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (request) async => pages[request.afterMediaStoreId]!,
      ),
    );

    final first = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 2),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    ) as CameraGalleryRecoverySuccess;
    final second = await pipeline.getPage(
      request: TrashDiscoveryPageRequest(
        pageSize: 2,
        afterMediaStoreId: first.nextAfterMediaStoreId,
      ),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    ) as CameraGalleryRecoverySuccess;

    final ids = [
      ...first.items,
      ...second.items,
    ].map((item) => item.candidate.mediaStoreId).toList();
    expect(ids, [12, 13, 14]);
    expect(ids.toSet(), hasLength(3));
  });

  test('source resolution is deterministic with locked-source precedence', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 1,
      relativePath: 'DCIM/Screenshots/',
      bucketName: 'Camera',
    );

    expect(resolver.resolve(metadata), MediaSource.screenshots);
    expect(resolver.resolve(metadata), MediaSource.screenshots);
  });

  test('non-primary storage is not guessed as Camera Gallery', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 2,
      relativePath: 'DCIM/Camera/',
      bucketName: 'Camera',
      storageVolumeName: '1234-5678',
      isRemovableStorage: true,
    );

    expect(resolver.resolve(metadata), MediaSource.sdCard);
  });

  test('large indexed inventory remains compatible with exclusion', () {
    final records = List.generate(
      10000,
      (id) => CurrentMediaRecord(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
      ),
    );
    final pipeline = pipelineFor(
      const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
    );
    final matchingCandidate = candidate(
      id: 9999,
      evidence: [DeletionEvidenceReason.systemTrashRecord],
    );

    final result = pipeline.processCandidates(
      candidates: [matchingCandidate],
      existingMediaIndex: ExistingMediaIndex.build(records: records),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('current-media volume never inflates deleted result count', () async {
    final currentRecords = List.generate(
      12000,
      (id) => CurrentMediaRecord(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
      ),
    );
    final deletedItems = List.generate(8, (index) => trashItem(20000 + index));
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(TrashDiscoveryPage(items: deletedItems)),
    );

    final result = await pipeline.getPage(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: ExistingMediaIndex.build(records: currentRecords),
      androidApiLevel: 35,
    );

    final success = result as CameraGalleryRecoverySuccess;
    expect(success.items, hasLength(8));
    expect(success.diagnostics.examinedCount, 8);
  });
}

class _FakeTrashDiscovery implements TrashDiscovery {
  const _FakeTrashDiscovery(this.handler);

  final Future<TrashDiscoveryResult> Function(TrashDiscoveryPageRequest)
  handler;

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) {
    return handler(request);
  }
}
