import '../../data/trash_discovery/trash_discovery_models.dart';
import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../source_recovery/verified_source_recovery_models.dart';
import '../source_recovery/verified_source_recovery_pipeline.dart';
import 'scoped_storage_recovery_models.dart';
import 'storage_scope_models.dart';

class ScopedStorageRecoveryPipeline {
  const ScopedStorageRecoveryPipeline({
    required this.sourcePipeline,
    this.scopeMatcher = const FolderScopeMatcher(),
  });

  final VerifiedSourceRecoveryPipeline sourcePipeline;
  final FolderScopeMatcher scopeMatcher;

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

  Future<ScopedStorageRecoveryResult> getSelectedFolderPage({
    required AuthorizedFolderScope? scope,
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) async {
    if (scope == null) {
      return const ScopedStorageRecoveryResult(
        capability: ScopedRecoveryCapability.folderSelectionRequired,
      );
    }
    if (scope.grantState == FolderGrantState.permissionGrantLost) {
      return ScopedStorageRecoveryResult(
        capability: ScopedRecoveryCapability.permissionGrantLost,
        scope: scope,
      );
    }
    if (scope.grantState == FolderGrantState.accessUnavailable) {
      return ScopedStorageRecoveryResult(
        capability: ScopedRecoveryCapability.scopeAccessUnavailable,
        scope: scope,
      );
    }
    if (scope.volume == null || scope.relativePathPrefix == null) {
      return ScopedStorageRecoveryResult(
        capability:
            ScopedRecoveryCapability.unsupportedDeletedDiscoveryForScope,
        scope: scope,
      );
    }

    final result = await sourcePipeline.trashDiscovery.getVerifiedTrashPage(
      request,
    );
    return switch (result) {
      TrashDiscoveryUnsupported unsupported => ScopedStorageRecoveryResult(
        capability: ScopedRecoveryCapability.unsupportedPlatformCapability,
        scope: scope,
        message: unsupported.androidApiLevel == null
            ? null
            : 'Unavailable on Android ${unsupported.androidApiLevel}.',
      ),
      TrashDiscoveryFailureResult failure => ScopedStorageRecoveryResult(
        capability: switch (failure.failure.code) {
          TrashDiscoveryFailureCode.mediaAccessUnavailable ||
          TrashDiscoveryFailureCode.securityDenied =>
            ScopedRecoveryCapability.scopeAccessUnavailable,
          _ => ScopedRecoveryCapability.platformFailure,
        },
        scope: scope,
        message: failure.failure.message,
      ),
      TrashDiscoverySuccess success => processSelectedFolderCandidates(
        scope: scope,
        candidates: success.page.items.map(
          sourcePipeline.candidateFromTrashItem,
        ),
        existingMediaIndex: existingMediaIndex,
        androidApiLevel: androidApiLevel,
        nextAfterMediaStoreId: success.page.nextAfterMediaStoreId,
        nextContinuationToken: success.page.nextContinuationToken,
        scannedVolumeName: success.page.scannedVolumeName,
      ),
    };
  }

  ScopedStorageRecoveryResult processSelectedFolderCandidates({
    required AuthorizedFolderScope scope,
    required Iterable<MediaCandidate> candidates,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
    int? nextAfterMediaStoreId,
    String? nextContinuationToken,
    String? scannedVolumeName,
  }) {
    final inScope = candidates
        .where(
          (candidate) =>
              scopeMatcher.evaluate(candidate, scope) == ScopeMembership.inside,
        )
        .map((candidate) => candidate.withSource(MediaSource.customFolder));
    final success = sourcePipeline.processCandidates(
      source: MediaSource.customFolder,
      candidates: inScope,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
      nextAfterMediaStoreId: nextAfterMediaStoreId,
      nextContinuationToken: nextContinuationToken,
      scannedVolumeName: scannedVolumeName,
    );
    return ScopedStorageRecoveryResult(
      capability: success.items.isEmpty
          ? ScopedRecoveryCapability.validEmptyResult
          : ScopedRecoveryCapability.verifiedRecoveryAvailable,
      items: success.items,
      scope: scope,
      nextAfterMediaStoreId: success.nextAfterMediaStoreId,
      nextContinuationToken: success.nextContinuationToken,
      scannedVolumeName: success.scannedVolumeName,
    );
  }

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
