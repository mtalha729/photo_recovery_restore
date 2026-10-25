import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/media_access/media_access.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/production_recovery_scan_page_source.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_controller.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_models.dart';

void main() {
  test('198 ordinary gallery records produce no recovery results', () async {
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: const _Access(),
      inventory: _Inventory([
        for (var id = 1; id <= 198; id++)
          CurrentMediaRecord(
            mediaStoreId: id,
            contentUri: Uri.parse('content://media/external/images/media/$id'),
            relativePath: 'DCIM/Camera/',
            displayName: 'photo_$id.jpg',
          ),
      ]),
      trashDiscovery: _Trash(),
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: source,
    );

    await controller.start();

    expect(source.diagnostics.currentRecordsScanned, 198);
    expect(source.diagnostics.currentPhotosMapped, 198);
    expect(controller.state.status, RecoveryScanViewStatus.empty);
    expect(controller.state.verifiedItems, isEmpty);
    expect(controller.state.possibleCopies, isEmpty);
    expect(controller.state.existingPhotos, isEmpty);
  });

  test(
    '198 gallery records plus three separate artifacts show only artifacts',
    () async {
      final artifacts = [
        (
          'alternate',
          '/storage/emulated/0/Pictures/Recovered/alternate.jpg',
          'Pictures/Recovered/',
          const RecoveryDiscoveryEvidence(),
        ),
        (
          'thumbnail',
          '/storage/emulated/0/DCIM/.thumbnails/thumb.jpg',
          'DCIM/.thumbnails/',
          const RecoveryDiscoveryEvidence(isThumbnailLike: true),
        ),
        (
          'cache',
          '/storage/emulated/0/Pictures/.cache/cached.jpg',
          'Pictures/.cache/',
          const RecoveryDiscoveryEvidence(isCacheLike: true),
        ),
      ];
      final deep = _DeepProvider(
        records: [
          for (final (id, path, location, evidence) in artifacts)
            DeepRecoveryDiscoveryRecord(
              provider: DeepRecoveryProviderKind.directSharedStorage,
              candidate: MediaCandidate(
                id: id,
                source: MediaSource.unknown,
                filePath: path,
                displayName: '$id.jpg',
                relativeLocation: location,
                classification: RecoveryClassification.possibleCopy,
                discoveryEvidence: evidence,
                deletionEvidence: DeletionEvidence(),
                restoreCapability: RestoreCapability.unknownQualityCopy,
                recoveryQuality: RecoveryQuality.unknownQualityCopy,
              ),
            ),
        ],
      );
      final source = ProductionRecoveryScanPageSource(
        accessCoordinator: const _Access(),
        inventory: _Inventory([
          for (var id = 1; id <= 198; id++)
            CurrentMediaRecord(
              mediaStoreId: id,
              contentUri: Uri.parse(
                'content://media/external/images/media/$id',
              ),
              relativePath: 'DCIM/Camera/',
              displayName: 'photo_$id.jpg',
            ),
        ]),
        trashDiscovery: _Trash(),
        deepStorageProvider: deep,
        includeDeepStorage: true,
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: source,
      );

      await controller.start();

      expect(source.diagnostics.currentRecordsScanned, 198);
      expect(controller.state.existingPhotos, isEmpty);
      expect(controller.state.possibleCopies, hasLength(3));
      expect(controller.state.possibleCopies.map((item) => item.id).toSet(), {
        'alternate',
        'thumbnail',
        'cache',
      });
      expect(controller.state.verifiedItems, isEmpty);
      expect(deep.calls, greaterThan(0));
    },
  );

  test('ordinary MediaStore photos are indexed but never published as recovery results', () async {
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: const _Access(),
      inventory: _Inventory([
        CurrentMediaRecord(
          mediaStoreId: 1,
          contentUri: Uri.parse('content://media/external/images/media/1'),
          relativePath: 'DCIM/Camera/',
          displayName: 'camera.jpg',
          byteSize: 123,
        ),
        CurrentMediaRecord(
          mediaStoreId: 2,
          contentUri: Uri.parse('content://media/external/images/media/2'),
          relativePath: 'Pictures/Screenshots/',
          displayName: 'screenshot.jpg',
        ),
      ]),
      trashDiscovery: _Trash(),
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: source,
    );
    await controller.start();

    expect(controller.state.status, RecoveryScanViewStatus.empty);
    expect(controller.state.existingPhotos, isEmpty);
    expect(source.diagnostics.mediaStoreRowsReturned, 2);
    expect(source.diagnostics.currentPhotosMapped, 2);
    expect(source.diagnostics.currentRowsRejected, 0);
    expect(controller.state.verifiedItems, isEmpty);
    expect(controller.state.possibleCopies, isEmpty);
  });

  test(
    'inventory record cap still runs trash and reports partial coverage',
    () async {
      final inventory = _Inventory([
        for (var id = 1; id <= 4; id++)
          CurrentMediaRecord(
            mediaStoreId: id,
            contentUri: Uri.parse('content://media/external/images/media/$id'),
          ),
      ]);
      final trash = _Trash();
      final source = ProductionRecoveryScanPageSource(
        accessCoordinator: _Access(),
        inventory: inventory,
        trashDiscovery: trash,
        maximumCurrentInventoryRecords: 3,
      );

      final firstResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        const TrashDiscoveryPageRequest(pageSize: 200),
      );

      expect(firstResult, isA<VerifiedSourceRecoverySuccess>());
      final firstPage = firstResult as VerifiedSourceRecoverySuccess;
      expect(firstPage.items, isEmpty);
      expect(firstPage.mayHaveMore, isTrue);
      expect(inventory.calls, 1);
      expect(trash.calls, 1);
      expect(
        source.diagnostics.currentMediaInventoryState,
        'resourceLimitPartial',
      );
      expect(source.diagnostics.currentRecordsScanned, 3);

      final terminalResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        TrashDiscoveryPageRequest(
          pageSize: 200,
          continuationToken: firstPage.nextContinuationToken,
        ),
      );
      expect(terminalResult, isA<VerifiedSourceRecoveryFailure>());
      final failure = terminalResult as VerifiedSourceRecoveryFailure;
      expect(failure.code, VerifiedSourceRecoveryFailureCode.resourceLimit);
      expect(failure.message, contains('safe page or record limit'));
    },
  );

  test(
    'partial inventory retains comparison records, not visible originals',
    () async {
      final uri = Uri.parse('content://media/external/images/media/5');
      final source = ProductionRecoveryScanPageSource(
        accessCoordinator: const _Access(),
        inventory: _Inventory([
          CurrentMediaRecord(mediaStoreId: 5, contentUri: uri),
          CurrentMediaRecord(mediaStoreId: 5, contentUri: uri),
          CurrentMediaRecord(
            mediaStoreId: 6,
            contentUri: Uri.parse('content://media/external/images/media/6'),
          ),
          CurrentMediaRecord(
            mediaStoreId: 7,
            contentUri: Uri.parse('content://media/external/images/media/7'),
          ),
        ]),
        trashDiscovery: _Trash(),
        maximumCurrentInventoryRecords: 2,
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: source,
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.partial);
      expect(controller.state.existingPhotos, isEmpty);
      expect(source.diagnostics.currentRecordsScanned, 2);
      expect(source.diagnostics.mediaStoreRowsReturned, 4);
      expect(source.diagnostics.currentDuplicatesSuppressed, 1);
    },
  );

  test(
    'inventory page cap still runs trash and reports partial coverage',
    () async {
      final inventory = _Inventory(const [], nextContinuationToken: 'next');
      final trash = _Trash();
      final source = ProductionRecoveryScanPageSource(
        accessCoordinator: _Access(),
        inventory: inventory,
        trashDiscovery: trash,
        maximumCurrentInventoryPages: 1,
      );

      final firstResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        const TrashDiscoveryPageRequest(pageSize: 200),
      );

      expect(firstResult, isA<VerifiedSourceRecoverySuccess>());
      final firstPage = firstResult as VerifiedSourceRecoverySuccess;
      expect(firstPage.mayHaveMore, isTrue);
      expect(inventory.calls, 1);
      expect(trash.calls, 1);
      expect(
        source.diagnostics.currentMediaInventoryState,
        'resourceLimitPartial',
      );

      final terminalResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        TrashDiscoveryPageRequest(
          pageSize: 200,
          continuationToken: firstPage.nextContinuationToken,
        ),
      );
      expect(terminalResult, isA<VerifiedSourceRecoveryFailure>());
      expect(
        (terminalResult as VerifiedSourceRecoveryFailure).code,
        VerifiedSourceRecoveryFailureCode.resourceLimit,
      );
    },
  );

  test(
    'missing broad access does not suppress an independent trash provider',
    () async {
      final inventory = _Inventory(const []);
      final trash = _Trash();
      final source = ProductionRecoveryScanPageSource(
        accessCoordinator: _Access(status: MediaAccessStatus.denied),
        inventory: inventory,
        trashDiscovery: trash,
      );

      final firstResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        const TrashDiscoveryPageRequest(pageSize: 200),
      );

      expect(firstResult, isA<VerifiedSourceRecoverySuccess>());
      final firstPage = firstResult as VerifiedSourceRecoverySuccess;
      expect(firstPage.mayHaveMore, isTrue);
      expect(inventory.calls, 0);
      expect(trash.calls, 1);
      expect(
        source.diagnostics.currentMediaInventoryState,
        'notGranted:denied',
      );

      final terminalResult = await source.loadPage(
        RecoveryScanSource.allPhotos,
        TrashDiscoveryPageRequest(
          pageSize: 200,
          continuationToken: firstPage.nextContinuationToken,
        ),
      );
      expect(terminalResult, isA<VerifiedSourceRecoveryFailure>());
      expect(
        (terminalResult as VerifiedSourceRecoveryFailure).code,
        VerifiedSourceRecoveryFailureCode.accessUnavailable,
      );
    },
  );

  test('inventory exception still runs trash and deep providers', () async {
    final inventory = _Inventory(const [], throws: true);
    final trash = _Trash();
    final deep = _DeepProvider();
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: _Access(),
      inventory: inventory,
      trashDiscovery: trash,
      deepStorageProvider: deep,
      includeDeepStorage: true,
      profile: PhotoRecoveryProfile.thorough,
    );

    final first = await source.loadPage(
      RecoveryScanSource.allPhotos,
      const TrashDiscoveryPageRequest(pageSize: 200),
    ) as VerifiedSourceRecoverySuccess;
    final last = await source.loadPage(
      RecoveryScanSource.allPhotos,
      TrashDiscoveryPageRequest(
        pageSize: 200,
        continuationToken: first.nextContinuationToken,
      ),
    );

    expect(last, isA<VerifiedSourceRecoveryFailure>());
    expect(inventory.calls, 1);
    expect(trash.calls, 1);
    expect(deep.calls, 1);
    expect(
      source.possibleCopies.map((candidate) => candidate.id),
      contains('hidden-copy'),
    );
    expect(source.diagnostics.currentMediaInventoryState, 'failed:exception');
  });

  test('trash exception still runs deep provider and keeps its copy', () async {
    final deep = _DeepProvider();
    final source = ProductionRecoveryScanPageSource(
      accessCoordinator: _Access(),
      inventory: _Inventory(const []),
      trashDiscovery: _Trash(throws: true),
      deepStorageProvider: deep,
      includeDeepStorage: true,
    );

    final first = await source.loadPage(
      RecoveryScanSource.allPhotos,
      const TrashDiscoveryPageRequest(pageSize: 200),
    ) as VerifiedSourceRecoverySuccess;
    final last = await source.loadPage(
      RecoveryScanSource.allPhotos,
      TrashDiscoveryPageRequest(
        pageSize: 200,
        continuationToken: first.nextContinuationToken,
      ),
    );

    expect(last, isA<VerifiedSourceRecoveryFailure>());
    expect(deep.calls, 1);
    expect(source.possibleCopies, hasLength(1));
    expect(source.diagnostics.verifiedTrashProviderState, 'failed:exception');
  });
}

