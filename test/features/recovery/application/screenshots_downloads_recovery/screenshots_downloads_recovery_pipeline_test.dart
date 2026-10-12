import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/screenshots_downloads_recovery/screenshots_downloads_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
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
    required String? relativePath,
    required String? bucketName,
    String displayName = 'image.jpg',
  }) {
    return VerifiedTrashItem.fromPlatformTrash(
      metadata: CurrentMediaMetadata(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
        displayName: displayName,
        mimeType: 'image/jpeg',
        byteSize: 2048,
        width: 1080,
        height: 1920,
        relativePath: relativePath,
        bucketName: bucketName,
        storageVolumeName: 'external_primary',
      ),
    );
  }

  MediaCandidate candidate({
    required int id,
    required MediaSource source,
    RecoveryClassification classification = RecoveryClassification.unclassified,
    Iterable<DeletionEvidenceReason> evidence = const [],
  }) {
    return MediaCandidate(
      id: 'candidate-$id',
      source: source,
      contentUri: Uri.parse('content://media/external/images/media/$id'),
      mediaStoreId: id,
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

  ScreenshotsDownloadsRecoveryPipeline pipelineFor(
    TrashDiscoveryResult result,
  ) {
    return ScreenshotsDownloadsRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery((_) async => result),
    );
  }

  Future<VerifiedSourceRecoverySuccess> screenshots(
    ScreenshotsDownloadsRecoveryPipeline pipeline, {
    ExistingMediaIndex? index,
  }) async {
    return await pipeline.recoverScreenshots(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: index ?? emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;
  }

  Future<VerifiedSourceRecoverySuccess> downloads(
    ScreenshotsDownloadsRecoveryPipeline pipeline, {
    ExistingMediaIndex? index,
  }) async {
    return await pipeline.recoverDownloads(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: index ?? emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;
  }

  test(
    'verified Pictures Screenshots item appears in Screenshot recovery',
    () async {
      final result = await screenshots(
        pipelineFor(
          TrashDiscoverySuccess(
            TrashDiscoveryPage(
              items: [
                trashItem(
                  1,
                  relativePath: 'Pictures/Screenshots/',
                  bucketName: 'Screenshots',
                ),
              ],
            ),
          ),
        ),
      );

      expect(result.items, hasLength(1));
      expect(result.source, MediaSource.screenshots);
    },
  );

  test('current screenshot is excluded', () async {
    final item = trashItem(
      2,
      relativePath: 'Pictures/Screenshots/',
      bucketName: 'Screenshots',
    );
    final index = ExistingMediaIndex.build(
      records: [
        CurrentMediaRecord(
          mediaStoreId: 2,
          contentUri: item.metadata.contentUri,
        ),
      ],
    );
    final result = await screenshots(
      pipelineFor(TrashDiscoverySuccess(TrashDiscoveryPage(items: [item]))),
      index: index,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('Camera item is not classified as Screenshot', () async {
    final result = await screenshots(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(3, relativePath: 'DCIM/Camera/', bucketName: 'Camera'),
            ],
          ),
        ),
      ),
    );

    expect(result.items, isEmpty);
  });

  test('Download item is not classified as Screenshot', () async {
    final result = await screenshots(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(4, relativePath: 'Download/', bucketName: 'Download'),
            ],
          ),
        ),
      ),
    );

    expect(result.items, isEmpty);
  });

  test('verified Download item appears in Download recovery', () async {
    final result = await downloads(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(5, relativePath: 'Downloads/', bucketName: 'Downloads'),
            ],
          ),
        ),
      ),
    );

    expect(result.items, hasLength(1));
    expect(result.source, MediaSource.downloadsSavedMedia);
  });

  test('current Download item is excluded', () async {
    final item = trashItem(
      6,
      relativePath: 'Download/',
      bucketName: 'Download',
    );
    final index = ExistingMediaIndex.build(
      records: [
        CurrentMediaRecord(
          mediaStoreId: 6,
          contentUri: item.metadata.contentUri,
        ),
      ],
    );
    final result = await downloads(
      pipelineFor(TrashDiscoverySuccess(TrashDiscoveryPage(items: [item]))),
      index: index,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('Screenshot is not returned by Download recovery', () async {
    final result = await downloads(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                7,
                relativePath: 'Pictures/Screenshots/',
                bucketName: 'Screenshots',
              ),
            ],
          ),
        ),
      ),
    );

    expect(result.items, isEmpty);
  });

  test('Camera item is not returned by Download recovery', () async {
    final result = await downloads(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(8, relativePath: 'DCIM/Camera/', bucketName: 'Camera'),
            ],
          ),
        ),
      ),
    );

    expect(result.items, isEmpty);
  });

  test('messaging media remains excluded from both pipelines', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              9,
              relativePath: 'Pictures/WhatsApp/',
              bucketName: 'WhatsApp Images',
            ),
          ],
        ),
      ),
    );

    expect((await screenshots(pipeline)).items, isEmpty);
    expect((await downloads(pipeline)).items, isEmpty);
  });

  test('unknown-source item is not guessed', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [trashItem(10, relativePath: null, bucketName: 'Unsorted')],
        ),
      ),
    );

    expect((await screenshots(pipeline)).items, isEmpty);
    expect((await downloads(pipeline)).items, isEmpty);
  });

  test('screenshot filename alone is insufficient', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 11,
      displayName: 'Screenshot_2026.png',
    );

    expect(resolver.resolve(metadata), MediaSource.unknown);
  });

  test('download filename alone is insufficient', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 12,
      displayName: 'downloaded_photo.jpg',
    );

    expect(resolver.resolve(metadata), MediaSource.unknown);
  });

  test('possible copy never enters Screenshot verified results', () {
    final shared = VerifiedSourceRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
      ),
    );
    final result = shared.processCandidates(
      source: MediaSource.screenshots,
      candidates: [
        candidate(
          id: 13,
          source: MediaSource.screenshots,
          classification: RecoveryClassification.possibleCopy,
        ),
      ],
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
  });

  test('no existing match alone never proves deletion', () {
    final shared = VerifiedSourceRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
      ),
    );
    final result = shared.processCandidates(
      source: MediaSource.downloadsSavedMedia,
      candidates: [candidate(id: 14, source: MediaSource.downloadsSavedMedia)],
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
  });

  test(
    'definite existing match wins over contradictory deletion evidence',
    () async {
      final item = trashItem(
        15,
        relativePath: 'Pictures/Screenshots/',
        bucketName: 'Screenshots',
      );
      final index = ExistingMediaIndex.build(
        records: [
          CurrentMediaRecord(
            mediaStoreId: 15,
            contentUri: item.metadata.contentUri,
          ),
        ],
      );
      final result = await screenshots(
        pipelineFor(TrashDiscoverySuccess(TrashDiscoveryPage(items: [item]))),
        index: index,
      );

      expect(result.items, isEmpty);
      expect(result.diagnostics.excludedExistingCount, 1);
    },
  );

  test('API 24 through 29 capability remains unsupported', () async {
    final pipeline = pipelineFor(
      const TrashDiscoveryUnsupported(androidApiLevel: 29),
    );
    final result = await pipeline.recoverScreenshots(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 29,
    );

    expect(result, isA<VerifiedSourceRecoveryUnsupported>());
  });

  test('empty source result is valid success', () async {
    final result = await downloads(
      pipelineFor(const TrashDiscoverySuccess(TrashDiscoveryPage.empty())),
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.examinedCount, 0);
  });

  test('access failure remains structured', () async {
    final pipeline = pipelineFor(
      const TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(code: TrashDiscoveryFailureCode.securityDenied),
      ),
    );
    final result = await pipeline.recoverDownloads(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(
      (result as VerifiedSourceRecoveryFailure).code,
      VerifiedSourceRecoveryFailureCode.accessUnavailable,
    );
  });

  test('pagination does not lose or duplicate Screenshot items', () async {
    final pages = {
      null: TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              16,
              relativePath: 'Pictures/Screenshots/',
              bucketName: 'Screenshots',
            ),
          ],
          nextAfterMediaStoreId: 16,
        ),
      ),
      16: TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              17,
              relativePath: 'Pictures/Screenshots/',
              bucketName: 'Screenshots',
            ),
          ],
        ),
      ),
    };
    final pipeline = ScreenshotsDownloadsRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (request) async => pages[request.afterMediaStoreId]!,
      ),
    );
    final first = await pipeline.recoverScreenshots(
      request: const TrashDiscoveryPageRequest(pageSize: 1),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;
    final second = await pipeline.recoverScreenshots(
      request: TrashDiscoveryPageRequest(
        pageSize: 1,
        afterMediaStoreId: first.nextAfterMediaStoreId,
      ),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;

    final ids = [
      ...first.items,
      ...second.items,
    ].map((item) => item.candidate.mediaStoreId).toList();
    expect(ids, [16, 17]);
  });

  test('source resolution is deterministic and mutually exclusive', () {
    const resolver = MediaSourceResolver();
    const screenshot = CurrentMediaMetadata(
      mediaStoreId: 18,
      relativePath: 'DCIM/Screenshots/',
      bucketName: 'Download',
    );
    const download = CurrentMediaMetadata(
      mediaStoreId: 19,
      relativePath: 'Download/',
      bucketName: 'Camera',
    );

    expect(resolver.resolve(screenshot), MediaSource.screenshots);
    expect(resolver.resolve(screenshot), MediaSource.screenshots);
    expect(resolver.resolve(download), MediaSource.downloadsSavedMedia);
  });

  test('current-media counts never inflate source recovery counts', () async {
    final current = List.generate(
      3500,
      (id) => CurrentMediaRecord(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
      ),
    );
    final deletedScreenshots = List.generate(
      7,
      (index) => trashItem(
        10000 + index,
        relativePath: 'Pictures/Screenshots/',
        bucketName: 'Screenshots',
      ),
    );
    final deletedDownloads = List.generate(
      5,
      (index) => trashItem(
        20000 + index,
        relativePath: 'Download/',
        bucketName: 'Download',
      ),
    );
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(items: [...deletedScreenshots, ...deletedDownloads]),
      ),
    );
    final index = ExistingMediaIndex.build(records: current);

    expect((await screenshots(pipeline, index: index)).items, hasLength(7));
    expect((await downloads(pipeline, index: index)).items, hasLength(5));
  });

  test('returned verified items preserve restore eligibility', () async {
    final pipeline = pipelineFor(
      TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              21,
              relativePath: 'Pictures/Screenshots/',
              bucketName: 'Screenshots',
            ),
            trashItem(22, relativePath: 'Download/', bucketName: 'Download'),
          ],
        ),
      ),
    );

    final screenshotResult = await screenshots(pipeline);
    final downloadResult = await downloads(pipeline);
    expect(screenshotResult.items.single.restoreEligibility.isEligible, isTrue);
    expect(downloadResult.items.single.restoreEligibility.isEligible, isTrue);
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
