import '../../data/trash_discovery/trash_discovery.dart';
import '../../data/trash_discovery/trash_discovery_models.dart';
import '../../domain/media_source.dart';
import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../recovery_evidence_classifier/recovery_evidence_classifier.dart';
import '../restore/system_trash_restore_policy.dart';
import '../source_recovery/verified_source_recovery_models.dart';
import '../source_recovery/verified_source_recovery_pipeline.dart';
import '../source_resolution/media_source_resolver.dart';

class ScreenshotsDownloadsRecoveryPipeline {
  ScreenshotsDownloadsRecoveryPipeline({
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

  Future<VerifiedSourceRecoveryResult> recoverScreenshots({
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) {
    return _pipeline.getPage(
      source: MediaSource.screenshots,
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    );
  }

  Future<VerifiedSourceRecoveryResult> recoverDownloads({
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) {
    return _pipeline.getPage(
      source: MediaSource.downloadsSavedMedia,
      request: request,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    );
  }
}
