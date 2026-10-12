import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../possible_copies/possible_copies_discovery.dart';
import '../possible_copies/possible_copy_models.dart';
import '../scan_runtime/scan_cancellation.dart';
import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import 'deep_recovery_classifier.dart';
import 'deep_recovery_provider.dart';

class DeepRecoveryEngineResult {
  const DeepRecoveryEngineResult({
    required this.completed,
    required this.byDisposition,
    required this.possibleCopies,
    required this.providersVisited,
    required this.recordsDiscovered,
    required this.duplicateRecordsSuppressed,
    required this.invalidFilesRejected,
    required this.unavailableFiles,
    this.unsupportedFiles = 0,
    required this.filesExamined,
    required this.directoriesExamined,
    this.entriesExamined = 0,
    this.currentFilesSkipped = 0,
    this.signatureCacheHits = 0,
    this.signatureCacheMisses = 0,
    this.nativeTraversalMillis = 0,
    this.carvedTemporaryBytes = 0,
    this.carvedTempBytesReclaimed = 0,
    this.volumesScanned = const {},
    this.duplicateDirectorySkips = 0,
    this.repeatedCursorDetections = 0,
    this.completionReason,
    this.failureAvailability,
    this.failureMessage,
  });

  final bool completed;
  final Map<DeepRecoveryDisposition, List<MediaCandidate>> byDisposition;
  final PossibleCopiesDiscoveryResult possibleCopies;
  final Set<DeepRecoveryProviderKind> providersVisited;
  final int recordsDiscovered;
  final int duplicateRecordsSuppressed;
  final int invalidFilesRejected;
  final int unavailableFiles;
  final int unsupportedFiles;
  final int filesExamined;
  final int directoriesExamined;
  final int entriesExamined;
  final int currentFilesSkipped;
  final int signatureCacheHits;
  final int signatureCacheMisses;
  final int nativeTraversalMillis;
  final int carvedTemporaryBytes;
  final int carvedTempBytesReclaimed;
  final Set<String> volumesScanned;
  final int duplicateDirectorySkips;
  final int repeatedCursorDetections;
  final String? completionReason;
  final DeepProviderAvailability? failureAvailability;
  final String? failureMessage;
}

class DeepRecoveryEngine {
  const DeepRecoveryEngine({
    this.classifier = const DeepRecoveryClassifier(),
    this.exclusionEngine = const ExistingMediaExclusionEngine(),
    this.possibleCopiesDiscovery = const PossibleCopiesDiscovery(),
  });

  final DeepRecoveryClassifier classifier;
  final ExistingMediaExclusionEngine exclusionEngine;
  final PossibleCopiesDiscovery possibleCopiesDiscovery;

