import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_controller.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_models.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_page_source.dart';

void main() {
  test('each selected source is passed unchanged to the page source', () async {
    for (final source in RecoveryScanSource.values) {
      final pageSource = _PageSource((selected, _) {
        expect(selected, source);
        return _success(source.mediaSource, const []);
      });
      final controller = RecoveryScanController(
        source: source,
        pageSource: pageSource,
      );
      await controller.start();
      expect(pageSource.calls, 1);
    }
  });

  test(
    'other domains, existing media, and possible copies never enter results',
    () async {
      final source = _PageSource(
        (_, _) => _success(MediaSource.cameraGallery, [
          _item(
            _candidate(
              'verified',
              MediaSource.cameraGallery,
              RecoveryClassification.verifiedDeleted,
            ),
          ),
          _item(
            _candidate(
              'other',
              MediaSource.messagingSharedMedia,
              RecoveryClassification.verifiedDeleted,
            ),
          ),
          _item(
            _candidate(
              'existing',
              MediaSource.cameraGallery,
              RecoveryClassification.existingMedia,
            ),
          ),
          _item(
            _candidate(
              'copy',
              MediaSource.cameraGallery,
              RecoveryClassification.possibleCopy,
            ),
          ),
        ]),
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: source,
      );
      await controller.start();

      expect(controller.state.verifiedItems.map((item) => item.id), [
        'verified',
      ]);
      expect(controller.state.status, RecoveryScanViewStatus.complete);
    },
  );

  test('empty, unsupported, and access failures stay distinct', () async {
    final empty = RecoveryScanController(
      source: RecoveryScanSource.messaging,
      pageSource: _PageSource(
        (_, _) => _success(MediaSource.messagingSharedMedia, const []),
      ),
    );
    await empty.start();
    expect(empty.state.status, RecoveryScanViewStatus.empty);

    final unsupported = RecoveryScanController(
      source: RecoveryScanSource.downloads,
      pageSource: _PageSource(
        (_, _) => const VerifiedSourceRecoveryUnsupported(
          source: MediaSource.downloadsSavedMedia,
        ),
      ),
    );
    await unsupported.start();
    expect(unsupported.state.status, RecoveryScanViewStatus.unsupported);

    final access = RecoveryScanController(
      source: RecoveryScanSource.screenshots,
      pageSource: _PageSource(
        (_, _) => const VerifiedSourceRecoveryFailure(
          source: MediaSource.screenshots,
          code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
        ),
      ),
    );
    await access.start();
    expect(access.state.status, RecoveryScanViewStatus.accessUnavailable);
  });

  test('duplicate platform records do not inflate verified results', () async {
    final repeated = _item(
      _candidate(
        'same-volume-id',
        MediaSource.cameraGallery,
        RecoveryClassification.verifiedDeleted,
      ),
    );
    final source = _PageSource((_, request) {
      if (request.continuationToken == null) {
        return VerifiedSourceRecoverySuccess(
          source: MediaSource.cameraGallery,
          items: [repeated],
          diagnostics: const VerifiedSourceRecoveryDiagnostics(
            examinedCount: 1,
            excludedExistingCount: 0,
            filteredOtherSourceCount: 0,
            filteredIneligibleCount: 0,
          ),
          nextContinuationToken: 'next-volume',
        );
      }
      return VerifiedSourceRecoverySuccess(
        source: MediaSource.cameraGallery,
        items: [repeated],
        diagnostics: const VerifiedSourceRecoveryDiagnostics(
          examinedCount: 1,
          excludedExistingCount: 0,
          filteredOtherSourceCount: 0,
          filteredIneligibleCount: 0,
        ),
      );
    });
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: source,
    );

    await controller.start();

    expect(controller.state.verifiedItems, hasLength(1));
    expect(controller.state.progress.discoveredVerifiedCount, 1);
  });
  test('cancellation never reports a completed scan', () async {
    final pending = Completer<VerifiedSourceRecoveryResult>();
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: _PageSource((_, _) => pending.future),
    );
    final scan = controller.start();
    controller.cancel();
    expect(controller.state.status, RecoveryScanViewStatus.cancelling);
    pending.complete(_success(MediaSource.cameraGallery, const []));
    await scan;
    expect(controller.state.status, RecoveryScanViewStatus.cancelled);
  });

  test(
    'deep access requirement is explicit and settings are user-triggered',
    () async {
      final source = _DeepAccessPageSource();
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: source,
      );
      await controller.start();
      expect(
        controller.state.status,
        RecoveryScanViewStatus.deepAccessRequired,
      );
      expect(source.settingsCalls, 0);
      await controller.openDeepScanSettings();
      expect(source.settingsCalls, 1);
    },
  );

  test(
    'zero verified and nonzero possible copies completes to results',
    () async {
      final copy = _candidate(
        'deep-copy',
        MediaSource.cameraGallery,
        RecoveryClassification.possibleCopy,
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: _CopiesPageSource(copy),
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.complete);
      expect(controller.state.verifiedItems, isEmpty);
      expect(controller.state.possibleCopies, [copy]);
    },
  );

  test('each completed scan starts and ends an isolated provider session', () async {
    final source = _LifecyclePageSource();
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: source,
    );

    await controller.start();
    expect(source.startedSessions, 1);
    expect(source.endedSessions, 1);
    expect(controller.state.verifiedItems.single.id, 'scan-1');

    await controller.start();
    expect(source.startedSessions, 2);
    expect(source.endedSessions, 2);
    expect(source.loadCalls, 2);
    expect(controller.state.verifiedItems.single.id, 'scan-2');
  });

  test('page source exception terminates as failed exactly once', () async {
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: _PageSource((_, _) => throw StateError('native failure')),
    );
    var terminalNotifications = 0;
    controller.addListener(() {
      if (controller.state.status == RecoveryScanViewStatus.failure) {
        terminalNotifications++;
      }
    });

    await controller.start();

    expect(controller.state.status, RecoveryScanViewStatus.failure);
    expect(terminalNotifications, 1);
  });

  test(
    'last non-empty page preserves results and stops progress state',
    () async {
      final recovered = _candidate(
        'last-page',
        MediaSource.cameraGallery,
        RecoveryClassification.verifiedDeleted,
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: _PageSource(
          (_, _) => _success(MediaSource.cameraGallery, [_item(recovered)]),
        ),
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.complete);
      expect(controller.state.verifiedItems, [recovered]);
      expect(controller.state.status, isNot(RecoveryScanViewStatus.running));
    },
  );
}

