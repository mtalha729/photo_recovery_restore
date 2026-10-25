import '../../recovery/application/camera_gallery_recovery/camera_gallery_recovery_models.dart';
import '../../recovery/application/camera_gallery_recovery/camera_gallery_recovery_pipeline.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_index.dart';
import '../../recovery/application/messaging_recovery/messaging_recovery_pipeline.dart';
import '../../recovery/application/scoped_storage_recovery/scoped_storage_recovery_models.dart';
import '../../recovery/application/scoped_storage_recovery/scoped_storage_recovery_pipeline.dart';
import '../../recovery/application/screenshots_downloads_recovery/screenshots_downloads_recovery_pipeline.dart';
import '../../recovery/application/scan_runtime/scan_cancellation.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_models.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
import '../../recovery/data/trash_discovery/trash_discovery_models.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'authorized_folder_scan_models.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/media_source.dart';
import 'recovery_scan_models.dart';

abstract interface class RecoveryScanPageSource {
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  );
}

abstract interface class CancellationAwarePageSource {
  set cancellationToken(ScanCancellationToken? value);
}

abstract interface class ActiveScanCancellationAwarePageSource {
  Future<void> cancelActiveScan();
}

abstract interface class ScanSessionLifecyclePageSource {
  void beginScanSession();
  void endScanSession();
}

abstract interface class LimitedAccessAwarePageSource {
  bool get isLimitedAccess;
}

abstract interface class PossibleCopiesAwarePageSource {
  List<MediaCandidate> get possibleCopies;
}

abstract interface class CurrentPhotosAwarePageSource {
  List<MediaCandidate> get currentPhotos;
  set onCurrentPhotosProgress(void Function(List<MediaCandidate>)? callback);
}

abstract interface class AuthorizedFolderScanAwarePageSource {
  bool get canScanAuthorizedFolder;

  Future<AuthorizedFolderScanOutcome> scanAuthorizedFolder({
    required RecoveryScanSource source,
    required void Function(AuthorizedFolderScanProgress progress) onProgress,
  });
}

abstract interface class DeepScanCapabilityAwarePageSource {
  DeepStorageCapabilityStatus get deepCapabilityStatus;
  String? get deepCapabilityMessage;
  bool get canRequestDeepStorageAccess;
  Future<void> openDeepScanSettings();
  Future<bool> refreshDeepScanCapability();
}

class UnavailableRecoveryScanPageSource implements RecoveryScanPageSource {
  const UnavailableRecoveryScanPageSource();

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => VerifiedSourceRecoveryFailure(
    source: source.mediaSource,
    code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
    message: 'Media access is not available yet.',
  );
}

class ExistingRecoveryPipelinePageSource implements RecoveryScanPageSource {
  const ExistingRecoveryPipelinePageSource({
    required this.cameraGallery,
    required this.messaging,
    required this.screenshotsDownloads,
    required this.scopedStorage,
    required this.allPhotos,
    required this.existingMediaIndex,
    required this.androidApiLevel,
  });

  final CameraGalleryRecoveryPipeline cameraGallery;
  final MessagingRecoveryPipeline messaging;
  final ScreenshotsDownloadsRecoveryPipeline screenshotsDownloads;
  final ScopedStorageRecoveryPipeline scopedStorage;
  final VerifiedSourceRecoveryPipeline allPhotos;
  final ExistingMediaIndex existingMediaIndex;
  final int androidApiLevel;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => switch (source) {
    RecoveryScanSource.allPhotos => allPhotos.getPage(
      source: MediaSource.unknown,
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    ),
    RecoveryScanSource.cameraGallery => _cameraPage(request),
    RecoveryScanSource.messaging => messaging.recoverMessaging(
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    ),
    RecoveryScanSource.screenshots => screenshotsDownloads.recoverScreenshots(
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    ),
    RecoveryScanSource.downloads => screenshotsDownloads.recoverDownloads(
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    ),
    RecoveryScanSource.sdCard => _scopedPage(
      scopedStorage.getSdCardPage(
        request: request,
        existingMediaIndex: existingMediaIndex,
        androidApiLevel: androidApiLevel,
      ),
      MediaSource.sdCard,
    ),
  };

  Future<VerifiedSourceRecoveryResult> _cameraPage(
    TrashDiscoveryPageRequest request,
  ) async {
    final result = await cameraGallery.getPage(
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    );
    return switch (result) {
      CameraGalleryRecoverySuccess success => VerifiedSourceRecoverySuccess(
        source: MediaSource.cameraGallery,
        items: [
          for (final item in success.items)
            VerifiedSourceRecoveryItem(
              candidate: item.candidate,
              classificationDecision: item.classificationDecision,
              restoreEligibility: item.restoreEligibility,
            ),
        ],
        diagnostics: VerifiedSourceRecoveryDiagnostics(
          examinedCount: success.diagnostics.examinedCount,
          excludedExistingCount: success.diagnostics.excludedExistingCount,
          filteredOtherSourceCount:
              success.diagnostics.filteredOtherSourceCount,
          filteredIneligibleCount: success.diagnostics.filteredIneligibleCount,
        ),
        nextAfterMediaStoreId: success.nextAfterMediaStoreId,
        nextContinuationToken: success.nextContinuationToken,
        scannedVolumeName: success.scannedVolumeName,
      ),
      CameraGalleryRecoveryUnsupported unsupported =>
        VerifiedSourceRecoveryUnsupported(
          source: MediaSource.cameraGallery,
          androidApiLevel: unsupported.androidApiLevel,
        ),
      CameraGalleryRecoveryFailure failure => VerifiedSourceRecoveryFailure(
        source: MediaSource.cameraGallery,
        code: failure.code == CameraGalleryRecoveryFailureCode.accessUnavailable
            ? VerifiedSourceRecoveryFailureCode.accessUnavailable
            : VerifiedSourceRecoveryFailureCode.platformFailure,
        message: failure.message,
      ),
    };
  }

  Future<VerifiedSourceRecoveryResult> _scopedPage(
    Future<ScopedStorageRecoveryResult> pending,
    MediaSource source,
  ) async {
    final result = await pending;
    return switch (result.capability) {
      ScopedRecoveryCapability.verifiedRecoveryAvailable ||
      ScopedRecoveryCapability.validEmptyResult =>
        VerifiedSourceRecoverySuccess(
          source: source,
          items: result.items,
          diagnostics: const VerifiedSourceRecoveryDiagnostics(
            examinedCount: 0,
            excludedExistingCount: 0,
            filteredOtherSourceCount: 0,
            filteredIneligibleCount: 0,
          ),
          nextAfterMediaStoreId: result.nextAfterMediaStoreId,
          nextContinuationToken: result.nextContinuationToken,
          scannedVolumeName: result.scannedVolumeName,
        ),
      ScopedRecoveryCapability.unsupportedPlatformCapability =>
        VerifiedSourceRecoveryUnsupported(source: source),
      ScopedRecoveryCapability.scopeAccessUnavailable =>
        VerifiedSourceRecoveryFailure(
          source: source,
          code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
          message: result.message,
        ),
      ScopedRecoveryCapability.platformFailure => VerifiedSourceRecoveryFailure(
        source: source,
        code: VerifiedSourceRecoveryFailureCode.platformFailure,
        message: result.message,
      ),
    };
  }
}
