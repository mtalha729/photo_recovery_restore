import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/media_access/media_access.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/authorized_folder_media_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/folder_scope_selector.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/authorized_folder_scan_models.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/production_recovery_scan_page_source.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_models.dart';

void main() {
  test('SAF discovery excludes exact and ambiguous current-media matches', () async {
    final currentRecords = [
      const CurrentMediaRecord(
        mediaStoreId: 101,
        contentUri: null,
        displayName: 'current.jpg',
        mimeType: 'image/jpeg',
        storageVolumeName: 'external_primary',
        byteSize: 1000,
        relativePath: 'Pictures/Album/',
      ),
      const CurrentMediaRecord(
        mediaStoreId: 102,
        contentUri: null,
        displayName: 'ambiguous.jpg',
        mimeType: 'image/jpeg',
        storageVolumeName: 'external_primary',
        byteSize: 200,
        relativePath: 'Pictures/Elsewhere/',
      ),
    ];
    final discovered = [
      _record('current.jpg', size: 1000),
      _record('ambiguous.jpg', size: 201),
      _record('new-copy.jpg', size: 300),
    ];
    final selector = _FolderSelector(
      AuthorizedFolderScope(
        treeUri: Uri.parse(
          'content://com.android.externalstorage.documents/tree/primary%3APictures%2FAlbum',
        ),
        documentId: 'primary:Pictures/Album',
        relativePathPrefix: 'Pictures/Album',
        volume: const StorageVolumeIdentity(
          mediaStoreVolumeName: 'external_primary',
          isRemovable: false,
        ),
        grantState: FolderGrantState.active,
      ),
    );
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: _AccessCoordinator(),
      inventory: _Inventory(currentRecords),
      trashDiscovery: _TrashDiscovery(),
      folderScopeSelector: selector,
      authorizedFolderDiscovery: _FolderDiscovery(discovered),
    );
    source.beginScanSession();
    final streamed = <MediaCandidate>[];

    final outcome = await source.scanAuthorizedFolder(
      source: RecoveryScanSource.allPhotos,
      onProgress: (progress) => streamed.addAll(progress.pageCandidates),
    );

    expect(outcome.status, AuthorizedFolderScanStatus.completed);
    expect(outcome.candidatesFound, 1);
    expect(streamed, hasLength(1));
    expect(streamed.single.displayName, 'new-copy.jpg');
    expect(streamed.single.classification, RecoveryClassification.possibleCopy);
    expect(streamed.single.deletionEvidence.reasons, isEmpty);
  });

  test('SAF scanning is not gated on broad photo-library access', () async {
    final inventory = _Inventory(const []);
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: const _AccessCoordinator(
        status: MediaAccessStatus.denied,
      ),
      inventory: inventory,
      trashDiscovery: _TrashDiscovery(),
      folderScopeSelector: _FolderSelector(
        AuthorizedFolderScope(
          treeUri: Uri.parse('content://provider/tree/root'),
          documentId: 'root',
          grantState: FolderGrantState.active,
        ),
      ),
      authorizedFolderDiscovery: _FolderDiscovery([
        _record('chosen-folder-copy.jpg', size: 1234),
      ]),
    );
    source.beginScanSession();
    final streamed = <MediaCandidate>[];

    final outcome = await source.scanAuthorizedFolder(
      source: RecoveryScanSource.allPhotos,
      onProgress: (progress) => streamed.addAll(progress.pageCandidates),
    );

    expect(outcome.status, AuthorizedFolderScanStatus.partialFailure);
    expect(outcome.candidatesFound, 1);
    expect(inventory.calls, 0);
    expect(streamed.single.classification, RecoveryClassification.possibleCopy);
    expect(streamed.single.deletionEvidence.reasons, isEmpty);
  });

  test('folder result cap is reported as partial instead of silent exhaustion', () async {
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: _AccessCoordinator(),
      inventory: _Inventory(const []),
      trashDiscovery: _TrashDiscovery(),
      folderScopeSelector: _FolderSelector(
        AuthorizedFolderScope(
          treeUri: Uri.parse('content://provider/tree/root'),
          documentId: 'root',
          grantState: FolderGrantState.active,
        ),
      ),
      authorizedFolderDiscovery: _FolderDiscovery([
        for (var index = 0; index < 10001; index++)
          _record('photo-$index.jpg', size: 1000 + index),
      ]),
    );
    source.beginScanSession();
    var streamedCount = 0;

    final outcome = await source.scanAuthorizedFolder(
      source: RecoveryScanSource.allPhotos,
      onProgress: (progress) => streamedCount += progress.pageCandidates.length,
    );

    expect(outcome.status, AuthorizedFolderScanStatus.partialFailure);
    expect(outcome.candidatesFound, 10000);
    expect(streamedCount, 10000);
    expect(outcome.message, contains('safe retained-result limit'));
  });

  test('recognized SAF image without dimensions is retained as possible copy', () async {
    final selector = _FolderSelector(
      AuthorizedFolderScope(
        treeUri: Uri(
          scheme: 'content',
          host: 'provider',
          path: '/tree/root',
        ),
        documentId: 'root',
        grantState: FolderGrantState.active,
      ),
    );
    final record = _record('unknown-bounds.jpg', size: 1234);
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: _AccessCoordinator(),
      inventory: _Inventory(const []),
      trashDiscovery: _TrashDiscovery(),
      folderScopeSelector: selector,
      authorizedFolderDiscovery: _FolderDiscovery([record]),
    );
    source.beginScanSession();
    final streamed = <MediaCandidate>[];

    final outcome = await source.scanAuthorizedFolder(
      source: RecoveryScanSource.allPhotos,
      onProgress: (progress) => streamed.addAll(progress.pageCandidates),
    );

    expect(outcome.status, AuthorizedFolderScanStatus.completed);
    expect(streamed, hasLength(1));
    expect(streamed.single.classification, RecoveryClassification.possibleCopy);
    expect(streamed.single.deletionEvidence.reasons, isEmpty);
  });
}

