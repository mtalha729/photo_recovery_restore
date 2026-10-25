import '../../data/trash_discovery/trash_discovery.dart';
import '../../data/trash_discovery/trash_discovery_models.dart';
import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_exclusion_models.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../recovery_evidence_classifier/recovery_evidence_classifier.dart';
import '../restore/system_trash_restore_models.dart';
import '../restore/system_trash_restore_policy.dart';
import '../source_resolution/media_source_resolver.dart';
import 'verified_source_recovery_models.dart';

class VerifiedSourceRecoveryPipeline {
  VerifiedSourceRecoveryPipeline({
    required this.trashDiscovery,
    this.sourceResolver = const MediaSourceResolver(),
    this.exclusionEngine = const ExistingMediaExclusionEngine(),
    this.classifier = const RecoveryEvidenceClassifier(),
    this.restorePolicy = const SystemTrashRestorePolicy(),
  });

  final TrashDiscovery trashDiscovery;
  final MediaSourceResolver sourceResolver;
  final ExistingMediaExclusionEngine exclusionEngine;
  final RecoveryEvidenceClassifier classifier;
  final SystemTrashRestorePolicy restorePolicy;

  Future<VerifiedSourceRecoveryResult> getPage({
    required MediaSource source,
    required TrashDiscoveryPageRequest request,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
  }) async {
    final trashResult = await trashDiscovery.getVerifiedTrashPage(request);
    return switch (trashResult) {
      TrashDiscoveryUnsupported unsupported =>
        VerifiedSourceRecoveryUnsupported(
          source: source,
          androidApiLevel: unsupported.androidApiLevel,
        ),
      TrashDiscoveryFailureResult failure => VerifiedSourceRecoveryFailure(
        source: source,
        code: _failureCode(failure.failure.code),
        message: failure.failure.message,
      ),
      TrashDiscoverySuccess success => processCandidates(
        source: source,
        candidates: success.page.items.map(candidateFromTrashItem),
        existingMediaIndex: existingMediaIndex,
        androidApiLevel: androidApiLevel,
        nextAfterMediaStoreId: success.page.nextAfterMediaStoreId,
        nextContinuationToken: success.page.nextContinuationToken,
        scannedVolumeName: success.page.scannedVolumeName,
      ),
    };
  }

  VerifiedSourceRecoverySuccess processCandidates({
    required MediaSource source,
    required Iterable<MediaCandidate> candidates,
    required ExistingMediaIndex existingMediaIndex,
    required int androidApiLevel,
    int? nextAfterMediaStoreId,
    String? nextContinuationToken,
    String? scannedVolumeName,
  }) {
    final results = <VerifiedSourceRecoveryItem>[];
    var examinedCount = 0;
    var excludedExistingCount = 0;
    var filteredOtherSourceCount = 0;
    var filteredIneligibleCount = 0;

    for (final candidate in candidates) {
      examinedCount++;
      if (source != MediaSource.unknown && candidate.source != source) {
        filteredOtherSourceCount++;
        continue;
      }

      final exclusion = exclusionEngine.evaluate(candidate, existingMediaIndex);
      final decision = classifier.classify(
        candidate: candidate,
        existingMediaDecision: exclusion,
      );
      if (exclusion.type == ExistingMediaDecisionType.definitelyExisting) {
        excludedExistingCount++;
        continue;
      }
      if (!decision.isEligibleForVerifiedDeletedResults ||
          decision.classification == RecoveryClassification.possibleCopy ||
          decision.classification == RecoveryClassification.unclassified) {
        filteredIneligibleCount++;
        continue;
      }

      final restoreRequest = SystemTrashRestoreRequest(
        requestId: candidate.id,
        candidate: candidate,
        classificationDecision: decision,
      );
      results.add(
        VerifiedSourceRecoveryItem(
          candidate: candidate,
          classificationDecision: decision,
          restoreEligibility: restorePolicy.evaluate(
            restoreRequest,
            androidApiLevel: androidApiLevel,
          ),
        ),
      );
    }

    return VerifiedSourceRecoverySuccess(
      source: source,
      items: List.unmodifiable(results),
      diagnostics: VerifiedSourceRecoveryDiagnostics(
        examinedCount: examinedCount,
        excludedExistingCount: excludedExistingCount,
        filteredOtherSourceCount: filteredOtherSourceCount,
        filteredIneligibleCount: filteredIneligibleCount,
      ),
      nextAfterMediaStoreId: nextAfterMediaStoreId,
      nextContinuationToken: nextContinuationToken,
      scannedVolumeName: scannedVolumeName,
    );
  }

  MediaCandidate candidateFromTrashItem(VerifiedTrashItem item) {
    final metadata = item.metadata;
    return MediaCandidate(
      id: 'mediastore:${metadata.storageVolumeName ?? 'unknown'}:${metadata.mediaStoreId}',
      source: sourceResolver.resolve(metadata),
      contentUri: metadata.contentUri,
      mediaStoreId: metadata.mediaStoreId,
      displayName: metadata.displayName,
      mimeType: metadata.mimeType,
      relativeLocation: metadata.relativePath,
      bucketName: metadata.bucketName,
      storageVolumeName: metadata.storageVolumeName,
      isRemovableStorage: metadata.isRemovableStorage,
      byteSize: metadata.byteSize,
      width: metadata.width,
      height: metadata.height,
      createdAt: metadata.dateAdded,
      modifiedAt: metadata.dateModified,
      takenAt: metadata.dateTaken,
      classification: RecoveryClassification.unclassified,
      deletionEvidence: item.deletionEvidence,
      restoreCapability: RestoreCapability.originalFullQuality,
      recoveryQuality: item.initialBytesReadable
          ? RecoveryQuality.original
          : RecoveryQuality.metadataOnly,
    );
  }

  VerifiedSourceRecoveryFailureCode _failureCode(
    TrashDiscoveryFailureCode code,
  ) {
    return switch (code) {
      TrashDiscoveryFailureCode.mediaAccessUnavailable ||
      TrashDiscoveryFailureCode.securityDenied =>
        VerifiedSourceRecoveryFailureCode.accessUnavailable,
      TrashDiscoveryFailureCode.platformFailure ||
      TrashDiscoveryFailureCode.malformedPlatformResponse =>
        VerifiedSourceRecoveryFailureCode.platformFailure,
    };
  }
}
