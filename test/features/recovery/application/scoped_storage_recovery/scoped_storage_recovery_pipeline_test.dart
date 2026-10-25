import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/scoped_storage_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/scoped_storage_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/current_media_metadata.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';

void main() {
  final emptyIndex = ExistingMediaIndex.build(records: const []);

  VerifiedTrashItem trashItem({
    int id = 7,
    String path = 'Pictures/Trips/',
    String volume = '1234-5678',
    bool removable = true,
  }) => VerifiedTrashItem.fromPlatformTrash(
    metadata: CurrentMediaMetadata(
      mediaStoreId: id,
      contentUri: Uri.parse('content://media/$volume/images/media/$id'),
      relativePath: path,
      storageVolumeName: volume,
      isRemovableStorage: removable,
    ),
  );

  ScopedStorageRecoveryPipeline pipeline(TrashDiscoveryResult result) =>
      ScopedStorageRecoveryPipeline(
        sourcePipeline: VerifiedSourceRecoveryPipeline(
          trashDiscovery: _FakeTrashDiscovery(result),
        ),
      );

  group('SD-card recovery', () {
    test('requires explicit removable-volume metadata', () async {
      final result =
          await pipeline(
            TrashDiscoverySuccess(
              TrashDiscoveryPage(
                items: [trashItem(removable: false), trashItem(id: 8)],
              ),
            ),
          ).getSdCardPage(
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );

      expect(result.items, hasLength(1));
      expect(result.items.single.candidate.mediaStoreId, 8);
    });

    test('empty removable-volume result is valid, not inaccessible', () async {
      final result =
          await pipeline(
            const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
          ).getSdCardPage(
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );

      expect(result.capability, ScopedRecoveryCapability.validEmptyResult);
    });

    test('pagination continuation is preserved', () async {
      final result =
          await pipeline(
            TrashDiscoverySuccess(
              TrashDiscoveryPage(
                items: [trashItem()],
                nextAfterMediaStoreId: 7,
              ),
            ),
          ).getSdCardPage(
            request: const TrashDiscoveryPageRequest(pageSize: 1),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );

      expect(result.nextAfterMediaStoreId, 7);
      expect(result.mayHaveMore, isTrue);
    });

    test('access failure is structured', () async {
      final result =
          await pipeline(
            const TrashDiscoveryFailureResult(
              TrashDiscoveryFailure(
                code: TrashDiscoveryFailureCode.securityDenied,
              ),
            ),
          ).getSdCardPage(
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );

      expect(result.capability, ScopedRecoveryCapability.scopeAccessUnavailable);
    });

    test('unsupported Android trash discovery is explicit', () async {
      final result =
          await pipeline(const TrashDiscoveryUnsupported(androidApiLevel: 29))
              .getSdCardPage(
                request: const TrashDiscoveryPageRequest(pageSize: 10),
                existingMediaIndex: emptyIndex,
                androidApiLevel: 29,
              );

      expect(
        result.capability,
        ScopedRecoveryCapability.unsupportedPlatformCapability,
      );
    });
  });
}

class _FakeTrashDiscovery implements TrashDiscovery {
  const _FakeTrashDiscovery(this.result);
  final TrashDiscoveryResult result;

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) async => result;
}
