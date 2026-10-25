import '../../domain/media_candidate.dart';

class StorageVolumeIdentity {
  const StorageVolumeIdentity({
    required this.mediaStoreVolumeName,
    required this.isRemovable,
  });

  final String mediaStoreVolumeName;
  final bool isRemovable;
}

enum FolderGrantState { active, permissionGrantLost, accessUnavailable }

/// User-granted SAF tree metadata. The grant is read-only and is never treated
/// as evidence that a file was deleted.
class AuthorizedFolderScope {
  const AuthorizedFolderScope({
    required this.treeUri,
    required this.grantState,
    this.documentId,
    this.volume,
    this.relativePathPrefix,
  });

  final Uri treeUri;
  final FolderGrantState grantState;
  final String? documentId;
  final StorageVolumeIdentity? volume;
  final String? relativePathPrefix;
}

enum ScopeMembership { inside, outside, ambiguous }

class FolderScopeMatcher {
  const FolderScopeMatcher();

  ScopeMembership evaluate(
    MediaCandidate candidate,
    AuthorizedFolderScope scope,
  ) {
    if (scope.grantState != FolderGrantState.active) {
      return ScopeMembership.ambiguous;
    }
    final candidateUri = candidate.documentUri;
    if (candidateUri != null &&
        candidateUri.authority == scope.treeUri.authority) {
      final treeId = _idAfter(scope.treeUri, 'tree') ?? scope.documentId;
      final documentId = _idAfter(candidateUri, 'document');
      if (treeId == null || documentId == null) return ScopeMembership.ambiguous;
      return documentId == treeId || documentId.startsWith('$treeId/')
          ? ScopeMembership.inside
          : ScopeMembership.outside;
    }

    final scopeVolume = scope.volume?.mediaStoreVolumeName.trim();
    final candidateVolume = candidate.storageVolumeName?.trim();
    final prefix = _normalizePath(scope.relativePathPrefix);
    final candidatePath = _normalizePath(candidate.relativeLocation);
    if (scopeVolume == null ||
        scopeVolume.isEmpty ||
        candidateVolume == null ||
        candidateVolume.isEmpty ||
        prefix == null ||
        candidatePath == null) {
      return ScopeMembership.ambiguous;
    }
    if (scopeVolume.toLowerCase() != candidateVolume.toLowerCase()) {
      return ScopeMembership.outside;
    }
    return candidatePath == prefix || candidatePath.startsWith('$prefix/')
        ? ScopeMembership.inside
        : ScopeMembership.outside;
  }

  String? _idAfter(Uri uri, String marker) {
    final index = uri.pathSegments.indexOf(marker);
    return index >= 0 && index + 1 < uri.pathSegments.length
        ? uri.pathSegments[index + 1]
        : null;
  }

  String? _normalizePath(String? value) {
    final normalized = value
        ?.trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    return normalized == null || normalized.isEmpty
        ? null
        : normalized.toLowerCase();
  }
}
