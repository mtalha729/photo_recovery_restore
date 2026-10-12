import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/camera_gallery_recovery/camera_gallery_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/camera_gallery_recovery/camera_gallery_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/messaging_recovery/messaging_recovery_pipeline.dart';
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
    String volume = 'external_primary',
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
        storageVolumeName: volume,
      ),
    );
  }

  MediaCandidate candidate({
    required int id,
    MediaSource source = MediaSource.messagingSharedMedia,
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

  MessagingRecoveryPipeline pipelineFor(TrashDiscoveryResult result) {
    return MessagingRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery((_) async => result),
    );
  }

  Future<VerifiedSourceRecoverySuccess> recover(
    MessagingRecoveryPipeline pipeline, {
    ExistingMediaIndex? index,
  }) async {
    return await pipeline.recoverMessaging(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: index ?? emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;
  }

  test('verified deleted WhatsApp shared media is included', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                1,
                relativePath: 'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/',
                bucketName: 'WhatsApp Images',
              ),
            ],
          ),
        ),
      ),
    );

    expect(result.items, hasLength(1));
    expect(result.source, MediaSource.messagingSharedMedia);
  });

  test('verified deleted Telegram shared media is included', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                2,
                relativePath: 'Pictures/Telegram/Telegram Images/',
                bucketName: 'Telegram Images',
              ),
            ],
          ),
        ),
      ),
    );

    expect(result.items, hasLength(1));
  });

  test('existing Messaging image is excluded', () async {
    final item = trashItem(
      3,
      relativePath: 'Pictures/WhatsApp/',
      bucketName: 'WhatsApp Images',
    );
    final index = ExistingMediaIndex.build(
      records: [
        CurrentMediaRecord(
          mediaStoreId: 3,
          contentUri: item.metadata.contentUri,
        ),
      ],
    );
    final result = await recover(
      pipelineFor(TrashDiscoverySuccess(TrashDiscoveryPage(items: [item]))),
      index: index,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('filename alone is insufficient for Messaging source', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 4,
      displayName: 'WhatsApp Image 2026.jpg',
    );

    expect(resolver.resolve(metadata), MediaSource.unknown);
  });

  test('generic Pictures location is insufficient', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 5,
      relativePath: 'Pictures/',
      bucketName: 'Pictures',
    );

    expect(resolver.resolve(metadata), MediaSource.cameraGallery);
    expect(resolver.resolve(metadata), isNot(MediaSource.messagingSharedMedia));
  });

  test('private Android data path is not classified or accessed', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 6,
      relativePath: 'Android/data/com.whatsapp/files/WhatsApp Images/',
      bucketName: 'WhatsApp Images',
    );

    expect(resolver.resolve(metadata), MediaSource.unknown);
  });

  test('possible copy never enters Messaging verified results', () {
    final shared = VerifiedSourceRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
      ),
    );
    final result = shared.processCandidates(
      source: MediaSource.messagingSharedMedia,
      candidates: [
        candidate(id: 7, classification: RecoveryClassification.possibleCopy),
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
      source: MediaSource.messagingSharedMedia,
      candidates: [candidate(id: 8)],
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
  });

  test('definite existing match blocks contradictory deletion evidence', () {
    final item = candidate(
      id: 9,
      evidence: [DeletionEvidenceReason.systemTrashRecord],
    );
    final shared = VerifiedSourceRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
      ),
    );
    final result = shared.processCandidates(
      source: MediaSource.messagingSharedMedia,
      candidates: [item],
      existingMediaIndex: ExistingMediaIndex.build(
        records: [
          CurrentMediaRecord(mediaStoreId: 9, contentUri: item.contentUri),
        ],
      ),
      androidApiLevel: 35,
    );

    expect(result.items, isEmpty);
    expect(result.diagnostics.excludedExistingCount, 1);
  });

  test('ambiguous provider remains unknown', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 10,
      relativePath: 'Shared/',
      bucketName: 'Messages',
    );

    expect(resolver.resolve(metadata), MediaSource.unknown);
  });

  test('empty Messaging trash is valid success', () async {
    final result = await recover(
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
    final result = await pipeline.recoverMessaging(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect(
      (result as VerifiedSourceRecoveryFailure).code,
      VerifiedSourceRecoveryFailureCode.accessUnavailable,
    );
  });

  test('API 24 through 29 remains unsupported', () async {
    final pipeline = pipelineFor(
      const TrashDiscoveryUnsupported(androidApiLevel: 29),
    );
    final result = await pipeline.recoverMessaging(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 29,
    );

    expect(result, isA<VerifiedSourceRecoveryUnsupported>());
  });

  test('pagination does not lose or duplicate Messaging items', () async {
    final pages = {
      null: TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              11,
              relativePath: 'Pictures/WhatsApp/',
              bucketName: 'WhatsApp Images',
            ),
          ],
          nextAfterMediaStoreId: 11,
        ),
      ),
      11: TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              12,
              relativePath: 'Pictures/Telegram/',
              bucketName: 'Telegram Images',
            ),
          ],
        ),
      ),
    };
    final pipeline = MessagingRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (request) async => pages[request.afterMediaStoreId]!,
      ),
    );
    final first = await pipeline.recoverMessaging(
      request: const TrashDiscoveryPageRequest(pageSize: 1),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    ) as VerifiedSourceRecoverySuccess;
    final second = await pipeline.recoverMessaging(
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
    expect(ids, [11, 12]);
  });

  test('source and provider classification is deterministic', () {
    const resolver = MediaSourceResolver();
    const metadata = CurrentMediaMetadata(
      mediaStoreId: 13,
      relativePath: 'Android/media/org.telegram.messenger/Telegram Images/',
      bucketName: 'Telegram Images',
    );

    final first = resolver.resolveDetails(metadata);
    final second = resolver.resolveDetails(metadata);
    expect(first.source, MediaSource.messagingSharedMedia);
    expect(first.messagingProvider, MessagingProvider.telegram);
    expect(second.source, first.source);
    expect(second.messagingProvider, first.messagingProvider);
  });

  test('existing-media counts never inflate Messaging recovery', () async {
    final current = List.generate(
      1200,
      (id) => CurrentMediaRecord(
        mediaStoreId: id,
        contentUri: Uri.parse('content://media/external/images/media/$id'),
      ),
    );
    final deleted = List.generate(
      6,
      (index) => trashItem(
        20000 + index,
        relativePath: 'Pictures/WhatsApp/',
        bucketName: 'WhatsApp Images',
      ),
    );
    final result = await recover(
      pipelineFor(TrashDiscoverySuccess(TrashDiscoveryPage(items: deleted))),
      index: ExistingMediaIndex.build(records: current),
    );

    expect(result.items, hasLength(6));
    expect(result.diagnostics.examinedCount, 6);
  });

  test('verified Messaging items preserve restore eligibility', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                14,
                relativePath: 'Pictures/WhatsApp/',
                bucketName: 'WhatsApp Images',
              ),
            ],
          ),
        ),
      ),
    );

    expect(result.items.single.restoreEligibility.isEligible, isTrue);
  });

  test('Camera never appears in Messaging', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(15, relativePath: 'DCIM/Camera/', bucketName: 'Camera'),
            ],
          ),
        ),
      ),
    );
    expect(result.items, isEmpty);
  });

  test('Screenshot never appears in Messaging', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                16,
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

  test('Download never appears in Messaging', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(17, relativePath: 'Download/', bucketName: 'Download'),
            ],
          ),
        ),
      ),
    );
    expect(result.items, isEmpty);
  });

  test(
    'SD custom media without explicit identity never appears in Messaging',
    () async {
      final result = await recover(
        pipelineFor(
          TrashDiscoverySuccess(
            TrashDiscoveryPage(
              items: [
                trashItem(
                  18,
                  relativePath: 'Pictures/Shared/',
                  bucketName: 'Shared',
                  volume: '1234-5678',
                ),
              ],
            ),
          ),
        ),
      );
      expect(result.items, isEmpty);
    },
  );

  test('unknown media never appears in Messaging', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [trashItem(19, relativePath: null, bucketName: 'Unsorted')],
          ),
        ),
      ),
    );
    expect(result.items, isEmpty);
  });

  test('Messaging never appears in Camera Gallery', () async {
    final discovery = _FakeTrashDiscovery(
      (_) async => TrashDiscoverySuccess(
        TrashDiscoveryPage(
          items: [
            trashItem(
              20,
              relativePath: 'Pictures/WhatsApp/',
              bucketName: 'WhatsApp Images',
            ),
          ],
        ),
      ),
    );
    final result =
        await CameraGalleryRecoveryPipeline(trashDiscovery: discovery).getPage(
          request: const TrashDiscoveryPageRequest(pageSize: 20),
          existingMediaIndex: emptyIndex(),
          androidApiLevel: 35,
        );

    expect((result as CameraGalleryRecoverySuccess).items, isEmpty);
  });

  test('Messaging never appears in Screenshots', () async {
    final pipeline = ScreenshotsDownloadsRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                21,
                relativePath: 'Pictures/WhatsApp/',
                bucketName: 'WhatsApp Images',
              ),
            ],
          ),
        ),
      ),
    );
    final result = await pipeline.recoverScreenshots(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as VerifiedSourceRecoverySuccess).items, isEmpty);
  });

  test('Messaging never appears in Downloads', () async {
    final pipeline = ScreenshotsDownloadsRecoveryPipeline(
      trashDiscovery: _FakeTrashDiscovery(
        (_) async => TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                22,
                relativePath: 'Pictures/Telegram/',
                bucketName: 'Telegram Images',
              ),
            ],
          ),
        ),
      ),
    );
    final result = await pipeline.recoverDownloads(
      request: const TrashDiscoveryPageRequest(pageSize: 20),
      existingMediaIndex: emptyIndex(),
      androidApiLevel: 35,
    );

    expect((result as VerifiedSourceRecoverySuccess).items, isEmpty);
  });

  test('pipeline remains metadata-only and exposes no image payload', () async {
    final result = await recover(
      pipelineFor(
        TrashDiscoverySuccess(
          TrashDiscoveryPage(
            items: [
              trashItem(
                23,
                relativePath: 'Pictures/WhatsApp/',
                bucketName: 'WhatsApp Images',
              ),
            ],
          ),
        ),
      ),
    );

    final candidate = result.items.single.candidate;
    expect(candidate.contentUri?.scheme, 'content');
    expect(candidate.byteSize, 2048);
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