  Future<DeepRecoveryEngineResult> scan({
    required Iterable<DeepRecoveryDiscoveryProvider> providers,
    required ExistingMediaIndex existingMediaIndex,
    required MediaSource source,
    Set<String> currentMediaLocationKeys = const {},
    PhotoRecoveryProfile profile = PhotoRecoveryProfile.fastDeep,
    ScanCancellationToken? cancellationToken,
    int pageSize = 200,
    void Function(DeepRecoveryEngineProgress progress)? onProgress,
  }) async {
    final records = <String, DeepRecoveryDiscoveryRecord>{};
    final visited = <DeepRecoveryProviderKind>{};
    var duplicateRecords = 0;
    var invalidFiles = 0;
    var unavailableFiles = 0;
    var unsupportedFiles = 0;
    var filesExamined = 0;
    var directoriesExamined = 0;
    var entriesExamined = 0;
    var currentFilesSkipped = 0;
    var signatureCacheHits = 0;
    var signatureCacheMisses = 0;
    var nativeTraversalMillis = 0;
    var carvedTemporaryBytes = 0;
    var carvedTempBytesReclaimed = 0;
    final volumesScanned = <String>{};
    var duplicateDirectorySkips = 0;
    var repeatedCursorDetections = 0;
    String? completionReason;
    var pageCount = 0;

    for (final provider in providers) {
      String? token;
      final seenTokens = <String>{};
      do {
        if (cancellationToken?.isCancelled == true) {
          return _cancelled(
            visited,
            records.length,
            duplicateRecords,
            invalidFiles,
            unavailableFiles,
            filesExamined,
            directoriesExamined,
            volumesScanned,
          );
        }
        visited.add(provider.kind);
        final result = await provider.getPage(
          DeepRecoveryProviderRequest(
            pageSize: pageSize,
            source: source,
            profile: profile,
            continuationToken: token,
            currentMediaLocationKeys: token == null
                ? currentMediaLocationKeys
                : const {},
          ),
        );
        if (result is DeepRecoveryProviderUnavailable) {
          return DeepRecoveryEngineResult(
            completed: false,
            byDisposition: const {},
            possibleCopies: const PossibleCopiesDiscoveryResult(
              groups: [],
              verifiedDeletedCount: 0,
            ),
            providersVisited: Set.unmodifiable(visited),
            recordsDiscovered: records.length,
            duplicateRecordsSuppressed: duplicateRecords,
            invalidFilesRejected: invalidFiles,
            unavailableFiles: unavailableFiles,
            filesExamined: filesExamined,
            directoriesExamined: directoriesExamined,
            volumesScanned: Set.unmodifiable(volumesScanned),
            duplicateDirectorySkips: duplicateDirectorySkips,
            repeatedCursorDetections: repeatedCursorDetections,
            completionReason: result.message,
            failureAvailability: result.availability,
            failureMessage: result.message,
          );
        }
        final page = result as DeepRecoveryProviderPage;
        pageCount++;
        filesExamined += page.filesExamined;
        directoriesExamined += page.directoriesExamined;
        entriesExamined += page.entriesExamined;
        currentFilesSkipped += page.currentFilesSkipped;
        signatureCacheHits += page.signatureCacheHits;
        signatureCacheMisses += page.signatureCacheMisses;
        nativeTraversalMillis += page.nativeTraversalMillis;
        carvedTemporaryBytes += page.carvedTemporaryBytes;
        carvedTempBytesReclaimed += page.carvedTempBytesReclaimed;
        volumesScanned.addAll(page.volumesScanned);
        duplicateDirectorySkips += page.duplicateDirectorySkips;
        repeatedCursorDetections += page.repeatedCursorDetections;
        completionReason = page.completionReason ?? completionReason;
        invalidFiles += page.invalidFilesRejected;
        unavailableFiles += page.unavailableFiles;
        unsupportedFiles += page.unsupportedFiles;
        for (final record in page.items) {
          if (source != MediaSource.unknown &&
              record.candidate.source != source) {
            continue;
          }
          final key = _stableKey(record.candidate);
          if (records.containsKey(key)) {
            duplicateRecords++;
          } else {
            records[key] = record;
          }
        }
        onProgress?.call(
          DeepRecoveryEngineProgress(
            pageCount: pageCount,
            filesExamined: filesExamined,
            directoriesExamined: directoriesExamined,
            candidatesFound: records.length,
            pageFilesExamined: page.filesExamined,
            pageDirectoriesConsumed: page.directoryWorkConsumed,
            pageRecordsReturned: page.items.length,
            remainingDirectoryQueue: page.remainingDirectoryQueue,
            visitedDirectoryCount: page.visitedDirectoryCount,
            duplicateDirectorySkips: page.duplicateDirectorySkips,
            repeatedCursorDetections: page.repeatedCursorDetections,
            providerExhausted: page.providerExhausted,
            completionReason: page.completionReason,
            cursorIdentifier: page.nextContinuationToken == null
                ? 'final'
                : page.nextContinuationToken.hashCode
                      .toUnsigned(32)
                      .toRadixString(16),
            currentArea: page.currentArea,
          ),
        );
        final nextToken = page.nextContinuationToken;
        if (page.providerExhausted &&
            (page.completionReason == 'repeatedCursor' ||
                page.completionReason == 'noProgress')) {
          return DeepRecoveryEngineResult(
            completed: false,
            byDisposition: const {},
            possibleCopies: const PossibleCopiesDiscoveryResult(
              groups: [],
              verifiedDeletedCount: 0,
            ),
            providersVisited: Set.unmodifiable(visited),
            recordsDiscovered: records.length,
            duplicateRecordsSuppressed: duplicateRecords,
            invalidFilesRejected: invalidFiles,
            unavailableFiles: unavailableFiles,
            filesExamined: filesExamined,
            directoriesExamined: directoriesExamined,
            volumesScanned: Set.unmodifiable(volumesScanned),
            duplicateDirectorySkips: duplicateDirectorySkips,
            repeatedCursorDetections: repeatedCursorDetections,
            completionReason: page.completionReason,
            failureAvailability: DeepProviderAvailability.failed,
            failureMessage: 'Deep Scan did not reach a safe completion point.',
          );
        }
        if (page.providerExhausted) {
          completionReason = page.completionReason ?? 'exhausted';
          token = null;
        } else if (nextToken == null) {
          token = null;
        } else if (nextToken == token || !seenTokens.add(nextToken)) {
          repeatedCursorDetections++;
          completionReason = 'repeatedCursor';
          token = null;
        } else {
          token = nextToken;
        }
      } while (token != null);
    }

    if (cancellationToken?.isCancelled == true) {
      return _cancelled(
        visited,
        records.length,
        duplicateRecords,
        invalidFiles,
        unavailableFiles,
        filesExamined,
        directoriesExamined,
        volumesScanned,
      );
    }

    final buckets = <DeepRecoveryDisposition, List<MediaCandidate>>{};
    final deleted = <MediaCandidate>[];
    final accessible = <MediaCandidate>[];
    final relationships = <PossibleCopyRelationship>[];
    for (final record in records.values) {
      final candidate = record.candidate;
      final disposition = record.isAccessibleCurrentMedia
          ? DeepRecoveryDisposition.existingMedia
          : classifier.classify(
              candidate: candidate,
              existingMediaDecision: exclusionEngine.evaluate(
                candidate,
                existingMediaIndex,
              ),
              provenCopyType: record.hasStrongCopyRelationship
                  ? record.provenCopyType
                  : null,
            );
      (buckets[disposition] ??= []).add(candidate);
      if (disposition == DeepRecoveryDisposition.verifiedDeleted ||
          disposition == DeepRecoveryDisposition.protectedDeleted) {
        deleted.add(candidate);
      } else {
        accessible.add(candidate);
      }
      if (record.hasStrongCopyRelationship &&
          record.candidate.source == source) {
        relationships.add(
          PossibleCopyRelationship(
            originalCandidateId: record.relatedDeletedCandidateId!,
            copyCandidateId: candidate.id,
            type: record.provenCopyType!,
            evidence: record.relationshipEvidence!,
          ),
        );
      }
    }
    for (final values in buckets.values) {
      values.sort((a, b) => a.id.compareTo(b.id));
    }
    final copies = possibleCopiesDiscovery.discover(
      verifiedDeletedCandidates: deleted,
      accessibleCandidates: accessible,
      existingMediaIndex: existingMediaIndex,
      relationships: relationships,
    );
    return DeepRecoveryEngineResult(
      completed: true,
      byDisposition:
          Map<DeepRecoveryDisposition, List<MediaCandidate>>.unmodifiable({
            for (final entry in buckets.entries)
              entry.key: List<MediaCandidate>.unmodifiable(entry.value),
          }),
      possibleCopies: copies,
      providersVisited: Set.unmodifiable(visited),
      recordsDiscovered: records.length,
      duplicateRecordsSuppressed: duplicateRecords,
      invalidFilesRejected: invalidFiles,
      unavailableFiles: unavailableFiles,
      unsupportedFiles: unsupportedFiles,
      filesExamined: filesExamined,
      directoriesExamined: directoriesExamined,
      entriesExamined: entriesExamined,
      currentFilesSkipped: currentFilesSkipped,
      signatureCacheHits: signatureCacheHits,
      signatureCacheMisses: signatureCacheMisses,
      nativeTraversalMillis: nativeTraversalMillis,
      carvedTemporaryBytes: carvedTemporaryBytes,
      carvedTempBytesReclaimed: carvedTempBytesReclaimed,
      volumesScanned: Set.unmodifiable(volumesScanned),
      duplicateDirectorySkips: duplicateDirectorySkips,
      repeatedCursorDetections: repeatedCursorDetections,
      completionReason: completionReason ?? 'exhausted',
    );
  }

