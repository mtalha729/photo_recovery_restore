import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/smart_cleanup/application/photo_cleanup_engine.dart';
import 'package:photo_recovery_restore/features/smart_cleanup/application/photo_cleanup_models.dart';

void main() {
  test(
    'loads current image inventory once and reuses one cleanup index',
    () async {
      final inventory = _Inventory([
        [_photo(1), _photo(2)],
      ]);
      final engine = _engine(inventory, {'external:1': 'a', 'external:2': 'b'});

      final first = await engine.load();
      final second = await engine.load();

      expect(identical(first, second), isTrue);
      expect(inventory.calls, 1);
    },
  );

  test(
    'exact content evidence groups duplicates and protects one copy',
    () async {
      final engine = _engine(
        _Inventory([
          [_photo(1), _photo(2)],
        ]),
        {'external:1': 'same-digest', 'external:2': 'same-digest'},
      );

      final index = await engine.load();

      expect(index.duplicateGroups, hasLength(1));
      expect(index.duplicateGroups.single.count, 2);
      expect(index.duplicateGroups.single.protectedPhoto.id, 'external:1');
      expect(index.duplicateGroups.single.duplicates.single.id, 'external:2');
      expect(index.duplicateGroups.single.reclaimableBytes, 1000);
    },
  );

  test(
    'same filename or dimensions with different bytes are not duplicates',
    () async {
      final inventory = _Inventory([
        [
          _photo(1, name: 'same.jpg', bytes: 1000, width: 100),
          _photo(2, name: 'same.jpg', bytes: 1001, width: 100),
          _photo(3, name: 'different.jpg', bytes: 1000, width: 100),
        ],
      ]);
      final index = await _engine(inventory, {
        'external:1': 'first',
        'external:2': 'second',
        'external:3': 'third',
      }).load();

      expect(index.duplicateGroups, isEmpty);
    },
  );

  test('unchanged photos reuse cache while modified photos rehash', () async {
    final cache = PhotoCleanupAnalysisCache();
    final digests = _CountingDigests({
      'external:1': 'same',
      'external:2': 'same',
    });
    await PhotoCleanupEngine(
      inventory: _Inventory([
        [_photo(1), _photo(2)],
      ]),
      digestProvider: digests,
      cache: cache,
    ).load();
    expect(digests.calls, 2);

    await PhotoCleanupEngine(
      inventory: _Inventory([
        [_photo(1), _photo(2)],
      ]),
      digestProvider: digests,
      cache: cache,
    ).load();
    expect(digests.calls, 2);

    await PhotoCleanupEngine(
      inventory: _Inventory([
        [_photo(1, modified: DateTime.utc(2025)), _photo(2)],
      ]),
      digestProvider: digests,
      cache: cache,
    ).load();
    expect(digests.calls, 3);
  });
  test('old photos use valid current-media date fallback', () async {
    final now = DateTime.utc(2026, 1, 1);
    final inventory = _Inventory([
      [
        _photo(1, taken: DateTime.utc(2024, 1, 1)),
        _photo(2, modified: DateTime.utc(2025, 12, 15)),
        _photo(3, added: DateTime.utc(2024, 12, 1)),
      ],
    ]);
    final index = await PhotoCleanupEngine(
      inventory: inventory,
      digestProvider: _Digests(const {}),
      clock: () => now,
    ).load();

    expect(index.oldPhotos.map((photo) => photo.id), [
      'external:1',
      'external:3',
    ]);
  });

  test('large photos are image-only and sorted by byte size', () async {
    final inventory = _Inventory([
      [
        _photo(1, bytes: 100),
        _photo(2, bytes: 900),
        CurrentMediaRecord(
          mediaStoreId: 3,
          mimeType: 'video/mp4',
          byteSize: 9999,
        ),
        CurrentMediaRecord(
          mediaStoreId: 4,
          mimeType: 'application/pdf',
          byteSize: 5000,
        ),
      ],
    ]);
    final index = await PhotoCleanupEngine(
      inventory: inventory,
      digestProvider: _Digests(const {}),
      largePhotoMinimumBytes: 1,
    ).load();

    expect(index.largePhotos.map((photo) => photo.id), [
      'external:2',
      'external:1',
    ]);
  });

  test('old and large analysis do not trigger duplicate hashing', () async {
    final digests = _CountingDigests({
      'external:1': 'same',
      'external:2': 'same',
    });
    final engine = PhotoCleanupEngine(
      inventory: _Inventory([
        [_photo(1, bytes: 6000), _photo(2, bytes: 6000)],
      ]),
      digestProvider: digests,
      largePhotoMinimumBytes: 1,
      clock: () => DateTime.utc(2026, 1, 1),
    );

    await engine.load(category: PhotoCleanupCategory.oldPhotos);
    await engine.load(category: PhotoCleanupCategory.largePhotos);
    expect(digests.calls, 0);

    final duplicates = await engine.load(
      category: PhotoCleanupCategory.duplicatePhotos,
    );
    expect(digests.calls, 2);
    expect(duplicates.duplicateGroups, hasLength(1));
  });

  test('repeated inventory continuation fails instead of publishing partial cleanup', () async {
    final engine = _engine(_RepeatingInventory(), const {});

    expect(engine.load(), throwsA(isA<PhotoCleanupFailure>()));
  });
  test('screen-local selection tracks exact count and bytes', () {
    final duplicateSelection = PhotoCleanupSelection();
    final oldSelection = PhotoCleanupSelection();
    final first = CleanupPhoto(record: _photo(1, bytes: 100), id: 'external:1');
    final second = CleanupPhoto(
      record: _photo(2, bytes: 900),
      id: 'external:2',
    );

    duplicateSelection.toggle(first);
    duplicateSelection.toggle(second, protectedIds: {'external:2'});

    expect(duplicateSelection.selectedIds, {'external:1'});
    expect(duplicateSelection.selectedBytes([first, second]), 100);
    expect(oldSelection.selectedIds, isEmpty);
    expect(duplicateSelection.canDelete, isTrue);
  });

  test(
    'cancelled or partial deletion only reconciles confirmed removals',
    () async {
      final inventory = _Inventory([
        [_photo(1), _photo(2), _photo(3)],
      ]);
      final engine = _engine(inventory, const {});
      await engine.load();

      final cancelled = await engine.deleteSelected([
        'external:1',
      ], _ResultExecutor(const PhotoCleanupDeleteResult(cancelled: true)));
      expect(cancelled.cancelled, isTrue);
      expect((await engine.load()).photos, hasLength(3));

      final partial = await engine.deleteSelected(
        ['external:1', 'external:2'],
        _ResultExecutor(
          const PhotoCleanupDeleteResult(
            deletedIds: {'external:1'},
            unavailableIds: {'external:2'},
          ),
        ),
      );
      expect(partial.deletedIds, {'external:1'});
      expect(partial.unavailableIds, {'external:2'});
      expect((await engine.load()).photos.map((photo) => photo.id), [
        'external:2',
        'external:3',
      ]);
      expect(inventory.calls, 1);
    },
  );
  test(
    'deletion preserves duplicate best copy and refreshes local results',
    () async {
      final engine = _engine(
        _Inventory([
          [_photo(1), _photo(2), _photo(3, bytes: 5000)],
        ]),
        {'external:1': 'same', 'external:2': 'same', 'external:3': 'unique'},
        minimumLargeBytes: 1,
      );
      await engine.load();
      final deleted = await engine.deleteSelected([
        'external:1',
        'external:2',
        'external:3',
      ], _DeleteExecutor());
      final refreshed = await engine.load();

      expect(deleted.protectedIds, {'external:1'});
      expect(deleted.deletedIds, {'external:2', 'external:3'});
      expect(refreshed.photos.map((photo) => photo.id), ['external:1']);
      expect(refreshed.duplicateGroups, isEmpty);
      expect(refreshed.largePhotos.map((photo) => photo.id), ['external:1']);
    },
  );
}

