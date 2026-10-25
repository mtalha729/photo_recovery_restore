import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/paginated_recovery_scanner.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/authorized_folder_scan_models.dart';
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

  test(
    'large verified result sets are capped with explicit partial coverage',
    () async {
      final results = List<VerifiedSourceRecoveryItem>.generate(
        10001,
        (index) => _item(
          _candidate(
            'large-set-$index',
            MediaSource.cameraGallery,
            RecoveryClassification.verifiedDeleted,
          ),
        ),
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: _PageSource(
          (_, _) => _success(MediaSource.cameraGallery, results),
        ),
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.partial);
      expect(controller.state.verifiedItems, hasLength(10000));
      expect(controller.state.message, contains('coverage is partial'));
    },
  );

  test('resource-limited empty scan is reported as partial coverage', () async {
    var calls = 0;
    final source = _PageSource((_, _) {
      calls++;
      return VerifiedSourceRecoverySuccess(
        source: MediaSource.cameraGallery,
        items: const [],
        diagnostics: const VerifiedSourceRecoveryDiagnostics(
          examinedCount: 0,
          excludedExistingCount: 0,
          filteredOtherSourceCount: 0,
          filteredIneligibleCount: 0,
        ),
        nextContinuationToken: 'more-remains',
      );
    });
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: source,
      scanner: const PaginatedRecoveryScanner(maximumPageCount: 1),
    );

    await controller.start();

    expect(calls, 1);
    expect(controller.state.status, RecoveryScanViewStatus.partial);
    expect(controller.state.message, contains('coverage is partial'));
  });

  test(
    'an empty 200-row page continues to later recoverable results',
    () async {
      final recovered = _candidate(
        'after-first-page',
        MediaSource.cameraGallery,
        RecoveryClassification.verifiedDeleted,
      );
      final source = _PageSource((_, request) {
        if (request.continuationToken == null) {
          return const VerifiedSourceRecoverySuccess(
            source: MediaSource.cameraGallery,
            items: [],
            diagnostics: VerifiedSourceRecoveryDiagnostics(
              examinedCount: 200,
              excludedExistingCount: 0,
              filteredOtherSourceCount: 0,
              filteredIneligibleCount: 200,
            ),
            nextContinuationToken: 'second-page',
          );
        }
        expect(request.continuationToken, 'second-page');
        return _success(MediaSource.cameraGallery, [_item(recovered)]);
      });
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: source,
      );

      await controller.start();

      expect(source.calls, 2);
      expect(controller.state.progress.processedCount, 201);
      expect(controller.state.verifiedItems, [recovered]);
      expect(controller.state.status, RecoveryScanViewStatus.complete);
    },
  );

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
  test(
    'provider failure after a valid page keeps results as partial coverage',
    () async {
      final recovered = _candidate(
        'before-provider-failure',
        MediaSource.cameraGallery,
        RecoveryClassification.verifiedDeleted,
      );
      final source = _PageSource((_, request) {
        if (request.continuationToken == null) {
          return VerifiedSourceRecoverySuccess(
            source: MediaSource.cameraGallery,
            items: [_item(recovered)],
            diagnostics: const VerifiedSourceRecoveryDiagnostics(
              examinedCount: 1,
              excludedExistingCount: 0,
              filteredOtherSourceCount: 0,
              filteredIneligibleCount: 0,
            ),
            nextContinuationToken: 'next-page',
          );
        }
        return const VerifiedSourceRecoveryFailure(
          source: MediaSource.cameraGallery,
          code: VerifiedSourceRecoveryFailureCode.platformFailure,
          message: 'The provider failed on its next page.',
        );
      });
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: source,
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.partial);
      expect(controller.state.verifiedItems, [recovered]);
      expect(controller.state.message, contains('provider failed'));
    },
  );

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
    'optional deep-scan unavailability does not mark a completed scan limited',
    () async {
      final controller = RecoveryScanController(
        source: RecoveryScanSource.cameraGallery,
        pageSource: _OptionalDeepUnavailablePageSource(),
      );

      await controller.start();

      expect(controller.state.status, RecoveryScanViewStatus.empty);
      expect(controller.state.deepCapabilityMessage, contains('not available'));
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

  test('selected-folder partial failure retains verified and streamed copy results', () async {
    final verified = _candidate(
      'verified-before-folder',
      MediaSource.cameraGallery,
      RecoveryClassification.verifiedDeleted,
    );
    final copy = _candidate(
      'folder-copy',
      MediaSource.cameraGallery,
      RecoveryClassification.possibleCopy,
    );
    final source = _AuthorizedFolderPageSource(
      canScan: true,
      initialItems: [_item(verified)],
      folderHandler: ({required source, required onProgress}) async {
        onProgress(
          AuthorizedFolderScanProgress(
            pageCandidates: [copy],
            filesExamined: 4,
            pageCount: 1,
            entriesExamined: 7,
          ),
        );
        return const AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.partialFailure,
          filesExamined: 4,
          pageCount: 1,
          candidatesFound: 1,
          message: 'Some selected-folder entries were unavailable.',
        );
      },
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: source,
    );

    await controller.start();
    expect(controller.state.verifiedItems, [verified]);
    expect(controller.canScanAuthorizedFolder, isTrue);

    await controller.scanAuthorizedFolder();

    expect(controller.state.status, RecoveryScanViewStatus.partial);
    expect(controller.state.verifiedItems, [verified]);
    expect(controller.state.possibleCopies, [copy]);
    expect(controller.state.message, contains('entries were unavailable'));
    expect(
      controller.state.deepCapabilityMessage,
      contains('not verified deletions'),
    );
  });

  test(
    'cancelling folder selection restores the prior results state',
    () async {
      final verified = _candidate(
        'verified-before-selection',
        MediaSource.cameraGallery,
        RecoveryClassification.verifiedDeleted,
      );
      final source = _AuthorizedFolderPageSource(
        canScan: true,
        initialItems: [_item(verified)],
        folderHandler: ({required source, required onProgress}) async =>
            const AuthorizedFolderScanOutcome(
              status: AuthorizedFolderScanStatus.selectionCancelled,
            ),
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: source,
      );
      await controller.start();
      final statusBeforeSelection = controller.state.status;

      await controller.scanAuthorizedFolder();

      expect(controller.state.status, statusBeforeSelection);
      expect(controller.state.verifiedItems, [verified]);
    },
  );

  test(
    'completed empty folder scan and access failure remain honest',
    () async {
      final emptySource = _AuthorizedFolderPageSource(
        canScan: true,
        folderHandler: ({required source, required onProgress}) async =>
            const AuthorizedFolderScanOutcome(
              status: AuthorizedFolderScanStatus.completed,
            ),
      );
      final emptyController = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: emptySource,
      );
      await emptyController.scanAuthorizedFolder();
      expect(
        emptyController.state.status,
        RecoveryScanViewStatus.emptyRestricted,
      );

      final deniedSource = _AuthorizedFolderPageSource(
        canScan: true,
        folderHandler: ({required source, required onProgress}) async =>
            const AuthorizedFolderScanOutcome(
              status: AuthorizedFolderScanStatus.permissionGrantLost,
              message: 'The persisted folder grant is no longer valid.',
            ),
      );
      final deniedController = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: deniedSource,
      );
      await deniedController.scanAuthorizedFolder();
      expect(deniedController.state.status, RecoveryScanViewStatus.partial);
      expect(deniedController.state.message, contains('no longer valid'));
    },
  );

  test(
    'folder-scan cancellation keeps streamed candidates and reports cancelled',
    () async {
      final copy = _candidate(
        'copy-before-cancel',
        MediaSource.cameraGallery,
        RecoveryClassification.possibleCopy,
      );
      final pending = Completer<AuthorizedFolderScanOutcome>();
      final source = _AuthorizedFolderPageSource(
        canScan: true,
        folderHandler: ({required source, required onProgress}) {
          onProgress(
            AuthorizedFolderScanProgress(
              pageCandidates: [copy],
              filesExamined: 2,
              pageCount: 1,
              entriesExamined: 2,
            ),
          );
          return pending.future;
        },
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: source,
      );

      final scan = controller.scanAuthorizedFolder();
      expect(controller.state.status, RecoveryScanViewStatus.running);
      controller.cancel();
      pending.complete(
        const AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.completed,
        ),
      );
      await scan;

      expect(controller.state.status, RecoveryScanViewStatus.cancelled);
      expect(controller.state.possibleCopies, [copy]);
    },
  );

  test('folder scan is not offered for a source-specific scan', () async {
    final source = _AuthorizedFolderPageSource(
      canScan: true,
      folderHandler: ({required source, required onProgress}) async =>
          const AuthorizedFolderScanOutcome(
            status: AuthorizedFolderScanStatus.completed,
          ),
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: source,
    );

    expect(controller.canScanAuthorizedFolder, isFalse);
    await controller.scanAuthorizedFolder();
    expect(source.folderCalls, 0);
  });

  test(
    'each completed scan starts and ends an isolated provider session',
    () async {
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
    },
  );

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

