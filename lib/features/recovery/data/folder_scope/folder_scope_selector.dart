import '../../application/scoped_storage_recovery/storage_scope_models.dart';

enum FolderScopeSelectionStatus {
  selected,
  cancelled,
  restrictedLocation,
  permissionGrantLost,
  accessUnavailable,
  operationInProgress,
  platformFailure,
}

class FolderScopeSelectionResult {
  const FolderScopeSelectionResult({
    required this.status,
    this.scope,
    this.message,
  });

  final FolderScopeSelectionStatus status;
  final AuthorizedFolderScope? scope;
  final String? message;
}

abstract interface class FolderScopeSelector {
  Future<FolderScopeSelectionResult> selectFolder();

  Future<FolderScopeSelectionResult> checkGrant(AuthorizedFolderScope scope);
}
