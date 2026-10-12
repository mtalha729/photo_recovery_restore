import '../../recovery/data/current_media_inventory/current_media_inventory.dart';
import '../../recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'photo_cleanup_models.dart';

class PhotoCleanupEngine {
  PhotoCleanupEngine({
    required this.inventory,
    required this.digestProvider,
    this.largePhotoMinimumBytes = 5 * 1024 * 1024,
    this.oldPhotoAge = const Duration(days: 365),
    PhotoCleanupAnalysisCache? cache,
    DateTime Function()? clock,
  }) : cache = cache ?? PhotoCleanupAnalysisCache(),
       _clock = clock ?? DateTime.now;

  final CurrentMediaInventory inventory;
  final PhotoCleanupDigestProvider digestProvider;
  final int largePhotoMinimumBytes;
  final Duration oldPhotoAge;
  final PhotoCleanupAnalysisCache cache;
  final PhotoCleanupDiagnostics diagnostics = PhotoCleanupDiagnostics();
  final DateTime Function() _clock;
  final Map<String, String?> _digests = {};
  List<CleanupPhoto> _photos = const [];
  PhotoCleanupIndex? _index;
  bool _cancelled = false;
  bool _disposed = false;
  bool _deleting = false;
  bool _duplicateAnalysisLoaded = false;

  Future<PhotoCleanupIndex> load({PhotoCleanupCategory? category}) async {
    if (_index != null &&
        (category != PhotoCleanupCategory.duplicatePhotos ||
            _duplicateAnalysisLoaded)) {
      return _index!;
    }
    _ensureActive();
    if (_index == null) {
      final photos = <CleanupPhoto>[];
      final seen = <String>{};
      String? continuation;
      int? afterId;
      final continuations = <String>{};
      do {
        _ensureActive();
        final result = await inventory.getCurrentMediaPage(
          CurrentMediaPageRequest(
            pageSize: 200,
            afterMediaStoreId: afterId,
            continuationToken: continuation,
          ),
        );
        _ensureActive();
        if (result is CurrentMediaInventoryFailureResult) {
          throw PhotoCleanupFailure(
            result.failure.message ?? 'Photo access is unavailable.',
          );
        }
        final page = (result as CurrentMediaInventorySuccess).page;
        for (final record in page.items) {
          if (!_isImage(record)) continue;
          final photo = CleanupPhoto(record: record, id: _idFor(record));
          if (seen.add(photo.id)) photos.add(photo);
        }
        continuation = page.nextContinuationToken;
        afterId = page.nextAfterMediaStoreId;
        if (continuation != null && !continuations.add(continuation)) {
          throw const PhotoCleanupFailure(
            'Current-media pagination repeated a cursor.',
          );
        }
      } while (continuation != null || afterId != null);
      _photos = List.unmodifiable(photos);
      _reconcileCache();
      _index = await _buildMetadataIndex();
    }
    if (category == null || category == PhotoCleanupCategory.duplicatePhotos) {
      _index = await _withDuplicateGroups(_index!);
      _duplicateAnalysisLoaded = true;
    }
    return _index!;
  }

  Future<PhotoCleanupDeletionOutcome> deleteSelected(
    Iterable<String> selectedIds,
    PhotoCleanupDeletionExecutor executor,
  ) async {
    if (_deleting) {
      throw const PhotoCleanupFailure('A deletion is already in progress.');
    }
    _deleting = true;
    try {
      final index = await load();
      _ensureActive();
      final selected = selectedIds.toSet();
      final protected = <String>{};
      for (final group in index.duplicateGroups) {
        if (selected.contains(group.protectedPhoto.id)) {
          protected.add(group.protectedPhoto.id);
        }
      }
      selected.removeAll(protected);
      final byId = {for (final photo in _photos) photo.id: photo};
      final requested = selected
          .map((id) => byId[id])
          .whereType<CleanupPhoto>();
      final deleteResult = await executor.deletePhotos(requested);
      _ensureActive();
      // Only platform-confirmed IDs can leave local inventory. Unavailable,
      // failed, and cancelled entries remain visible for an accurate retry.
      final removed = deleteResult.deletedIds;
      if (removed.isNotEmpty) {
        _photos = List.unmodifiable(
          _photos.where((photo) => !removed.contains(photo.id)),
        );
        for (final id in removed) {
          _digests.remove(id);
          cache.remove(id);
          diagnostics.deletedCacheEntries++;
        }
        _index = await _buildMetadataIndex();
        if (_duplicateAnalysisLoaded) {
          _index = await _withDuplicateGroups(_index!);
        }
      }
      return PhotoCleanupDeletionOutcome(
        deletedIds: Set.unmodifiable(deleteResult.deletedIds),
        protectedIds: Set.unmodifiable(protected),
        unavailableIds: Set.unmodifiable(deleteResult.unavailableIds),
        cancelled: deleteResult.cancelled,
      );
    } finally {
      _deleting = false;
    }
  }

  void cancel() => _cancelled = true;
  void dispose() {
    _disposed = true;
    _cancelled = true;
  }

