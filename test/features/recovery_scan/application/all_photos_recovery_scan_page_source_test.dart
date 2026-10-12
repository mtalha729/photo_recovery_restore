import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/all_photos_recovery_scan_page_source.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_controller.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_models.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_page_source.dart';

void main() {
  test(
    'runs each standard photo source and preserves source identities',
    () async {
      final camera = _Source(MediaSource.cameraGallery, 'camera');
      final screenshots = _Source(MediaSource.screenshots, 'screenshots');
      final downloads = _Source(MediaSource.downloadsSavedMedia, 'downloads');
      final messaging = _Source(MediaSource.messagingSharedMedia, 'messaging');
      final pageSource = AllPhotosRecoveryScanPageSource(
        sources: [camera, screenshots, downloads, messaging],
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: pageSource,
      );

      await controller.start();

      expect(camera.requestedSources, [RecoveryScanSource.cameraGallery]);
      expect(screenshots.requestedSources, [RecoveryScanSource.screenshots]);
      expect(downloads.requestedSources, [RecoveryScanSource.downloads]);
      expect(messaging.requestedSources, [RecoveryScanSource.messaging]);
      expect(controller.state.verifiedItems.map((item) => item.source), [
        MediaSource.cameraGallery,
        MediaSource.screenshots,
        MediaSource.downloadsSavedMedia,
        MediaSource.messagingSharedMedia,
      ]);
    },
  );

  test('deduplicates copy records returned by source pipelines', () async {
    final sharedCopy = _candidate(
      'shared-copy',
      MediaSource.unknown,
      RecoveryClassification.possibleCopy,
    );
    final pageSource = AllPhotosRecoveryScanPageSource(
      sources: [
        _Source(MediaSource.cameraGallery, 'camera', copy: sharedCopy),
        _Source(MediaSource.screenshots, 'screenshots', copy: sharedCopy),
        _Source(MediaSource.downloadsSavedMedia, 'downloads'),
        _Source(MediaSource.messagingSharedMedia, 'messaging'),
      ],
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: pageSource,
    );

    await controller.start();

    expect(controller.state.possibleCopies.map((item) => item.id), [
      'shared-copy',
    ]);
  });
}

class _Source implements RecoveryScanPageSource, PossibleCopiesAwarePageSource {
  _Source(this.mediaSource, this.id, {this.copy});

  final MediaSource mediaSource;
  final String id;
  final MediaCandidate? copy;
  final List<RecoveryScanSource> requestedSources = [];

  @override
  List<MediaCandidate> get possibleCopies => copy == null ? const [] : [copy!];

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    requestedSources.add(source);
    final candidate = _candidate(
      id,
      mediaSource,
      RecoveryClassification.verifiedDeleted,
    );
    return VerifiedSourceRecoverySuccess(
      source: mediaSource,
      items: [
        VerifiedSourceRecoveryItem(
          candidate: candidate,
          classificationDecision: RecoveryClassificationDecision(
            classification: RecoveryClassification.verifiedDeleted,
            reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
          ),
          restoreEligibility: const SystemTrashRestoreEligibility(
            reason: SystemTrashRestoreEligibilityReason.eligible,
          ),
        ),
      ],
      diagnostics: const VerifiedSourceRecoveryDiagnostics(
        examinedCount: 1,
        excludedExistingCount: 0,
        filteredOtherSourceCount: 0,
        filteredIneligibleCount: 0,
      ),
    );
  }
}

MediaCandidate _candidate(
  String id,
  MediaSource source,
  RecoveryClassification classification,
) => MediaCandidate(
  id: id,
  source: source,
  displayName: '$id.jpg',
  classification: classification,
  deletionEvidence: DeletionEvidence(
    reasons: const [DeletionEvidenceReason.systemTrashRecord],
  ),
  restoreCapability: RestoreCapability.originalFullQuality,
  recoveryQuality: RecoveryQuality.original,
);
