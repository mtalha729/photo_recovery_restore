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

    final documentMembership = _documentMembership(candidate, scope);
    if (documentMembership != null) return documentMembership;

    final scopeVolume = _clean(scope.volume?.mediaStoreVolumeName);
    final candidateVolume = _clean(candidate.storageVolumeName);
    final prefix = _normalizePath(scope.relativePathPrefix);
    final candidatePath = _normalizePath(candidate.relativeLocation);
    if (scopeVolume == null ||
        candidateVolume == null ||
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

  ScopeMembership? _documentMembership(
    MediaCandidate candidate,
    AuthorizedFolderScope scope,
  ) {
    final candidateUri = candidate.documentUri;
    if (candidateUri == null ||
        candidateUri.authority != scope.treeUri.authority) {
      return null;
    }
    final treeId = _idAfter(scope.treeUri, 'tree') ?? _clean(scope.documentId);
    final documentId = _idAfter(candidateUri, 'document');
    if (treeId == null || documentId == null) return ScopeMembership.ambiguous;
    return documentId == treeId || documentId.startsWith('$treeId/')
        ? ScopeMembership.inside
        : ScopeMembership.outside;
  }

  String? _idAfter(Uri uri, String marker) {
    final index = uri.pathSegments.indexOf(marker);
    return index >= 0 && index + 1 < uri.pathSegments.length
        ? _clean(uri.pathSegments[index + 1])
        : null;
  }

  String? _normalizePath(String? value) {
    final clean = _clean(value)?.replaceAll('\\', '/');
    if (clean == null) return null;
    return clean.replaceAll(RegExp(r'/+$'), '').toLowerCase();
  }

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