AuthorizedFolderMediaRecord _record(String name, {required int size}) =>
    AuthorizedFolderMediaRecord(
      documentUri: Uri.parse(
        'content://com.android.externalstorage.documents/tree/primary%3APictures%2FAlbum/document/primary%3APictures%2FAlbum%2F$name',
      ),
      displayName: name,
      mimeType: 'image/jpeg',
      declaredMimeType: 'application/octet-stream',
      detectedFormat: 'jpeg',
      relativeLocation: 'Pictures/Album',
      byteSize: size,
    );

class _AccessCoordinator implements MediaAccessCoordinator {
  const _AccessCoordinator({this.status = MediaAccessStatus.fullAccess});

  final MediaAccessStatus status;

  @override
  Future<MediaAccessState> getState() async => MediaAccessState(
    status: status,
    androidApiLevel: 35,
  );

  @override
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  }) async => getState();

  @override
  Future<void> openSettings() async {}
}

class _Inventory implements CurrentMediaInventory {
  _Inventory(this.records);
  final List<CurrentMediaRecord> records;
  int calls = 0;

  @override
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  ) async {
    calls++;
    return CurrentMediaInventorySuccess(CurrentMediaPage(items: records));
  }
}

class _TrashDiscovery implements TrashDiscovery {
  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) async => const TrashDiscoverySuccess(TrashDiscoveryPage.empty());
}

class _FolderSelector implements FolderScopeSelector {
  const _FolderSelector(this.scope);
  final AuthorizedFolderScope scope;

  @override
  Future<FolderScopeSelectionResult> selectFolder() async =>
      FolderScopeSelectionResult(
        status: FolderScopeSelectionStatus.selected,
        scope: scope,
      );

  @override
  Future<FolderScopeSelectionResult> selectDestinationFolder() async =>
      FolderScopeSelectionResult(
        status: FolderScopeSelectionStatus.selected,
        scope: scope,
      );

  @override
  Future<FolderScopeSelectionResult> checkGrant(
    AuthorizedFolderScope scope,
  ) async => FolderScopeSelectionResult(
    status: FolderScopeSelectionStatus.selected,
    scope: this.scope,
  );
}

class _FolderDiscovery implements AuthorizedFolderMediaDiscovery {
  const _FolderDiscovery(this.records);
  final List<AuthorizedFolderMediaRecord> records;

  @override
  Future<AuthorizedFolderMediaResult> getPage({
    required Uri treeUri,
    required int pageSize,
    String? continuationToken,
  }) async => AuthorizedFolderMediaSuccess(
    AuthorizedFolderMediaPage(
      items: records,
      filesExamined: records.length,
      entriesExamined: records.length,
      providerExhausted: true,
      completionReason: 'exhausted',
    ),
  );

  @override
  Future<void> cancelScan({String? continuationToken}) async {}
}
