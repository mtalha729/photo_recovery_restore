import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../recovery/application/scan_runtime/paginated_recovery_scanner.dart';
import '../../recovery/application/scan_runtime/scan_cancellation.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_models.dart';
import '../../recovery/application/restore/system_trash_restore_models.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/media_candidate.dart';
import 'authorized_folder_scan_models.dart';
import 'recovery_scan_models.dart';
import 'recovery_scan_page_source.dart';
import 'production_recovery_scan_page_source.dart';
import '../../restore_ux/application/restore_ux_models.dart';
import '../../recovery/data/restore/file_copy_restorer.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import '../../recovery/application/deep_recovery/deep_recovery_engine.dart';
import '../../recovery/application/duplicate_resolution/duplicate_best_copy_resolver.dart';

class RecoveryScanController extends ChangeNotifier {
  static const _maximumRetainedVerifiedResults = 10000;

  RecoveryScanController({
    required RecoveryScanSource source,
    required this.pageSource,
    this.scanner = const PaginatedRecoveryScanner(),
    Iterable<MediaCandidate> possibleCopies = const [],
  }) : _state = RecoveryScanViewState(
         source: source,
         possibleCopies: List<MediaCandidate>.unmodifiable(
           possibleCopies.where(
             (candidate) =>
                 (source == RecoveryScanSource.allPhotos ||
                     candidate.source == source.mediaSource) &&
                 candidate.classification ==
                     RecoveryClassification.possibleCopy,
           ),
         ),
       ) {
    _initialPossibleCopies = _state.possibleCopies;
  }

  final RecoveryScanPageSource pageSource;
  final PaginatedRecoveryScanner scanner;
  late final List<MediaCandidate> _initialPossibleCopies;
  RecoveryScanViewState _state;
  ScanCancellationToken? _token;
  final Map<String, VerifiedSourceRecoveryItem> _itemsById = {};
  int _scanSession = 0;
  int _standardItemsExamined = 0;
  int? _terminalSession;
  String? _lastFailureType;

  RecoveryScanViewState get state => _state;

  RestoreReviewItem reviewItemFor(MediaCandidate candidate) {
    final item = _itemsById[candidate.id];
    if ((candidate.filePath != null ||
            candidate.documentUri != null ||
            candidate.contentUri != null) &&
        (candidate.classification == RecoveryClassification.possibleCopy ||
            candidate.classification == RecoveryClassification.existingMedia)) {
      return RestoreReviewItem(
        candidate: candidate,
        route: RestoreRoute.fileCopy,
        fileCopyRequest: FileCopyRestoreRequest(candidate: candidate),
      );
    }
    if (item == null || !item.restoreEligibility.isEligible) {
      return RestoreReviewItem(
        candidate: candidate,
        route: RestoreRoute.unavailable,
      );
    }
    return RestoreReviewItem(
      candidate: candidate,
      route: RestoreRoute.systemTrash,
      systemRequest: SystemTrashRestoreRequest(
        requestId: candidate.id,
        candidate: candidate,
        classificationDecision: item.classificationDecision,
      ),
    );
  }