class _Access implements MediaAccessCoordinator {
  const _Access({this.status = MediaAccessStatus.fullAccess});

  final MediaAccessStatus status;

  @override
  Future<MediaAccessState> getState() async =>
      MediaAccessState(status: status, androidApiLevel: 34);

  @override
  Future<void> openSettings() async {}

  @override
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  }) async => getState();
}

class _Inventory implements CurrentMediaInventory {
  _Inventory(this.items, {this.nextContinuationToken, this.throws = false});

  final List<CurrentMediaRecord> items;
  final String? nextContinuationToken;
  final bool throws;
  int calls = 0;

  @override
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  ) async {
    calls++;
    if (throws) throw StateError('inventory unavailable');
    return CurrentMediaInventorySuccess(
      CurrentMediaPage(
        items: items,
        nextContinuationToken: nextContinuationToken,
      ),
    );
  }
}

class _Trash implements TrashDiscovery {
  _Trash({this.throws = false});

  final bool throws;
  int calls = 0;

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) async {
    calls++;
    if (throws) throw StateError('trash unavailable');
    return const TrashDiscoverySuccess(TrashDiscoveryPage.empty());
  }
}

class _DeepProvider extends PlatformDeepStorageRecoveryProvider {
  _DeepProvider({this.records});

  final List<DeepRecoveryDiscoveryRecord>? records;
  int calls = 0;

  @override
  Future<DeepStorageCapabilityState> getCapability() async =>
      const DeepStorageCapabilityState(
        status: DeepStorageCapabilityStatus.available,
        requiresAllFilesAccess: false,
        mode: DeepStorageAccessMode.legacySharedRead,
        androidApiLevel: 28,
      );

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) async {
    calls++;
    return DeepRecoveryProviderPage(
      items:
          records ??
          [
            DeepRecoveryDiscoveryRecord(
              provider: DeepRecoveryProviderKind.directSharedStorage,
              candidate: MediaCandidate(
                id: 'hidden-copy',
                source: MediaSource.unknown,
                filePath: '/storage/emulated/0/.cache/hidden.jpg',
                displayName: 'hidden.jpg',
                relativeLocation: '.cache',
                classification: RecoveryClassification.possibleCopy,
                deletionEvidence: DeletionEvidence(),
                restoreCapability: RestoreCapability.unknownQualityCopy,
                recoveryQuality: RecoveryQuality.unknownQualityCopy,
              ),
            ),
          ],
      providerExhausted: true,
      completionReason: 'exhausted',
    );
  }
}
