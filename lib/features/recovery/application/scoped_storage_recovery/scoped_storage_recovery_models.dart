import '../source_recovery/verified_source_recovery_models.dart';

enum ScopedRecoveryCapability {
  verifiedRecoveryAvailable,
  validEmptyResult,
  scopeAccessUnavailable,
  unsupportedPlatformCapability,
  platformFailure,
}

class ScopedStorageRecoveryResult {
  const ScopedStorageRecoveryResult({
    required this.capability,
    this.items = const [],
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
    this.message,
  });

  final ScopedRecoveryCapability capability;
  final List<VerifiedSourceRecoveryItem> items;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;
  final String? message;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}