  String _stableKey(MediaCandidate candidate) {
    final uri = candidate.contentUri ?? candidate.documentUri;
    if (uri != null) return 'uri:$uri';
    final volume = candidate.storageVolumeName;
    final id = candidate.mediaStoreId;
    if (volume != null && id != null) return 'media:$volume:$id';
    return 'candidate:${candidate.id}';
  }

  DeepRecoveryEngineResult _cancelled(
    Set<DeepRecoveryProviderKind> visited,
    int discovered,
    int duplicates,
    int invalid,
    int unavailable,
    int filesExamined,
    int directoriesExamined,
    Set<String> volumesScanned,
  ) => DeepRecoveryEngineResult(
    completed: false,
    byDisposition: const {},
    possibleCopies: const PossibleCopiesDiscoveryResult(
      groups: [],
      verifiedDeletedCount: 0,
    ),
    providersVisited: Set.unmodifiable(visited),
    recordsDiscovered: discovered,
    duplicateRecordsSuppressed: duplicates,
    invalidFilesRejected: invalid,
    unavailableFiles: unavailable,
    filesExamined: filesExamined,
    directoriesExamined: directoriesExamined,
    volumesScanned: Set.unmodifiable(volumesScanned),
  );
}

class DeepRecoveryEngineProgress {
  const DeepRecoveryEngineProgress({
    required this.pageCount,
    required this.filesExamined,
    required this.directoriesExamined,
    required this.candidatesFound,
    this.pageFilesExamined = 0,
    this.pageDirectoriesConsumed = 0,
    this.pageRecordsReturned = 0,
    this.remainingDirectoryQueue = 0,
    this.visitedDirectoryCount = 0,
    this.duplicateDirectorySkips = 0,
    this.repeatedCursorDetections = 0,
    this.providerExhausted = false,
    this.completionReason,
    this.cursorIdentifier,
    this.currentArea,
  });
  final int pageCount;
  final int filesExamined;
  final int directoriesExamined;
  final int candidatesFound;
  final int pageFilesExamined;
  final int pageDirectoriesConsumed;
  final int pageRecordsReturned;
  final int remainingDirectoryQueue;
  final int visitedDirectoryCount;
  final int duplicateDirectorySkips;
  final int repeatedCursorDetections;
  final bool providerExhausted;
  final String? completionReason;
  final String? cursorIdentifier;
  final String? currentArea;
}
