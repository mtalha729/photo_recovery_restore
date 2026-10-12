import '../source_recovery/verified_source_recovery_models.dart';
import 'storage_scope_models.dart';

enum ScopedRecoveryCapability {
  verifiedRecoveryAvailable,
  validEmptyResult,
  folderSelectionRequired,
  scopeAccessUnavailable,
  unsupportedDeletedDiscoveryForScope,
  permissionGrantLost,
  unsupportedPlatformCapability,
  platformFailure,
}

class ScopedStorageRecoveryResult {
  const ScopedStorageRecoveryResult({
    required this.capability,
    this.items = const [],
    this.scope,
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
    this.message,
  });

  final ScopedRecoveryCapability capability;
  final List<VerifiedSourceRecoveryItem> items;
  final AuthorizedFolderScope? scope;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;
  final String? message;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}