typedef _AuthorizedFolderHandler =
    Future<AuthorizedFolderScanOutcome> Function({
      required RecoveryScanSource source,
      required void Function(AuthorizedFolderScanProgress progress) onProgress,
    });

class _AuthorizedFolderPageSource
    implements RecoveryScanPageSource, AuthorizedFolderScanAwarePageSource {
  _AuthorizedFolderPageSource({
    required this.canScan,
    required this.folderHandler,
    this.initialItems = const [],
  });

  final bool canScan;
  final _AuthorizedFolderHandler folderHandler;
  final List<VerifiedSourceRecoveryItem> initialItems;
  int folderCalls = 0;

  @override
  bool get canScanAuthorizedFolder => canScan;

  @override
  Future<AuthorizedFolderScanOutcome> scanAuthorizedFolder({
    required RecoveryScanSource source,
    required void Function(AuthorizedFolderScanProgress progress) onProgress,
  }) {
    folderCalls++;
    return folderHandler(source: source, onProgress: onProgress);
  }

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => _success(source.mediaSource, initialItems);
}

class _LifecyclePageSource
    implements RecoveryScanPageSource, ScanSessionLifecyclePageSource {
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
  bool get canRequestDeepStorageAccess => true;
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

class _OptionalDeepUnavailablePageSource
    implements RecoveryScanPageSource, DeepScanCapabilityAwarePageSource {
  @override
  DeepStorageCapabilityStatus get deepCapabilityStatus =>
      DeepStorageCapabilityStatus.unavailable;

  @override
  String? get deepCapabilityMessage => 'Optional deep scan is not available.';

  @override
  bool get canRequestDeepStorageAccess => false;

  @override
  Future<void> openDeepScanSettings() async {}

  @override
  Future<bool> refreshDeepScanCapability() async => false;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => _success(source.mediaSource, const []);
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
