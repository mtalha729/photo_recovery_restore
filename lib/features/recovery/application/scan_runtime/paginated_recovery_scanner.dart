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
  const PaginatedRecoveryScanner({this.maximumPageSize = 200})
    : assert(maximumPageSize > 0);

  final int maximumPageSize;

  Future<RecoveryScanSummary> scan({
    required int pageSize,
    required RecoveryPageLoader loadPage,
    required RecoveryPageConsumer consumePage,
    required ScanCancellationToken cancellationToken,
    ScanProgressListener? onProgress,
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
      if (cancellationToken.isCancelled) {
        return RecoveryScanSummary(
          completion: RecoveryScanCompletion.cancelled,
          progress: progress,
        );
      }
      switch (result) {
        case VerifiedSourceRecoveryUnsupported():
          return RecoveryScanSummary(
            completion: RecoveryScanCompletion.unsupported,
            progress: progress,
          );
        case VerifiedSourceRecoveryFailure failure:
          return RecoveryScanSummary(
            completion: RecoveryScanCompletion.failed,
            progress: progress,
            failure: failure,
          );
        case VerifiedSourceRecoverySuccess success:
          await consumePage(success);
          progress = RecoveryScanProgress(
            processedCount:
                progress.processedCount + success.diagnostics.examinedCount,
            pageCount: progress.pageCount + 1,
            discoveredVerifiedCount:
                progress.discoveredVerifiedCount + success.items.length,
          );
          onProgress?.call(progress);
          final nextToken = success.nextContinuationToken;
          final nextId = success.nextAfterMediaStoreId;
          if (nextToken == null && nextId == null) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.completed,
              progress: progress,
            );
          }
          final continuationKey = nextToken ?? 'legacy:$nextId';
          if (!seenContinuations.add(continuationKey)) {
            return RecoveryScanSummary(
              completion: RecoveryScanCompletion.completed,
              progress: progress,
            );
          }
          continuationToken = nextToken;
          continuation = nextToken == null ? nextId : null;
      }
    }
  }
}
