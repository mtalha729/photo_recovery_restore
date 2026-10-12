import '../../recovery/data/current_media_inventory/current_media_inventory_models.dart';

class PhotoCleanupCacheEntry {
  const PhotoCleanupCacheEntry({
    required this.fingerprint,
    required this.digest,
  });

  final String fingerprint;
  final String? digest;
}

class PhotoCleanupAnalysisCache {
  PhotoCleanupAnalysisCache({this.schemaVersion = currentSchemaVersion});

  static const currentSchemaVersion = 1;
  final int schemaVersion;
  final Map<String, PhotoCleanupCacheEntry> _entries = {};

  PhotoCleanupCacheEntry? operator [](String id) => _entries[id];
  void operator []=(String id, PhotoCleanupCacheEntry value) =>
      _entries[id] = value;
  void remove(String id) => _entries.remove(id);
  void retain(Iterable<String> ids) =>
      _entries.removeWhere((id, _) => !ids.contains(id));
  void clear() => _entries.clear();
}

class PhotoCleanupDiagnostics {
  int cacheHits = 0;
  int cacheMisses = 0;
  int hashesReused = 0;
  int hashesComputed = 0;
  int uniqueSizeGroupsSkipped = 0;
  int deletedCacheEntries = 0;
}

class CleanupPhoto {
  const CleanupPhoto({required this.record, required this.id});

  final CurrentMediaRecord record;
  final String id;

  int get byteSize => record.byteSize ?? 0;
  int get pixelCount => (record.width ?? 0) * (record.height ?? 0);
  DateTime? get effectiveDate =>
      record.dateTaken ?? record.dateModified ?? record.dateAdded;
}

class DuplicatePhotoGroup {
  const DuplicatePhotoGroup({
    required this.protectedPhoto,
    required this.duplicates,
  });

  final CleanupPhoto protectedPhoto;
  final List<CleanupPhoto> duplicates;

  List<CleanupPhoto> get photos => [protectedPhoto, ...duplicates];
  int get count => photos.length;
  int get reclaimableBytes =>
      duplicates.fold(0, (total, photo) => total + photo.byteSize);
}

class PhotoCleanupIndex {
  const PhotoCleanupIndex({
    required this.photos,
    required this.duplicateGroups,
    required this.oldPhotos,
    required this.largePhotos,
  });

  final List<CleanupPhoto> photos;
  final List<DuplicatePhotoGroup> duplicateGroups;
  final List<CleanupPhoto> oldPhotos;
  final List<CleanupPhoto> largePhotos;

  PhotoCleanupIndex copyWith({List<DuplicatePhotoGroup>? duplicateGroups}) =>
      PhotoCleanupIndex(
        photos: photos,
        duplicateGroups: duplicateGroups ?? this.duplicateGroups,
        oldPhotos: oldPhotos,
        largePhotos: largePhotos,
      );

  int get duplicateReclaimableBytes =>
      duplicateGroups.fold(0, (total, group) => total + group.reclaimableBytes);
  int get oldPhotosBytes =>
      oldPhotos.fold(0, (total, photo) => total + photo.byteSize);
  int get largePhotosBytes =>
      largePhotos.fold(0, (total, photo) => total + photo.byteSize);
}

abstract interface class PhotoCleanupDigestProvider {
  Future<String?> digest(CleanupPhoto photo);
}

abstract interface class PhotoCleanupDeletionExecutor {
  Future<PhotoCleanupDeleteResult> deletePhotos(Iterable<CleanupPhoto> photos);
}

class PhotoCleanupDeleteResult {
  const PhotoCleanupDeleteResult({
    this.deletedIds = const {},
    this.unavailableIds = const {},
    this.cancelled = false,
  });

  final Set<String> deletedIds;
  final Set<String> unavailableIds;
  final bool cancelled;

  Set<String> get removedIds => {...deletedIds, ...unavailableIds};
}

enum PhotoCleanupCategory { duplicatePhotos, oldPhotos, largePhotos }

class PhotoCleanupSelection {
  final Set<String> _selectedIds = {};
  bool _deleting = false;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isDeleting => _deleting;
  bool get canDelete => _selectedIds.isNotEmpty && !_deleting;

  int selectedBytes(Iterable<CleanupPhoto> visiblePhotos) {
    final byId = {for (final photo in visiblePhotos) photo.id: photo};
    return _selectedIds.fold(
      0,
      (total, id) => total + (byId[id]?.byteSize ?? 0),
    );
  }

  void toggle(CleanupPhoto photo, {Set<String> protectedIds = const {}}) {
    if (_deleting || protectedIds.contains(photo.id)) return;
    if (!_selectedIds.add(photo.id)) _selectedIds.remove(photo.id);
  }

  void selectAll(
    Iterable<CleanupPhoto> photos, {
    Set<String> protectedIds = const {},
  }) {
    if (_deleting) return;
    _selectedIds.addAll(
      photos.map((photo) => photo.id).where((id) => !protectedIds.contains(id)),
    );
  }

  void removeAll(Iterable<String> ids) => _selectedIds.removeAll(ids);
  void clear() => _selectedIds.clear();
  void beginDeletion() => _deleting = true;
  void endDeletion() => _deleting = false;
}

class PhotoCleanupDeletionOutcome {
  const PhotoCleanupDeletionOutcome({
    required this.deletedIds,
    required this.protectedIds,
    this.unavailableIds = const {},
    this.cancelled = false,
  });

  final Set<String> deletedIds;
  final Set<String> protectedIds;
  final Set<String> unavailableIds;
  final bool cancelled;
}

class PhotoCleanupCancelled implements Exception {
  const PhotoCleanupCancelled();
}

class PhotoCleanupFailure implements Exception {
  const PhotoCleanupFailure(this.message);
  final String message;
}
