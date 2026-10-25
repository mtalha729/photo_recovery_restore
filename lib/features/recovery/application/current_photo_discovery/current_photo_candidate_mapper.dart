import '../../data/current_media_inventory/current_media_inventory_models.dart';
import '../../data/media_metadata/current_media_metadata.dart';
import '../../domain/deletion_evidence.dart';
import '../../domain/media_candidate.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_discovery_evidence.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import '../source_resolution/media_source_resolver.dart';

class CurrentPhotoCandidateMapper {
  const CurrentPhotoCandidateMapper();

  MediaCandidate? map(CurrentMediaRecord record) => _map(record);

  MediaCandidate? mapRecoveryArtifact(CurrentMediaRecord record) {
    if (record.recoveryArtifactFormat == null ||
        (!record.isThumbnailArtifact && !record.isCacheArtifact)) {
      return null;
    }
    return _map(record, recoveryArtifact: true);
  }

  MediaCandidate? _map(
    CurrentMediaRecord record, {
    bool recoveryArtifact = false,
  }) {
    final uri = record.contentUri;
    if (uri == null || uri.scheme != 'content') return null;
    final volume = record.storageVolumeName;
    final normalizedVolume = volume?.toLowerCase();
    final removable =
        normalizedVolume != null &&
        normalizedVolume != 'external' &&
        normalizedVolume != 'external_primary';
    final source = const MediaSourceResolver().resolve(
      CurrentMediaMetadata(
        mediaStoreId: record.mediaStoreId,
        relativePath: record.relativePath,
        bucketName: record.bucketName,
        isRemovableStorage: removable,
      ),
    );
    final segments = [record.relativePath, record.bucketName]
        .whereType<String>()
        .join('/')
        .replaceAll('\\', '/')
        .toLowerCase()
        .split('/');
    final thumbnail =
        record.isThumbnailArtifact ||
        segments.any(
          (part) =>
              part == '.thumbnails' ||
              part == 'thumbnails' ||
              part == 'thumbnail' ||
              part == 'thumbcache',
        );
    final cache =
        record.isCacheArtifact ||
        thumbnail ||
        segments.any(
          (part) =>
              part == '.cache' || part == 'cache' || part == 'image cache',
        );
    final hidden = segments.any(
      (part) => part.startsWith('.') && part.length > 1,
    );
    return MediaCandidate(
      id: '${recoveryArtifact ? 'artifact' : 'current'}:${uri.toString()}',
      source: source,
      contentUri: uri,
      mediaStoreId: record.mediaStoreId,
      displayName: record.displayName,
      mimeType: record.mimeType,
      relativeLocation: record.relativePath,
      bucketName: record.bucketName,
      storageVolumeName: volume,
      isRemovableStorage: removable,
      byteSize: record.byteSize,
      width: record.width,
      height: record.height,
      createdAt: record.dateAdded,
      modifiedAt: record.dateModified,
      takenAt: record.dateTaken,
      discoveryEvidence: RecoveryDiscoveryEvidence(
        detectedFormat: recoveryArtifact ? record.recoveryArtifactFormat : null,
        isThumbnailLike: thumbnail,
        isCacheLike: cache,
        isHidden: hidden,
      ),
      classification: recoveryArtifact
          ? RecoveryClassification.possibleCopy
          : RecoveryClassification.existingMedia,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: recoveryArtifact
          ? thumbnail
                ? RestoreCapability.lowerResolutionCopy
                : RestoreCapability.unknownQualityCopy
          : RestoreCapability.alternateFullQualityCopy,
      recoveryQuality: recoveryArtifact
          ? thumbnail
                ? RecoveryQuality.reducedResolutionCopy
                : RecoveryQuality.unknownQualityCopy
          : RecoveryQuality.original,
    );
  }
}
