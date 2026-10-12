import '../../data/trash_discovery/trash_discovery.dart';
import '../../data/trash_discovery/trash_discovery_models.dart';
import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../recovery_evidence_classifier/recovery_evidence_classifier.dart';
import '../restore/system_trash_restore_policy.dart';
import '../source_recovery/verified_source_recovery_models.dart';
import '../source_recovery/verified_source_recovery_pipeline.dart';
import '../source_resolution/media_source_resolver.dart';
import 'camera_gallery_recovery_models.dart';

class CameraGalleryRecoveryPipeline {
  CameraGalleryRecoveryPipeline({
    required TrashDiscovery trashDiscovery,
    MediaSourceResolver sourceResolver = const MediaSourceResolver(),
    ExistingMediaExclusionEngine exclusionEngine =
        const ExistingMediaExclusionEngine(),
    RecoveryEvidenceClassifier classifier = const RecoveryEvidenceClassifier(),
    SystemTrashRestorePolicy restorePolicy = const SystemTrashRestorePolicy(),
  }) : _pipeline = VerifiedSourceRecoveryPipeline(
         trashDiscovery: trashDiscovery,
         sourceResolver: sourceResolver,
         exclusionEngine: exclusionEngine,
         classifier: classifier,
         restorePolicy: restorePolicy,
       );

  final VerifiedSourceRecoveryPipeline _pipeline;

  Future<CameraGalleryRecoveryResult> getPage({
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) async {
    final result = await _pipeline.getPage(
      source: MediaSource.cameraGallery,
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    );
    return _cameraGalleryResult(result);
  }

  CameraGalleryRecoverySuccess processCandidates({
    required Iterable<MediaCandidate> candidates,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
    int? nextAfterMediaStoreId,
    String? nextContinuationToken,
    String? scannedVolumeName,
  }) {
    final result = _pipeline.processCandidates(
      source: MediaSource.cameraGallery,
      candidates: candidates,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
      nextAfterMediaStoreId: nextAfterMediaStoreId,
      nextContinuationToken: nextContinuationToken,
      scannedVolumeName: scannedVolumeName,
    );
    return _success(result);
  }

  CameraGalleryRecoveryResult _cameraGalleryResult(
    VerifiedSourceRecoveryResult result,
  ) {
    return switch (result) {
      VerifiedSourceRecoverySuccess success => _success(success),
      VerifiedSourceRecoveryUnsupported unsupported =>
        CameraGalleryRecoveryUnsupported(
          androidApiLevel: unsupported.androidApiLevel,
        ),
      VerifiedSourceRecoveryFailure failure => CameraGalleryRecoveryFailure(
        code:
            failure.code == VerifiedSourceRecoveryFailureCode.accessUnavailable
            ? CameraGalleryRecoveryFailureCode.accessUnavailable
            : CameraGalleryRecoveryFailureCode.platformFailure,
        message: failure.message,
      ),
    };
  }

  CameraGalleryRecoverySuccess _success(VerifiedSourceRecoverySuccess success) {
    return CameraGalleryRecoverySuccess(
      items: List.unmodifiable(
        success.items.map(
          (item) => CameraGalleryRecoveryItem(
            candidate: item.candidate,
            classificationDecision: item.classificationDecision,
            restoreEligibility: item.restoreEligibility,
          ),
        ),
      ),
      diagnostics: CameraGalleryRecoveryDiagnostics(
        examinedCount: success.diagnostics.examinedCount,
        excludedExistingCount: success.diagnostics.excludedExistingCount,
        filteredOtherSourceCount: success.diagnostics.filteredOtherSourceCount,
        filteredIneligibleCount: success.diagnostics.filteredIneligibleCount,
      ),
      nextAfterMediaStoreId: success.nextAfterMediaStoreId,
      nextContinuationToken: success.nextContinuationToken,
      scannedVolumeName: success.scannedVolumeName,
    );
  }
}