  Future<PhotoCleanupIndex> _buildMetadataIndex() async {
    _ensureActive();
    final now = _clock();
    final cutoff = now.subtract(oldPhotoAge);
    final old =
        _photos.where((photo) {
          final date = photo.effectiveDate;
          return date != null && !date.isAfter(now) && date.isBefore(cutoff);
        }).toList()..sort(
          (a, b) => (a.effectiveDate ?? DateTime(0)).compareTo(
            b.effectiveDate ?? DateTime(0),
          ),
        );
    final large =
        _photos
            .where(
              (photo) =>
                  photo.byteSize > 0 &&
                  photo.byteSize >= largePhotoMinimumBytes,
            )
            .toList()
          ..sort((a, b) => b.byteSize.compareTo(a.byteSize));
    return PhotoCleanupIndex(
      photos: List.unmodifiable(_photos),
      duplicateGroups: const [],
      oldPhotos: List.unmodifiable(old),
      largePhotos: List.unmodifiable(large),
    );
  }

  Future<PhotoCleanupIndex> _withDuplicateGroups(
    PhotoCleanupIndex metadata,
  ) async {
    final duplicateGroups = await _findExactDuplicates(_photos);
    return metadata.copyWith(
      duplicateGroups: List.unmodifiable(duplicateGroups),
    );
  }

  Future<List<DuplicatePhotoGroup>> _findExactDuplicates(
    List<CleanupPhoto> photos,
  ) async {
    final bySize = <int, List<CleanupPhoto>>{};
    for (final photo in photos) {
      if (photo.byteSize > 0) (bySize[photo.byteSize] ??= []).add(photo);
    }
    final byDigest = <String, List<CleanupPhoto>>{};
    diagnostics.uniqueSizeGroupsSkipped += bySize.values
        .where((group) => group.length == 1)
        .length;
    for (final group in bySize.values.where((group) => group.length > 1)) {
      for (final photo in group) {
        _ensureActive();
        final digest = _digests.containsKey(photo.id)
            ? _digests[photo.id]
            : await _computeAndCacheDigest(photo);
        _digests[photo.id] = digest;
        if (digest != null && digest.isNotEmpty) {
          (byDigest[digest] ??= []).add(photo);
        }
      }
    }
    final result = <DuplicatePhotoGroup>[];
    for (final group in byDigest.values.where((group) => group.length > 1)) {
      final sorted = [...group]..sort(_bestCopyOrder);
      result.add(
        DuplicatePhotoGroup(
          protectedPhoto: sorted.first,
          duplicates: List.unmodifiable(sorted.skip(1)),
        ),
      );
    }
    result.sort((a, b) => a.protectedPhoto.id.compareTo(b.protectedPhoto.id));
    return result;
  }

  void _reconcileCache() {
    if (cache.schemaVersion != PhotoCleanupAnalysisCache.currentSchemaVersion) {
      cache.clear();
      return;
    }
    final currentIds = _photos.map((photo) => photo.id).toSet();
    cache.retain(currentIds);
    for (final photo in _photos) {
      final entry = cache[photo.id];
      if (entry != null && entry.fingerprint == _fingerprint(photo)) {
        _digests[photo.id] = entry.digest;
        diagnostics.cacheHits++;
        if (entry.digest != null) diagnostics.hashesReused++;
      } else {
        if (entry != null) cache.remove(photo.id);
        diagnostics.cacheMisses++;
      }
    }
  }

  Future<String?> _computeAndCacheDigest(CleanupPhoto photo) async {
    final digest = await digestProvider.digest(photo);
    cache[photo.id] = PhotoCleanupCacheEntry(
      fingerprint: _fingerprint(photo),
      digest: digest,
    );
    diagnostics.hashesComputed++;
    return digest;
  }

  String _fingerprint(CleanupPhoto photo) => [
    photo.id,
    photo.record.contentUri,
    photo.byteSize,
    photo.record.dateModified?.millisecondsSinceEpoch,
    photo.record.storageVolumeName,
  ].join('|');
  int _bestCopyOrder(CleanupPhoto a, CleanupPhoto b) {
    final uri = (b.record.contentUri != null ? 1 : 0).compareTo(
      a.record.contentUri != null ? 1 : 0,
    );
    if (uri != 0) return uri;
    final pixels = b.pixelCount.compareTo(a.pixelCount);
    if (pixels != 0) return pixels;
    final originalPath = (_isOriginalPath(b) ? 1 : 0).compareTo(
      _isOriginalPath(a) ? 1 : 0,
    );
    if (originalPath != 0) return originalPath;
    final date = (b.effectiveDate ?? DateTime(0)).compareTo(
      a.effectiveDate ?? DateTime(0),
    );
    if (date != 0) return date;
    return a.id.compareTo(b.id);
  }

  bool _isOriginalPath(CleanupPhoto photo) {
    final path = photo.record.relativePath?.toLowerCase() ?? '';
    return path.startsWith('dcim/') || path.startsWith('pictures/');
  }

  bool _isImage(CurrentMediaRecord record) =>
      record.mimeType == null ||
      record.mimeType!.toLowerCase().startsWith('image/');

  String _idFor(CurrentMediaRecord record) =>
      '${record.storageVolumeName ?? 'external'}:${record.mediaStoreId}';

  void _ensureActive() {
    if (_cancelled || _disposed) throw const PhotoCleanupCancelled();
  }
}