class _LifecyclePageSource implements RecoveryScanPageSource, ScanSessionLifecyclePageSource {
  int startedSessions = 0;
  int endedSessions = 0;
  int loadCalls = 0;

  @override
  void beginScanSession() => startedSessions++;

  @override
  void endScanSession() => endedSessions++;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    loadCalls++;
    final candidate = _candidate(
      'scan-$startedSessions',
      source.mediaSource,
      RecoveryClassification.verifiedDeleted,
    );
    return _success(source.mediaSource, [_item(candidate)]);
  }
}

class _CopiesPageSource
    implements RecoveryScanPageSource, PossibleCopiesAwarePageSource {
  _CopiesPageSource(this.copy);
  final MediaCandidate copy;

  @override
  List<MediaCandidate> get possibleCopies => [copy];

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => _success(source.mediaSource, const []);
}

class _DeepAccessPageSource
    implements RecoveryScanPageSource, DeepScanCapabilityAwarePageSource {
  int settingsCalls = 0;
  @override
  DeepStorageCapabilityStatus get deepCapabilityStatus =>
      DeepStorageCapabilityStatus.accessRequired;
  @override
  String? get deepCapabilityMessage => 'Enable Deep Scan.';
  @override
  Future<void> openDeepScanSettings() async => settingsCalls++;
  @override
  Future<bool> refreshDeepScanCapability() async => false;
  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => const VerifiedSourceRecoveryFailure(
    source: MediaSource.cameraGallery,
    code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
    message: 'Enable Deep Scan.',
  );
}

class _PageSource implements RecoveryScanPageSource {
  _PageSource(this.handler);
  final FutureOr<VerifiedSourceRecoveryResult> Function(
    RecoveryScanSource,
    TrashDiscoveryPageRequest,
  )
  handler;
  int calls = 0;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    calls++;
    return handler(source, request);
  }
}

VerifiedSourceRecoverySuccess _success(
  MediaSource source,
  List<VerifiedSourceRecoveryItem> items,
) => VerifiedSourceRecoverySuccess(
  source: source,
  items: items,
  diagnostics: VerifiedSourceRecoveryDiagnostics(
    examinedCount: items.length,
    excludedExistingCount: 0,
    filteredOtherSourceCount: 0,
    filteredIneligibleCount: 0,
  ),
);

VerifiedSourceRecoveryItem _item(MediaCandidate candidate) =>
    VerifiedSourceRecoveryItem(
      candidate: candidate,
      classificationDecision: RecoveryClassificationDecision(
        classification: candidate.classification,
        reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
      ),
      restoreEligibility: const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.eligible,
      ),
    );

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
