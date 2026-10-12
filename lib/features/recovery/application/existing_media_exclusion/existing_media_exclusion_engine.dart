import '../../domain/media_candidate.dart';
import 'existing_media_exclusion_models.dart';
import 'existing_media_index.dart';

class ExistingMediaExclusionEngine {
  const ExistingMediaExclusionEngine();

  ExistingMediaDecision evaluate(
    MediaCandidate candidate,
    ExistingMediaIndex index,
  ) {
    final uriKey = ExistingMediaKeys.uri(candidate.contentUri);
    final uriMatches = uriKey == null ? null : index.findByUri(uriKey);
    if (uriMatches != null && uriMatches.isNotEmpty) {
      return ExistingMediaDecision.definitelyExisting(uriMatches.first);
    }

    final platformKey = ExistingMediaKeys.platformIdentity(
      mediaStoreId: candidate.mediaStoreId,
      storageVolumeName: candidate.storageVolumeName,
    );
    final platformMatches = platformKey == null
        ? null
        : index.findByPlatformIdentity(platformKey);
    if (platformMatches != null && platformMatches.isNotEmpty) {
      return ExistingMediaDecision.definitelyExisting(platformMatches.first);
    }

    final storageLocationKey = ExistingMediaKeys.storageLocation(
      storageVolumeName: candidate.storageVolumeName,
      relativeLocation: candidate.relativeLocation,
      displayName: candidate.displayName,
      byteSize: candidate.byteSize,
    );
    final storageLocationMatches = storageLocationKey == null
        ? null
        : index.findByStorageLocation(storageLocationKey);
    if (storageLocationMatches != null) {
      if (storageLocationMatches.length == 1) {
        return ExistingMediaDecision.definitelyExisting(
          storageLocationMatches.single,
        );
      }
      if (storageLocationMatches.isNotEmpty) {
        return const ExistingMediaDecision.uncertainIdentity();
      }
    }

    final compositeKey = ExistingMediaKeys.compositeMetadata(
      displayName: candidate.displayName,
      mimeType: candidate.mimeType,
      byteSize: candidate.byteSize,
      width: candidate.width,
      height: candidate.height,
      relativeLocation: candidate.relativeLocation,
      bucketName: candidate.bucketName,
    );
    final compositeMatches = compositeKey == null
        ? null
        : index.findByCompositeMetadata(compositeKey);
    if (compositeMatches != null) {
      if (compositeMatches.length == 1) {
        return ExistingMediaDecision.definitelyExisting(
          compositeMatches.single,
        );
      }
      if (compositeMatches.isNotEmpty) {
        return const ExistingMediaDecision.uncertainIdentity();
      }
    }

    if (_hasWeakOverlap(candidate, index)) {
      return const ExistingMediaDecision.uncertainIdentity();
    }
    return const ExistingMediaDecision.noExistingMatch();
  }

  bool _hasWeakOverlap(MediaCandidate candidate, ExistingMediaIndex index) {
    final fileName = ExistingMediaKeys.text(candidate.displayName);
    if (fileName != null && index.containsFileName(fileName)) return true;

    final dimensions = ExistingMediaKeys.dimensions(
      candidate.width,
      candidate.height,
    );
    if (dimensions != null && index.containsDimensions(dimensions)) return true;

    for (final timestamp in [
      candidate.takenAt,
      candidate.modifiedAt,
      candidate.createdAt,
    ]) {
      if (timestamp != null &&
          index.containsTimestamp(timestamp.millisecondsSinceEpoch)) {
        return true;
      }
    }
    return false;
  }
}