  Future<void> start() async {
    if (_state.status == RecoveryScanViewStatus.running ||
        _state.status == RecoveryScanViewStatus.cancelling) {
      return;
    }
    final session = ++_scanSession;
    _standardItemsExamined = 0;
    _lastFailureType = null;
    if (pageSource is ScanSessionLifecyclePageSource) {
      (pageSource as ScanSessionLifecyclePageSource).beginScanSession();
    }
    final token = ScanCancellationToken();
    _token = token;
    _itemsById.clear();
    if (pageSource is CancellationAwarePageSource) {
      (pageSource as CancellationAwarePageSource).cancellationToken = token;
    }
    if (pageSource is ProductionRecoveryScanPageSource) {
      (pageSource as ProductionRecoveryScanPageSource).onDeepProgress =
          (progress) {
            if (_isActive(session, token)) _onDeepProgress(progress);
          };
    }
    final verified = <MediaCandidate>[];
    var resultLimitReached = false;
    _set(
      RecoveryScanViewState(
        source: _state.source,
        status: RecoveryScanViewStatus.running,
        possibleCopies: _initialPossibleCopies,
      ),
    );

    RecoveryScanSummary summary;
    try {
      summary = await scanner.scan(
        pageSize: 200,
        cancellationToken: token,
        loadPage: (request) => pageSource.loadPage(_state.source, request),
        shouldStopAfterPage: () => resultLimitReached,
        consumePage: (page) async {
          for (final item in page.items) {
            final candidate = item.candidate;
            if (_itemsById.containsKey(candidate.id)) continue;
            final isInSelectedSource =
                _state.source == RecoveryScanSource.allPhotos ||
                candidate.source == _state.source.mediaSource;
            if (!isInSelectedSource ||
                !candidate.classification.isDeletedRecoveryResult) {
              continue;
            }
            if (verified.length >= _maximumRetainedVerifiedResults) {
              resultLimitReached = true;
              continue;
            }
            _itemsById[candidate.id] = item;
            verified.add(candidate);
          }
        },
        onProgress: (progress) {
          if (!_isActive(session, token)) return;
          _standardItemsExamined = progress.processedCount;
          final copiesById = <String, MediaCandidate>{
            for (final candidate in _state.possibleCopies)
              candidate.id: candidate,
          };
          if (pageSource is PossibleCopiesAwarePageSource) {
            for (final candidate
                in (pageSource as PossibleCopiesAwarePageSource)
                    .possibleCopies) {
              if (candidate.classification ==
                      RecoveryClassification.possibleCopy &&
                  (_state.source == RecoveryScanSource.allPhotos ||
                      candidate.source == _state.source.mediaSource)) {
                copiesById.putIfAbsent(candidate.id, () => candidate);
              }
            }
          }
          _set(
            _state.copyWith(
              progress: RecoveryScanProgress(
                processedCount:
                    progress.processedCount > _state.progress.processedCount
                    ? progress.processedCount
                    : _state.progress.processedCount,
                pageCount: progress.pageCount,
                discoveredVerifiedCount: verified.length,
              ),
              verifiedItems: List.unmodifiable(verified),
              possibleCopies: _distinctRecoveryCopies(copiesById.values),
            ),
          );
        },
      );
    } catch (error) {
      _lastFailureType = error.runtimeType.toString();
      final hasPartialResults =
          verified.isNotEmpty || _state.possibleCopies.isNotEmpty;
      _finishTerminal(
        session,
        _state.copyWith(
          status: token.isCancelled
              ? RecoveryScanViewStatus.cancelled
              : hasPartialResults
              ? RecoveryScanViewStatus.partial
              : RecoveryScanViewStatus.failure,
          verifiedItems: List<MediaCandidate>.unmodifiable(verified),
          message: token.isCancelled
              ? null
              : hasPartialResults
              ? 'The scan stopped early. Photos already found are retained.'
              : 'Scan could not finish safely.',
        ),
        token.isCancelled ? 'cancelled' : 'failed',
      );
      return;
    } finally {
      if (_scanSession == session) {
        if (pageSource is CancellationAwarePageSource) {
          (pageSource as CancellationAwarePageSource).cancellationToken = null;
        }
        if (pageSource is ProductionRecoveryScanPageSource) {
          (pageSource as ProductionRecoveryScanPageSource).onDeepProgress =
              null;
        }
      }
    }
    if (!_isActive(session, token)) return;
    final items = List<MediaCandidate>.unmodifiable(verified);
    final copiesById = <String, MediaCandidate>{
      for (final candidate in _state.possibleCopies) candidate.id: candidate,
    };
    if (pageSource is PossibleCopiesAwarePageSource) {
      for (final candidate
          in (pageSource as PossibleCopiesAwarePageSource).possibleCopies) {
        copiesById.putIfAbsent(candidate.id, () => candidate);
      }
    }
    final discoveredCopies = _distinctRecoveryCopies(copiesById.values);
    final isLimited =
        pageSource is LimitedAccessAwarePageSource &&
        (pageSource as LimitedAccessAwarePageSource).isLimitedAccess;
    final capabilityMessage = pageSource is DeepScanCapabilityAwarePageSource
        ? (pageSource as DeepScanCapabilityAwarePageSource)
              .deepCapabilityMessage
        : null;
    final production = pageSource is ProductionRecoveryScanPageSource
        ? pageSource as ProductionRecoveryScanPageSource
        : null;
    final deepStoppedEarly =
        production?.deepProviderRunState == 'partialFailure' ||
        production?.deepProviderRunState == 'failedCapabilityCheck' ||
        production?.deepProviderRunState == 'skippedCapabilityFailure';
    final restrictedCoverage = isLimited;
    final diagnostics = production?.diagnostics;
    final emptyMessage = diagnostics == null
        ? null
        : 'Indexed ${diagnostics.currentRecordsScanned} current photos and examined '
              '${diagnostics.filesExamined} shared-storage files. '
              'Recovery candidates: ${diagnostics.discoveredCandidates} discovered, '
              '${diagnostics.rejectedCandidates} rejected, '
              '${diagnostics.duplicateRecordsSuppressed} duplicates, '
              '${diagnostics.finalPossibleCopies} possible copies, '
              '${diagnostics.finalVerifiedDeleted} verified deleted. '
              'Deep scan: ${production!.deepProviderRunState}.';
    final normalizedProgress = RecoveryScanProgress(
      processedCount:
          summary.progress.processedCount > _state.progress.processedCount
          ? summary.progress.processedCount
          : _state.progress.processedCount,
      pageCount: summary.progress.pageCount,
      discoveredVerifiedCount: items.length,
    );
    switch (summary.completion) {
      case RecoveryScanCompletion.completed:
        _finishTerminal(
          session,
          _state.copyWith(
            status: resultLimitReached || deepStoppedEarly
                ? RecoveryScanViewStatus.partial
                : items.isEmpty && discoveredCopies.isEmpty
                ? restrictedCoverage
                      ? RecoveryScanViewStatus.emptyRestricted
                      : RecoveryScanViewStatus.empty
                : restrictedCoverage
                ? RecoveryScanViewStatus.completeRestricted
                : RecoveryScanViewStatus.complete,
            progress: normalizedProgress,
            message: resultLimitReached
                ? 'The scan retained the first $_maximumRetainedVerifiedResults verified results to keep memory bounded. Coverage is partial; the full result set is not displayed.'
                : deepStoppedEarly
                ? [
                        'The deep scan stopped early; results already found are kept.',
                        emptyMessage,
                        capabilityMessage,
                      ]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' ')
                : items.isEmpty && discoveredCopies.isEmpty
                ? [emptyMessage, capabilityMessage]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' ')
                : null,
            verifiedItems: items,
            possibleCopies: List<MediaCandidate>.unmodifiable(
              discoveredCopies.where(
                (candidate) =>
                    (_state.source == RecoveryScanSource.allPhotos ||
                        candidate.source == _state.source.mediaSource) &&
                    candidate.classification ==
                        RecoveryClassification.possibleCopy,
              ),
            ),
            isLimitedAccess: isLimited,
            deepCapabilityMessage: capabilityMessage,
          ),
          resultLimitReached ? 'resultMemoryLimit' : 'exhausted',
        );
      case RecoveryScanCompletion.cancelled:
        _finishTerminal(
          session,
          _state.copyWith(status: RecoveryScanViewStatus.cancelled),
          'cancelled',
        );
      case RecoveryScanCompletion.unsupported:
        _finishTerminal(
          session,
          _state.copyWith(status: RecoveryScanViewStatus.unsupported),
          'failed',
        );
      case RecoveryScanCompletion.failed:
        final access =
            summary.failure?.code ==
            VerifiedSourceRecoveryFailureCode.accessUnavailable;
        final deepRequired =
            pageSource is DeepScanCapabilityAwarePageSource &&
            (pageSource as DeepScanCapabilityAwarePageSource)
                    .deepCapabilityStatus ==
                DeepStorageCapabilityStatus.accessRequired;
        final hasPartialResults =
            items.isNotEmpty ||
            discoveredCopies.isNotEmpty ||
            summary.failure?.code ==
                VerifiedSourceRecoveryFailureCode.resourceLimit;
        _finishTerminal(
          session,
          _state.copyWith(
            status: hasPartialResults
                ? RecoveryScanViewStatus.partial
                : deepRequired && canOpenDeepStorageAccessSettings
                ? RecoveryScanViewStatus.deepAccessRequired
                : access
                ? RecoveryScanViewStatus.accessUnavailable
                : deepRequired
                ? RecoveryScanViewStatus.deepAccessRequired
                : RecoveryScanViewStatus.failure,
            verifiedItems: items,
            possibleCopies: List<MediaCandidate>.unmodifiable(
              discoveredCopies.where(
                (candidate) =>
                    (_state.source == RecoveryScanSource.allPhotos ||
                        candidate.source == _state.source.mediaSource) &&
                    candidate.classification ==
                        RecoveryClassification.possibleCopy,
              ),
            ),
            isLimitedAccess: isLimited,
            deepCapabilityMessage: capabilityMessage,
            message: hasPartialResults
                ? 'The scan stopped before full coverage. Results already found are retained. ${summary.failure?.message ?? ''}'
                : summary.failure?.message,
          ),
          resultLimitReached ? 'resultMemoryLimit' : 'failed',
        );
    }
  }

  bool _isActive(int session, ScanCancellationToken token) =>
      _scanSession == session &&
      _terminalSession != session &&
      identical(_token, token);

  void _finishTerminal(
    int session,
    RecoveryScanViewState value,
    String reason,
  ) {
    if (_scanSession != session || _terminalSession == session) return;
    _terminalSession = session;
    _token = null;
    _set(value);
    if (!kDebugMode) {
      _endPageSourceSession();
      return;
    }
    final production = pageSource is ProductionRecoveryScanPageSource
        ? pageSource as ProductionRecoveryScanPageSource
        : null;
    final diagnostics = production?.diagnostics;
    final visibleResults = <MediaCandidate>[
      ...value.verifiedItems,
      ...value.possibleCopies,
    ];
    final displayedIdentities = {
      for (final item in visibleResults)
        item.contentUri?.toString() ??
            item.documentUri?.toString() ??
            item.filePath ??
            item.id,
    };
    final completed =
        value.status == RecoveryScanViewStatus.complete ||
        value.status == RecoveryScanViewStatus.completeRestricted ||
        value.status == RecoveryScanViewStatus.empty ||
        value.status == RecoveryScanViewStatus.emptyRestricted;
    debugPrint(
      'Scan terminal state: ${completed ? 'COMPLETED' : value.status.name.toUpperCase()}\n'
      'Current-media inventory: ${diagnostics?.currentMediaInventoryState ?? 'unknown'}\n'
      'Verified-trash provider: ${diagnostics?.verifiedTrashProviderState ?? 'unknown'}\n'
      'Deep provider state: ${production?.deepProviderRunState ?? 'not configured'}\n'
      'Deep provider exhausted: ${production?.deepProviderExhausted ?? 'unknown'}\n'
      'Pending provider requests: ${production?.pendingProviderRequests ?? 'unknown'}\n'
      'Pending classification tasks: ${production?.pendingClassificationTasks ?? 'unknown'}\n'
      'Remaining native queue: ${production?.remainingNativeQueue ?? 'unknown'}\n'
      'Last continuation: ${production?.lastContinuationState ?? 'unknown'}\n'
      'Files examined: ${diagnostics?.filesExamined ?? value.progress.processedCount}\n'
      'MediaStore rows returned: ${diagnostics?.mediaStoreRowsReturned ?? 'unknown'}\n'
      'Current photos mapped: ${diagnostics?.currentPhotosMapped ?? 'unknown'}\n'
      'Current inventory results withheld: ${diagnostics?.currentPhotosMapped ?? 'unknown'}\n'
      'Current rows rejected: ${diagnostics?.currentRowsRejected ?? 'unknown'}\n'
      'Current duplicates suppressed: ${diagnostics?.currentDuplicatesSuppressed ?? 'unknown'}\n'
      'Directories examined: ${diagnostics?.foldersVisited ?? value.deepDirectoriesExamined}\n'
      'Candidates: discovered=${diagnostics?.discoveredCandidates ?? 0}, '
      'rejected=${diagnostics?.rejectedCandidates ?? 0}, '
      'duplicates=${diagnostics?.duplicateRecordsSuppressed ?? 0}, '
      'possible=${diagnostics?.finalPossibleCopies ?? value.possibleCopies.length}, '
      'verified=${diagnostics?.finalVerifiedDeleted ?? value.verifiedItems.length}\n'
      'Pages processed: ${value.progress.pageCount}\n'
      'Verified results: ${value.verifiedItems.length}\n'
      'Ordinary gallery originals displayed: 0\n'
      'Recoverable copies: ${value.possibleCopies.length}\n'
      'Cache images: ${visibleResults.where((item) => item.discoveryEvidence.isCacheLike).length}\n'
      'Thumbnails: ${visibleResults.where((item) => item.discoveryEvidence.isThumbnailLike).length}\n'
      'Volumes scanned: ${diagnostics?.volumesScanned.length ?? 0}\n'
      'Inaccessible locations: ${(diagnostics?.unavailableDirectories ?? 0) + (diagnostics?.unavailableFiles ?? 0)}\n'
      'Recovery candidates delivered: ${visibleResults.length}\n'
      'Distinct result cards: ${displayedIdentities.length}\n'
      'Completion reason: $reason'
      '${_lastFailureType == null ? '' : '\nFailure type: $_lastFailureType'}',
    );
    if (diagnostics?.currentMediaInventoryState == 'completed' &&
        diagnostics?.accessMode == 'fullAccess' &&
        diagnostics?.currentPhotosMapped == 0) {
      debugPrint(
        'Diagnostic: full photo access returned zero current images; verify MediaStore visibility and source data on this device.',
      );
    }
    _endPageSourceSession();
  }

  void _endPageSourceSession() {
    if (pageSource is ScanSessionLifecyclePageSource) {
      (pageSource as ScanSessionLifecyclePageSource).endScanSession();
    }
  }

  bool get canOpenDeepStorageAccessSettings =>
      pageSource is DeepScanCapabilityAwarePageSource &&
      (pageSource as DeepScanCapabilityAwarePageSource)
          .canRequestDeepStorageAccess;

  bool get canScanAuthorizedFolder =>
      _state.source == RecoveryScanSource.allPhotos &&
      pageSource is AuthorizedFolderScanAwarePageSource &&
      (pageSource as AuthorizedFolderScanAwarePageSource)
          .canScanAuthorizedFolder;

  Future<void> scanAuthorizedFolder() async {
    if (!canScanAuthorizedFolder ||
        _state.status == RecoveryScanViewStatus.running ||
        _state.status == RecoveryScanViewStatus.cancelling) {
      return;
    }
    final previousState = _state;
    final session = ++_scanSession;
    if (pageSource is ScanSessionLifecyclePageSource) {
      (pageSource as ScanSessionLifecyclePageSource).beginScanSession();
    }
    final token = ScanCancellationToken();
    _token = token;
    _lastFailureType = null;
    if (pageSource is CancellationAwarePageSource) {
      (pageSource as CancellationAwarePageSource).cancellationToken = token;
    }
    _set(
      _state.copyWith(
        status: RecoveryScanViewStatus.running,
        progress: RecoveryScanProgress(
          processedCount: 0,
          pageCount: 0,
          discoveredVerifiedCount: _state.verifiedItems.length,
        ),
        scanPhase: 'Selected folder',
        currentScanArea: 'Waiting for folder selection',
      ),
    );

    AuthorizedFolderScanOutcome outcome;
    try {
      outcome = await (pageSource as AuthorizedFolderScanAwarePageSource)
          .scanAuthorizedFolder(
            source: _state.source,
            onProgress: (progress) {
              if (!_isActive(session, token)) return;
              final byId = {
                for (final item in _state.possibleCopies) item.id: item,
              };
              for (final candidate in progress.pageCandidates) {
                if (candidate.classification ==
                        RecoveryClassification.possibleCopy &&
                    (_state.source == RecoveryScanSource.allPhotos ||
                        candidate.source == _state.source.mediaSource)) {
                  byId.putIfAbsent(candidate.id, () => candidate);
                }
              }
              _set(
                _state.copyWith(
                  progress: RecoveryScanProgress(
                    processedCount: progress.filesExamined,
                    pageCount: progress.pageCount,
                    discoveredVerifiedCount: _state.verifiedItems.length,
                  ),
                  possibleCopies: _distinctRecoveryCopies(byId.values),
                  deepCandidatesFound: byId.length,
                  currentScanArea: 'User-authorized folder',
                  scanPhase: 'Selected folder',
                ),
              );
            },
          );
    } catch (error) {
      _lastFailureType = error.runtimeType.toString();
      if (pageSource is CancellationAwarePageSource) {
        (pageSource as CancellationAwarePageSource).cancellationToken = null;
      }
      _finishTerminal(
        session,
        _state.copyWith(
          status: token.isCancelled
              ? RecoveryScanViewStatus.cancelled
              : RecoveryScanViewStatus.partial,
          message: token.isCancelled
              ? 'Selected-folder scan cancelled; results found so far are kept.'
              : 'Selected-folder scan ended unexpectedly; results found so far are kept.',
        ),
        token.isCancelled ? 'cancelled' : 'folderPartialFailure',
      );
      return;
    }
    if (pageSource is CancellationAwarePageSource) {
      (pageSource as CancellationAwarePageSource).cancellationToken = null;
    }
    if (!_isActive(session, token)) return;

    if (outcome.status == AuthorizedFolderScanStatus.selectionCancelled &&
        !token.isCancelled) {
      _terminalSession = session;
      _token = null;
      _set(previousState);
      _endPageSourceSession();
      return;
    }

    final selectedFolderMessage = [
      outcome.message ?? 'Only the folder you selected was searched.',
      'Results are possible copies, not verified deletions.',
    ].join(' ');
    final combinedMessage = [
      previousState.deepCapabilityMessage,
      selectedFolderMessage,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join('\n');
    final hasResults =
        _state.verifiedItems.isNotEmpty || _state.possibleCopies.isNotEmpty;
    final completed = outcome.status == AuthorizedFolderScanStatus.completed;
    final cancelled =
        token.isCancelled ||
        outcome.status == AuthorizedFolderScanStatus.cancelled;
    final status = cancelled
        ? RecoveryScanViewStatus.cancelled
        : completed
        ? hasResults
              ? RecoveryScanViewStatus.completeRestricted
              : RecoveryScanViewStatus.emptyRestricted
        : RecoveryScanViewStatus.partial;
    _finishTerminal(
      session,
      _state.copyWith(
        status: status,
        isLimitedAccess: previousState.isLimitedAccess,
        deepCapabilityMessage: combinedMessage,
        message: selectedFolderMessage,
        currentScanArea: null,
        scanPhase: 'Selected folder',
      ),
      cancelled
          ? 'cancelled'
          : completed
          ? 'selectedFolderExhausted'
          : 'selectedFolderPartialFailure',
    );
  }

  Future<void> openDeepScanSettings() async {
    if (pageSource is! DeepScanCapabilityAwarePageSource) return;
    await (pageSource as DeepScanCapabilityAwarePageSource)
        .openDeepScanSettings();
  }

  Future<void> retryDeepScanAfterResume() async {
    if (_state.status != RecoveryScanViewStatus.deepAccessRequired &&
        _state.status != RecoveryScanViewStatus.completeRestricted &&
        _state.status != RecoveryScanViewStatus.emptyRestricted) {
      return;
    }
    if (pageSource is! DeepScanCapabilityAwarePageSource) return;
    final available = await (pageSource as DeepScanCapabilityAwarePageSource)
        .refreshDeepScanCapability();
    if (available) await start();
  }

  void _onDeepProgress(DeepRecoveryEngineProgress progress) {
    final byId = {for (final item in _state.possibleCopies) item.id: item};
    for (final candidate in progress.possibleCopyCandidates) {
      if (candidate.classification == RecoveryClassification.possibleCopy &&
          (_state.source == RecoveryScanSource.allPhotos ||
              candidate.source == _state.source.mediaSource)) {
        byId.putIfAbsent(candidate.id, () => candidate);
      }
    }
    _set(
      _state.copyWith(
        progress: RecoveryScanProgress(
          processedCount:
              _standardItemsExamined + progress.filesExamined >
                  _state.progress.processedCount
              ? _standardItemsExamined + progress.filesExamined
              : _state.progress.processedCount,
          pageCount: progress.pageCount,
          discoveredVerifiedCount: _state.progress.discoveredVerifiedCount,
        ),
        possibleCopies: _distinctRecoveryCopies(byId.values),
        deepDirectoriesExamined: progress.directoriesExamined,
        deepCandidatesFound: byId.length,
        currentScanArea: progress.currentArea,
        scanPhase: 'Deep storage',
      ),
    );
  }

  List<MediaCandidate> _distinctRecoveryCopies(
    Iterable<MediaCandidate> candidates,
  ) {
    final byId = {for (final candidate in candidates) candidate.id: candidate};
    final groups = const DuplicateBestCopyResolver()
        .resolve(candidates: byId.values)
        .groups;
    return List<MediaCandidate>.unmodifiable([
      for (final group in groups) group.canonicalCandidate,
      for (final group in groups) ...group.alternateVariants,
    ]);
  }

  void cancel() {
    if (_state.status != RecoveryScanViewStatus.running) return;
    _set(_state.copyWith(status: RecoveryScanViewStatus.cancelling));
    _token?.cancel();
    if (pageSource is ActiveScanCancellationAwarePageSource) {
      unawaited(
        (pageSource as ActiveScanCancellationAwarePageSource)
            .cancelActiveScan(),
      );
    }
  }

  void _set(RecoveryScanViewState value) {
    _state = value;
    notifyListeners();
  }
}
