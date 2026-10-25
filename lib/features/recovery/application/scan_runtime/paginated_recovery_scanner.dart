import '../../data/trash_discovery/trash_discovery_models.dart';
import '../source_recovery/verified_source_recovery_models.dart';
import 'scan_cancellation.dart';

typedef RecoveryPageLoader = Future<VerifiedSourceRecoveryResult> Function(
  TrashDiscoveryPageRequest request,
);
typedef RecoveryPageConsumer = Future<void> Function(
  VerifiedSourceRecoverySuccess page,
);
typedef ScanProgressListener = void Function(RecoveryScanProgress progress);
typedef ScanStopAfterPage = bool Function();

enum RecoveryScanCompletion { completed, cancelled, unsupported, failed }

class RecoveryScanProgress {
  const RecoveryScanProgress({
    required this.processedCount,
    required this.pageCount,
    required this.discoveredVerifiedCount,
  });

  final int processedCount;
  final int pageCount;
  final int discoveredVerifiedCount;
}

class RecoveryScanSummary {
  const RecoveryScanSummary({
    required this.completion,
    required this.progress,
    this.failure,
  });

  final RecoveryScanCompletion completion;
  final RecoveryScanProgress progress;
  final VerifiedSourceRecoveryFailure? failure;

  bool get isCompleteSuccess => completion == RecoveryScanCompletion.completed;
}

class PaginatedRecoveryScanner {
  const PaginatedRecoveryScanner({
    this.maximumPageSize = 200,
    this.maximumPageCount = 1000,
  }) : assert(maximumPageSize > 0),
       assert(maximumPageCount > 0);

  final int maximumPageSize;
  final int maximumPageCount;

  Future<RecoveryScanSummary> scan({
    required int pageSize,
    required RecoveryPageLoader loadPage,
    required RecoveryPageConsumer consumePage,
    required ScanCancellationToken cancellationToken,
    ScanProgressListener? onProgress,
    ScanStopAfterPage? shouldStopAfterPage,
  }) async {
    if (pageSize <= 0 || pageSize > maximumPageSize) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    var progress = const RecoveryScanProgress(
      processedCount: 0,
      pageCount: 0,
      discoveredVerifiedCount: 0,
    );
    int? continuation;
    String? continuationToken;
    final seenContinuations = <String>{};

    while (true) {
      if (cancellationToken.isCancelled) {
        return RecoveryScanSummary(
          completion: RecoveryScanCompletion.cancelled,
          progress: progress,
        );
      }
      final result = await loadPage(
        TrashDiscoveryPageRequest(
          pageSize: pageSize,
          afterMediaStoreId: continuation,
          continuationToken: continuationToken,
        ),
      );
      switch (result) {
        case VerifiedSourceRecoveryUnsupported():
          if (cancellationToken.isCancelled) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.cancelled,
              progress: progress,
            );
          }
          return RecoveryScanSummary(
            completion: RecoveryScanCompletion.unsupported,
            progress: progress,
          );
        case VerifiedSourceRecoveryFailure failure:
          return RecoveryScanSummary(
            completion: cancellationToken.isCancelled
                ? RecoveryScanCompletion.cancelled
                : RecoveryScanCompletion.failed,
            progress: progress,
            failure: cancellationToken.isCancelled ? null : failure,
          );
        case VerifiedSourceRecoverySuccess success:
          if (cancellationToken.isCancelled) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.cancelled,
              progress: progress,
            );
          }
          await consumePage(success);
          progress = RecoveryScanProgress(
            processedCount:
                progress.processedCount + success.diagnostics.examinedCount,
            pageCount: progress.pageCount + 1,
            discoveredVerifiedCount:
                progress.discoveredVerifiedCount + success.items.length,
          );
          onProgress?.call(progress);
          // Providers are paged, so give the UI isolate a turn after every
          // published batch. This keeps initial results and cancellation
          // responsive even while a long source has more pages available.
          await Future<void>.delayed(Duration.zero);
          if (cancellationToken.isCancelled) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.cancelled,
              progress: progress,
            );
          }
          if (shouldStopAfterPage?.call() == true) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.failed,
              progress: progress,
              failure: VerifiedSourceRecoveryFailure(
                source: success.source,
                code: VerifiedSourceRecoveryFailureCode.resourceLimit,
                message:
                    'Recovery stopped at the safe verified-result memory limit; earlier results are retained and coverage is partial.',
              ),
            );
          }
          final nextToken = success.nextContinuationToken;
          final nextId = success.nextAfterMediaStoreId;
          if (nextToken == null && nextId == null) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.completed,
              progress: progress,
            );
          }
          if (progress.pageCount >= maximumPageCount) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.failed,
              progress: progress,
              failure: VerifiedSourceRecoveryFailure(
                source: success.source,
                code: VerifiedSourceRecoveryFailureCode.resourceLimit,
                message:
                    'Recovery reached the $maximumPageCount-page safety limit; coverage is partial.',
              ),
            );
          }
          final continuationKey = nextToken ?? 'legacy:$nextId';
          if (!seenContinuations.add(continuationKey)) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.failed,
              progress: progress,
              failure: VerifiedSourceRecoveryFailure(
                source: success.source,
                code: VerifiedSourceRecoveryFailureCode.platformFailure,
                message:
                    'Recovery pagination repeated a continuation state; coverage is partial.',
              ),
            );
          }
          continuationToken = nextToken;
          continuation = nextToken == null ? nextId : null;
      }
    }
  }
}
