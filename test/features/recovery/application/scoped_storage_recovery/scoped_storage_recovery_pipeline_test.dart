import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/scoped_storage_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/scoped_storage_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
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
  final emptyIndex = ExistingMediaIndex.build(records: const []);
  const removableVolume = StorageVolumeIdentity(
    mediaStoreVolumeName: '1234-5678',
    isRemovable: true,
  );
  final scope = AuthorizedFolderScope(
    treeUri: Uri.parse(
      'content://com.android.externalstorage.documents/tree/1234-5678%3APictures',
    ),
    documentId: '1234-5678:Pictures',
    volume: removableVolume,
    relativePathPrefix: 'Pictures',
    grantState: FolderGrantState.active,
  );

  MediaCandidate candidate({
    String location = 'Pictures/Trips/',
    String volume = '1234-5678',
    bool removable = true,
    Uri? documentUri,
    Iterable<DeletionEvidenceReason> evidence = const [
      DeletionEvidenceReason.systemTrashRecord,
    ],
  }) => MediaCandidate(
    id: 'candidate',
    source: MediaSource.unknown,
    contentUri: Uri.parse('content://media/$volume/images/media/7'),
    mediaStoreId: 7,
    displayName: 'Pictures.jpg',
    relativeLocation: location,
    storageVolumeName: volume,
    isRemovableStorage: removable,
    documentUri: documentUri,
    classification: RecoveryClassification.unclassified,
    deletionEvidence: DeletionEvidence(reasons: evidence),
    restoreCapability: RestoreCapability.originalFullQuality,
    recoveryQuality: RecoveryQuality.original,
  );

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

  group('scope membership', () {
    const matcher = FolderScopeMatcher();

    test('matches strong volume and relative-path identity', () {
      expect(matcher.evaluate(candidate(), scope), ScopeMembership.inside);
    });

    test('rejects a candidate outside the selected relative path', () {
      expect(
        matcher.evaluate(candidate(location: 'DCIM/Camera/'), scope),
        ScopeMembership.outside,
      );
    });

    test('rejects a candidate on another volume', () {
      expect(
        matcher.evaluate(candidate(volume: 'external_primary'), scope),
        ScopeMembership.outside,
      );
    });

    test('missing strong identity is ambiguous, not inside', () {
      final weakScope = AuthorizedFolderScope(
        treeUri: scope.treeUri,
        grantState: FolderGrantState.active,
      );
      expect(
        matcher.evaluate(candidate(location: ''), weakScope),
        ScopeMembership.ambiguous,
      );
    });

    test('exact descendant document URI is inside', () {
      final value = candidate(
        documentUri: Uri.parse(
          'content://com.android.externalstorage.documents/document/1234-5678%3APictures%2FTrips%2Fa.jpg',
        ),
      );
      expect(matcher.evaluate(value, scope), ScopeMembership.inside);
    });

    test('same-provider non-descendant document URI is outside', () {
      final value = candidate(
        documentUri: Uri.parse(
          'content://com.android.externalstorage.documents/document/1234-5678%3ADCIM%2Fa.jpg',
        ),
      );
      expect(matcher.evaluate(value, scope), ScopeMembership.outside);
    });

    test('filename resemblance is never scope evidence', () {
      final weakScope = AuthorizedFolderScope(
        treeUri: scope.treeUri,
        grantState: FolderGrantState.active,
      );
      final value = candidate(location: '');
      expect(matcher.evaluate(value, weakScope), ScopeMembership.ambiguous);
    });

    test('lost grant makes membership ambiguous', () {
      final lost = AuthorizedFolderScope(
        treeUri: scope.treeUri,
        volume: removableVolume,
        relativePathPrefix: 'Pictures',
        grantState: FolderGrantState.permissionGrantLost,
      );
      expect(matcher.evaluate(candidate(), lost), ScopeMembership.ambiguous);
    });
  });

  group('scoped recovery', () {
    test('requires folder selection when no scope exists', () async {
      final result =
          await pipeline(
            const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
          ).getSelectedFolderPage(
            scope: null,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );
      expect(
        result.capability,
        ScopedRecoveryCapability.folderSelectionRequired,
      );
    });

    test('reports a lost persisted grant', () async {
      final lost = AuthorizedFolderScope(
        treeUri: scope.treeUri,
        grantState: FolderGrantState.permissionGrantLost,
      );
      final result =
          await pipeline(
            const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
          ).getSelectedFolderPage(
            scope: lost,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );
      expect(result.capability, ScopedRecoveryCapability.permissionGrantLost);
    });

    test('unsupported mapping does not broaden the selected scope', () async {
      final weakScope = AuthorizedFolderScope(
        treeUri: scope.treeUri,
        grantState: FolderGrantState.active,
      );
      final result =
          await pipeline(
            const TrashDiscoverySuccess(TrashDiscoveryPage.empty()),
          ).getSelectedFolderPage(
            scope: weakScope,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );
      expect(
        result.capability,
        ScopedRecoveryCapability.unsupportedDeletedDiscoveryForScope,
      );
    });

    test('verified in-scope trash is a custom-folder result', () async {
      final result =
          await pipeline(
            TrashDiscoverySuccess(TrashDiscoveryPage(items: [trashItem()])),
          ).getSelectedFolderPage(
            scope: scope,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );
      expect(
        result.capability,
        ScopedRecoveryCapability.verifiedRecoveryAvailable,
      );
      expect(result.items.single.candidate.source, MediaSource.customFolder);
      expect(
        result.items.single.classificationDecision.classification,
        RecoveryClassification.verifiedDeleted,
      );
    });

    test('out-of-scope verified trash is a valid empty result', () async {
      final result =
          await pipeline(
            TrashDiscoverySuccess(
              TrashDiscoveryPage(items: [trashItem(path: 'DCIM/Camera/')]),
            ),
          ).getSelectedFolderPage(
            scope: scope,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: emptyIndex,
            androidApiLevel: 35,
          );
      expect(result.capability, ScopedRecoveryCapability.validEmptyResult);
      expect(result.items, isEmpty);
    });

    test('an existing in-scope item remains excluded', () async {
      final item = trashItem();
      final index = ExistingMediaIndex.build(
        records: [
          CurrentMediaRecord(
            mediaStoreId: 7,
            contentUri: item.metadata.contentUri,
          ),
        ],
      );
      final result =
          await pipeline(
            TrashDiscoverySuccess(TrashDiscoveryPage(items: [item])),
          ).getSelectedFolderPage(
            scope: scope,
            request: const TrashDiscoveryPageRequest(pageSize: 10),
            existingMediaIndex: index,
            androidApiLevel: 35,
          );
      expect(result.capability, ScopedRecoveryCapability.validEmptyResult);
    });

    test('absence from current inventory alone proves no deletion', () {
      final result =
          pipeline(const TrashDiscoverySuccess(TrashDiscoveryPage.empty()))
              .processSelectedFolderCandidates(
                scope: scope,
                candidates: [candidate(evidence: const [])],
                existingMediaIndex: emptyIndex,
                androidApiLevel: 35,
              );
      expect(result.capability, ScopedRecoveryCapability.validEmptyResult);
      expect(result.items, isEmpty);
    });

    test('SD recovery requires explicit removable-volume metadata', () async {
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
      expect(
        result.capability,
        ScopedRecoveryCapability.scopeAccessUnavailable,
      );
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