PhotoCleanupEngine _engine(
  CurrentMediaInventory inventory,
  Map<String, String> digests, {
  int minimumLargeBytes = 5 * 1024 * 1024,
}) => PhotoCleanupEngine(
  inventory: inventory,
  digestProvider: _Digests(digests),
  largePhotoMinimumBytes: minimumLargeBytes,
  clock: () => DateTime.utc(2026, 1, 1),
);

CurrentMediaRecord _photo(
  int id, {
  String name = 'photo.jpg',
  int bytes = 1000,
  int width = 100,
  DateTime? taken,
  DateTime? added,
  DateTime? modified,
}) => CurrentMediaRecord(
  mediaStoreId: id,
  contentUri: Uri.parse('content://media/$id'),
  mimeType: 'image/jpeg',
  displayName: name,
  storageVolumeName: 'external',
  byteSize: bytes,
  width: width,
  height: 100,
  dateTaken: taken,
  dateAdded: added,
  dateModified: modified,
  relativePath: 'DCIM/Camera',
);

class _Inventory implements CurrentMediaInventory {
  _Inventory(this.pages);
  final List<List<CurrentMediaRecord>> pages;
  int calls = 0;

  @override
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  ) async {
    calls++;
    final pageIndex = request.continuationToken == null
        ? 0
        : int.parse(request.continuationToken!);
    final next = pageIndex + 1 < pages.length ? '${pageIndex + 1}' : null;
    return CurrentMediaInventorySuccess(
      CurrentMediaPage(items: pages[pageIndex], nextContinuationToken: next),
    );
  }
}

class _Digests implements PhotoCleanupDigestProvider {
  const _Digests(this.values);
  final Map<String, String> values;

  @override
  Future<String?> digest(CleanupPhoto photo) async => values[photo.id];
}

class _DeleteExecutor implements PhotoCleanupDeletionExecutor {
  @override
  Future<PhotoCleanupDeleteResult> deletePhotos(
    Iterable<CleanupPhoto> photos,
  ) async => PhotoCleanupDeleteResult(
    deletedIds: photos.map((photo) => photo.id).toSet(),
  );
}

class _ResultExecutor implements PhotoCleanupDeletionExecutor {
  const _ResultExecutor(this.result);
  final PhotoCleanupDeleteResult result;

  @override
  Future<PhotoCleanupDeleteResult> deletePhotos(
    Iterable<CleanupPhoto> photos,
  ) async => result;
}

class _CountingDigests extends _Digests {
  _CountingDigests(super.values);
  int calls = 0;

  @override
  Future<String?> digest(CleanupPhoto photo) async {
    calls++;
    return super.digest(photo);
  }
}

class _RepeatingInventory implements CurrentMediaInventory {
  @override
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  ) async => CurrentMediaInventorySuccess(
    CurrentMediaPage(items: [_photo(1)], nextContinuationToken: 'same-token'),
  );
}
