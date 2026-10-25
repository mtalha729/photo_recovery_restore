import '../../data/trash_discovery/trash_discovery_models.dart';
import '../../domain/media_source.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../source_recovery/verified_source_recovery_models.dart';
import '../source_recovery/verified_source_recovery_pipeline.dart';
import 'scoped_storage_recovery_models.dart';

class ScopedStorageRecoveryPipeline {
  const ScopedStorageRecoveryPipeline({required this.sourcePipeline});

  final VerifiedSourceRecoveryPipeline sourcePipeline;

  Future<ScopedStorageRecoveryResult> getSdCardPage({
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) async => _mapSharedResult(
    await sourcePipeline.getPage(
      source: MediaSource.sdCard,
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    ),
  );

  ScopedStorageRecoveryResult _mapSharedResult(
    VerifiedSourceRecoveryResult result,
  ) => switch (result) {
    VerifiedSourceRecoverySuccess success => ScopedStorageRecoveryResult(
      capability: success.items.isEmpty
          ? ScopedRecoveryCapability.validEmptyResult
          : ScopedRecoveryCapability.verifiedRecoveryAvailable,
      items: success.items,
      nextAfterMediaStoreId: success.nextAfterMediaStoreId,
      nextContinuationToken: success.nextContinuationToken,
      scannedVolumeName: success.scannedVolumeName,
    ),
    VerifiedSourceRecoveryUnsupported() => const ScopedStorageRecoveryResult(
      capability: ScopedRecoveryCapability.unsupportedPlatformCapability,
    ),
    VerifiedSourceRecoveryFailure failure => ScopedStorageRecoveryResult(
      capability:
          failure.code == VerifiedSourceRecoveryFailureCode.accessUnavailable
          ? ScopedRecoveryCapability.scopeAccessUnavailable
          : ScopedRecoveryCapability.platformFailure,
      message: failure.message,
    ),
  };
}
