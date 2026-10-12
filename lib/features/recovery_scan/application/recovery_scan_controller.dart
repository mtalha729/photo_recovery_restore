import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../recovery/application/scan_runtime/paginated_recovery_scanner.dart';
import '../../recovery/application/scan_runtime/scan_cancellation.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_models.dart';
import '../../recovery/application/restore/system_trash_restore_models.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/media_candidate.dart';
import 'recovery_scan_models.dart';
import 'recovery_scan_page_source.dart';
import 'production_recovery_scan_page_source.dart';
import '../../restore_ux/application/restore_ux_models.dart';
import '../../recovery/data/restore/file_copy_restorer.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import '../../recovery/application/deep_recovery/deep_recovery_engine.dart';

class RecoveryScanController extends ChangeNotifier {
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
       );

  final RecoveryScanPageSource pageSource;
  final PaginatedRecoveryScanner scanner;
  RecoveryScanViewState _state;
  ScanCancellationToken? _token;
  final Map<String, VerifiedSourceRecoveryItem> _itemsById = {};
  int _scanSession = 0;
  int? _terminalSession;
  String? _lastFailureType;

  RecoveryScanViewState get state => _state;

  RestoreReviewItem reviewItemFor(MediaCandidate candidate) {
    final item = _itemsById[candidate.id];
    if (candidate.filePath != null &&
        candidate.classification == RecoveryClassification.possibleCopy) {
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
    _set(
      RecoveryScanViewState(
        source: _state.source,
        status: RecoveryScanViewStatus.running,
      ),
    );

    RecoveryScanSummary summary;
    try {
      summary = await scanner.scan(
        pageSize: 200,
        cancellationToken: token,
        loadPage: (request) => pageSource.loadPage(_state.source, request),
        consumePage: (page) async {
          for (final item in page.items) {
            final candidate = item.candidate;
            if (_itemsById.containsKey(candidate.id)) continue;
            _itemsById[candidate.id] = item;
            if ((_state.source == RecoveryScanSource.allPhotos ||
                    candidate.source == _state.source.mediaSource) &&
                candidate.classification.isDeletedRecoveryResult) {
              verified.add(candidate);
            }
          }
        },
        onProgress: (progress) {
          if (!_isActive(session, token)) return;
          _set(
            _state.copyWith(
              progress: RecoveryScanProgress(
                processedCount: progress.processedCount,
                pageCount: progress.pageCount,
                discoveredVerifiedCount: verified.length,
              ),
              verifiedItems: List.unmodifiable(verified),
            ),
          );
        },
      );
    } catch (error) {
      _lastFailureType = error.runtimeType.toString();
      _finishTerminal(
        session,
        _state.copyWith(
          status: token.isCancelled
              ? RecoveryScanViewStatus.cancelled
              : RecoveryScanViewStatus.failure,
          verifiedItems: List<MediaCandidate>.unmodifiable(verified),
          message: token.isCancelled ? null : 'Scan could not finish safely.',
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
    final discoveredCopies = pageSource is PossibleCopiesAwarePageSource
        ? (pageSource as PossibleCopiesAwarePageSource).possibleCopies
        : _state.possibleCopies;
    final normalizedProgress = RecoveryScanProgress(
      processedCount: summary.progress.processedCount,
      pageCount: summary.progress.pageCount,
      discoveredVerifiedCount: items.length,
    );
    switch (summary.completion) {
      case RecoveryScanCompletion.completed:
        _finishTerminal(
          session,
          _state.copyWith(
            status: items.isEmpty && discoveredCopies.isEmpty
                ? RecoveryScanViewStatus.empty
                : RecoveryScanViewStatus.complete,
            progress: normalizedProgress,
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
            isLimitedAccess:
                pageSource is LimitedAccessAwarePageSource &&
                (pageSource as LimitedAccessAwarePageSource).isLimitedAccess,
            deepCapabilityMessage:
                pageSource is DeepScanCapabilityAwarePageSource
                ? (pageSource as DeepScanCapabilityAwarePageSource)
                      .deepCapabilityMessage
                : null,
          ),
          'exhausted',
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
        _finishTerminal(
          session,
          _state.copyWith(
            status: deepRequired
                ? RecoveryScanViewStatus.deepAccessRequired
                : access
                ? RecoveryScanViewStatus.accessUnavailable
                : RecoveryScanViewStatus.failure,
            message: summary.failure?.message,
          ),
          'failed',
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
    final completed =
        value.status == RecoveryScanViewStatus.complete ||
        value.status == RecoveryScanViewStatus.empty;
    debugPrint(
      'Scan terminal state: ${completed ? 'COMPLETED' : value.status.name.toUpperCase()}\n'
      'Standard providers exhausted: ${reason == 'exhausted'}\n'
      'Deep provider exhausted: ${production?.deepProviderExhausted ?? true}\n'
      'Pending provider requests: ${production?.pendingProviderRequests ?? 0}\n'
      'Pending classification tasks: 0\n'
      'Remaining native queue: ${production?.remainingNativeQueue ?? 0}\n'
      'Last continuation present: false\n'
      'Files examined: ${diagnostics?.filesExamined ?? value.progress.processedCount}\n'
      'Directories examined: ${diagnostics?.foldersVisited ?? value.deepDirectoriesExamined}\n'
      'Pages processed: ${value.progress.pageCount}\n'
      'Verified results: ${value.verifiedItems.length}\n'
      'Recoverable copies: ${value.possibleCopies.length}\n'
      'Completion reason: $reason'
      '${_lastFailureType == null ? '' : '\nFailure type: $_lastFailureType'}',
    );
    _endPageSourceSession();
  }

  void _endPageSourceSession() {
    if (pageSource is ScanSessionLifecyclePageSource) {
      (pageSource as ScanSessionLifecyclePageSource).endScanSession();
    }
  }

  Future<void> openDeepScanSettings() async {
    if (pageSource is! DeepScanCapabilityAwarePageSource) return;
    await (pageSource as DeepScanCapabilityAwarePageSource)
        .openDeepScanSettings();
  }

  Future<void> retryDeepScanAfterResume() async {
    if (_state.status != RecoveryScanViewStatus.deepAccessRequired ||
        pageSource is! DeepScanCapabilityAwarePageSource) {
      return;
    }
    final available = await (pageSource as DeepScanCapabilityAwarePageSource)
        .refreshDeepScanCapability();
    if (available) await start();
  }

  void _onDeepProgress(DeepRecoveryEngineProgress progress) {
    _set(
      _state.copyWith(
        progress: RecoveryScanProgress(
          processedCount: progress.filesExamined,
          pageCount: progress.pageCount,
          discoveredVerifiedCount: _state.progress.discoveredVerifiedCount,
        ),
        deepDirectoriesExamined: progress.directoriesExamined,
        deepCandidatesFound: progress.candidatesFound,
        currentScanArea: progress.currentArea,
        scanPhase: 'Photo recovery',
      ),
    );
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
