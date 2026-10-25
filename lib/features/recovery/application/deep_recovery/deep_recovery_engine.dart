import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../possible_copies/possible_copies_discovery.dart';
import '../possible_copies/possible_copy_models.dart';
import '../scan_runtime/scan_cancellation.dart';
import '../../domain/media_candidate.dart';
import '../../domain/deletion_evidence.dart';
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
    this.existingRecordsExcluded = 0,
    this.lowerPriorityRecordsOmitted = 0,
    required this.duplicateRecordsSuppressed,
    required this.invalidFilesRejected,
    required this.unavailableFiles,
    this.unsupportedFiles = 0,
    this.unavailableDirectories = 0,
    required this.filesExamined,
    required this.directoriesExamined,
    this.rootDirectoriesOpened = 0,
    this.signatureFilesInspected = 0,
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
  final int existingRecordsExcluded;
  final int lowerPriorityRecordsOmitted;
  final int duplicateRecordsSuppressed;
  final int invalidFilesRejected;
  final int unavailableFiles;
  final int unsupportedFiles;
  final int unavailableDirectories;
  final int filesExamined;
  final int directoriesExamined;
  final int rootDirectoriesOpened;
  final int signatureFilesInspected;
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
    Set<String> alreadyDiscoveredStorageLocationKeys = const {},
    required MediaSource source,
    PhotoRecoveryProfile profile = PhotoRecoveryProfile.fastDeep,
    ScanCancellationToken? cancellationToken,
    int pageSize = 200,
    void Function(DeepRecoveryEngineProgress progress)? onProgress,
  }) async {
    final records = <String, DeepRecoveryDiscoveryRecord>{};
    final dispositions = <String, DeepRecoveryDisposition>{};
    final existingStorageLocationKeys = Set<String>.unmodifiable({
      ...existingMediaIndex.ordinaryStorageLocationKeys,
      ...alreadyDiscoveredStorageLocationKeys,
    });
    final visited = <DeepRecoveryProviderKind>{};
    var duplicateRecords = 0;
    var invalidFiles = 0;
    var unavailableFiles = 0;
    var unsupportedFiles = 0;
    var unavailableDirectories = 0;
    var filesExamined = 0;
    var directoriesExamined = 0;
    var rootDirectoriesOpened = 0;
    var signatureFilesInspected = 0;
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
    var existingRecordsExcluded = 0;
    var retainedExistingRecords = 0;
    var retainedNonCandidates = 0;
    var retainedGenericCopies = 0;
    var lowerPriorityRecordsOmitted = 0;

    var wasCancelled = false;
    var resultLimitReached = false;
    DeepProviderAvailability? failureAvailability;
    String? failureMessage;
    final streamedCopyKeys = <String>{};

    providerLoop:
    for (final provider in providers) {
      String? token;
      final seenTokens = <String>{};
      while (true) {
        if (cancellationToken?.isCancelled == true) {
          wasCancelled = true;
          completionReason = 'cancelled';
          break providerLoop;
        }
        visited.add(provider.kind);
        final result = await provider.getPage(
          DeepRecoveryProviderRequest(
            pageSize: pageSize,
            source: source,
            profile: profile,
            continuationToken: token,
            existingStorageLocationKeys: existingStorageLocationKeys,
          ),
        );
        if (result is DeepRecoveryProviderUnavailable) {
          if (cancellationToken?.isCancelled == true) {
            wasCancelled = true;
            completionReason = 'cancelled';
          } else {
            failureAvailability = result.availability;
            failureMessage =
                result.message ?? 'Deep provider became unavailable.';
            completionReason = 'providerUnavailable';
          }
          break providerLoop;
        }

        final page = result as DeepRecoveryProviderPage;
        pageCount++;
        filesExamined += page.filesExamined;
        directoriesExamined += page.directoriesExamined;
        if (page.rootDirectoriesOpened > rootDirectoriesOpened) {
          rootDirectoriesOpened = page.rootDirectoriesOpened;
        }
        if (page.signatureFilesInspected > signatureFilesInspected) {
          signatureFilesInspected = page.signatureFilesInspected;
        }
        entriesExamined += page.entriesExamined;
        currentFilesSkipped += page.currentFilesSkipped;
        signatureCacheHits += page.signatureCacheHits;
        signatureCacheMisses += page.signatureCacheMisses;
        nativeTraversalMillis = page.nativeTraversalMillis;
        carvedTemporaryBytes = page.carvedTemporaryBytes;
        carvedTempBytesReclaimed = page.carvedTempBytesReclaimed;
        volumesScanned.addAll(page.volumesScanned);
        duplicateDirectorySkips += page.duplicateDirectorySkips;
        repeatedCursorDetections += page.repeatedCursorDetections;
        completionReason = page.completionReason ?? completionReason;
        invalidFiles += page.invalidFilesRejected;
        unavailableFiles += page.unavailableFiles;
        unsupportedFiles += page.unsupportedFiles;
        unavailableDirectories += page.unavailableDirectories;
        final pageCopyCandidates = <MediaCandidate>[];
        for (final record in page.items) {
          if (source != MediaSource.unknown &&
              record.candidate.source != source) {
            continue;
          }
          final key = _stableKey(record.candidate);
          if (records.containsKey(key)) {
            duplicateRecords++;
            continue;
          }
          final disposition = record.isAccessibleCurrentMedia
              ? DeepRecoveryDisposition.existingMedia
              : !_isRecoveryRelevantArtifact(record)
              ? DeepRecoveryDisposition.existingMedia
              : classifier.classify(
                  candidate: record.candidate,
                  existingMediaDecision: exclusionEngine.evaluate(
                    record.candidate,
                    existingMediaIndex,
                  ),
                  provenCopyType: record.hasStrongCopyRelationship
                      ? record.provenCopyType
                      : null,
                );
          if (records.length >=
                  _maximumRetainedRecords - _reservedLateArtifactSlots &&
              disposition != DeepRecoveryDisposition.verifiedDeleted &&
              disposition != DeepRecoveryDisposition.protectedCopy &&
              !record.candidate.discoveryEvidence.isEmbeddedPayload) {
            lowerPriorityRecordsOmitted++;
            continue;
          }
          if (disposition == DeepRecoveryDisposition.existingMedia) {
            existingRecordsExcluded++;
            if (retainedExistingRecords >= _maximumRetainedExistingRecords) {
              continue;
            }
            retainedExistingRecords++;
          } else if (!_isPossibleCopy(disposition) &&
              disposition != DeepRecoveryDisposition.verifiedDeleted &&
              disposition != DeepRecoveryDisposition.protectedCopy) {
            if (retainedNonCandidates >= _maximumRetainedNonCandidates) {
              lowerPriorityRecordsOmitted++;
              continue;
            }
            retainedNonCandidates++;
          } else if (_isPossibleCopy(disposition) &&
              !_isHighValueArtifact(record)) {
            if (retainedGenericCopies >= _maximumRetainedGenericCopies) {
              lowerPriorityRecordsOmitted++;
              continue;
            }
            retainedGenericCopies++;
          }
          if (records.length >= _maximumRetainedRecords) {
            resultLimitReached = true;
            break;
          }
          records[key] = record;
          dispositions[key] = disposition;

          if (record.isAccessibleCurrentMedia) continue;
          if (_isPossibleCopy(disposition) && streamedCopyKeys.add(key)) {
            pageCopyCandidates.add(record.candidate);
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
            unavailableDirectories: page.unavailableDirectories,
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
            possibleCopyCandidates: List.unmodifiable(pageCopyCandidates),
          ),
        );

        if (cancellationToken?.isCancelled == true) {
          wasCancelled = true;
          completionReason = 'cancelled';
          break providerLoop;
        }
        if (resultLimitReached) {
          failureAvailability = DeepProviderAvailability.failed;
          failureMessage = 'Deep scan stopped at the safe in-memory result limit; partial results are kept.';
          completionReason = 'resultMemoryLimit';
          await provider.cancelActiveScan();
          break providerLoop;
        }
        final nextToken = page.nextContinuationToken;
        if (page.providerExhausted) {
          if (page.completionReason == 'repeatedCursor' ||
              page.completionReason == 'noProgress' ||
              page.completionReason == 'exhaustedWithUnreadableEntries' ||
              page.completionReason == 'exhaustedWithResourceLimit' ||
              page.completionReason == 'exhaustedWithCarvedStorageLimit') {
            failureAvailability = DeepProviderAvailability.failed;
            failureMessage = switch (page.completionReason) {
              'exhaustedWithUnreadableEntries' => 'Some shared-storage files or folders could not be read; coverage is partial.',
              'exhaustedWithResourceLimit' => 'Deep scan reached a safe traversal resource limit; coverage is partial.',
              'exhaustedWithCarvedStorageLimit' => 'Embedded-image cache reached its safe storage limit; other discovered results are retained.',
              _ => 'Deep scan did not reach a safe completion point.',
            };
            completionReason = page.completionReason;
            break providerLoop;
          }
          completionReason = page.completionReason ?? 'exhausted';
          break;
        }
        if (nextToken == null) {
          failureAvailability = DeepProviderAvailability.failed;
          failureMessage =
              'Deep provider stopped without an exhaustion signal.';
          completionReason = 'missingContinuation';
          break providerLoop;
        }
        if (nextToken == token || !seenTokens.add(nextToken)) {
          repeatedCursorDetections++;
          failureAvailability = DeepProviderAvailability.failed;
          failureMessage = 'Deep provider repeated a continuation state.';
          completionReason = 'repeatedCursor';
          break providerLoop;
        }
        token = nextToken;
      }
    }

    if (lowerPriorityRecordsOmitted > 0 &&
        failureAvailability == null &&
        !wasCancelled) {
      failureAvailability = DeepProviderAvailability.failed;
      failureMessage = 'Lower-priority records exceeded the bounded retention budget; recovery artifacts found later were still scanned and kept.';
      completionReason = 'lowerPriorityRetentionLimit';
    }

    final buckets = <DeepRecoveryDisposition, List<MediaCandidate>>{};
    final deleted = <MediaCandidate>[];
    final accessible = <MediaCandidate>[];
    final relationships = <PossibleCopyRelationship>[];
    for (final entry in records.entries) {
      final record = entry.value;
      final candidate = record.candidate;
      final disposition = dispositions[entry.key]!;
      (buckets[disposition] ??= []).add(candidate);
      if (disposition == DeepRecoveryDisposition.verifiedDeleted) {
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
      completed: !wasCancelled && failureAvailability == null,
      byDisposition:
          Map<DeepRecoveryDisposition, List<MediaCandidate>>.unmodifiable({
            for (final entry in buckets.entries)
              entry.key: List<MediaCandidate>.unmodifiable(entry.value),
          }),
      possibleCopies: copies,
      providersVisited: Set.unmodifiable(visited),
      recordsDiscovered: records.length,
      existingRecordsExcluded: existingRecordsExcluded,
      lowerPriorityRecordsOmitted: lowerPriorityRecordsOmitted,
      duplicateRecordsSuppressed: duplicateRecords,
      invalidFilesRejected: invalidFiles,
      unavailableFiles: unavailableFiles,
      unsupportedFiles: unsupportedFiles,
      unavailableDirectories: unavailableDirectories,
      filesExamined: filesExamined,
      directoriesExamined: directoriesExamined,
      rootDirectoriesOpened: rootDirectoriesOpened,
      signatureFilesInspected: signatureFilesInspected,
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
      failureAvailability: failureAvailability,
      failureMessage: failureMessage,
    );
  }

  bool _isPossibleCopy(DeepRecoveryDisposition disposition) =>
      disposition == DeepRecoveryDisposition.possibleFullQualityCopy ||
      disposition == DeepRecoveryDisposition.possibleLowerQualityCopy ||
      disposition == DeepRecoveryDisposition.possibleUnknownQualityCopy ||
      disposition == DeepRecoveryDisposition.thumbnailCopy;

  bool _isHighValueArtifact(DeepRecoveryDiscoveryRecord record) {
    final evidence = record.candidate.discoveryEvidence;
    return record.candidate.deletionEvidence.reasons.contains(
          DeletionEvidenceReason.systemTrashRecord,
        ) ||
        evidence.isTrashLike ||
        evidence.isCacheLike ||
        evidence.isRecoveryCopyLike ||
        evidence.isThumbnailLike ||
        evidence.isEmbeddedPayload ||
        record.hasStrongCopyRelationship;
  }

  bool _isRecoveryRelevantArtifact(DeepRecoveryDiscoveryRecord record) {
    final evidence = record.candidate.discoveryEvidence;
    return evidence.isTrashLike ||
        evidence.isCacheLike ||
        evidence.isRecoveryCopyLike ||
        evidence.isThumbnailLike ||
        evidence.isEmbeddedPayload ||
        evidence.isHidden ||
        record.hasStrongCopyRelationship;
  }

  static const int _maximumRetainedRecords = 10000;
  static const int _reservedLateArtifactSlots = 1000;
  static const int _maximumRetainedExistingRecords = 256;
  static const int _maximumRetainedNonCandidates = 256;
  static const int _maximumRetainedGenericCopies = 2000;

  String _stableKey(MediaCandidate candidate) {
    final uri = candidate.contentUri ?? candidate.documentUri;
    if (uri != null) return 'uri:$uri';
    final volume = candidate.storageVolumeName;
    final id = candidate.mediaStoreId;
    if (volume != null && id != null) return 'media:$volume:$id';
    return 'candidate:${candidate.id}';
  }
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
    this.unavailableDirectories = 0,
    this.remainingDirectoryQueue = 0,
    this.visitedDirectoryCount = 0,
    this.duplicateDirectorySkips = 0,
    this.repeatedCursorDetections = 0,
    this.providerExhausted = false,
    this.completionReason,
    this.cursorIdentifier,
    this.currentArea,
    this.possibleCopyCandidates = const [],
  });
  final int pageCount;
  final int filesExamined;
  final int directoriesExamined;
  final int candidatesFound;
  final int pageFilesExamined;
  final int pageDirectoriesConsumed;
  final int pageRecordsReturned;
  final int unavailableDirectories;
  final int remainingDirectoryQueue;
  final int visitedDirectoryCount;
  final int duplicateDirectorySkips;
  final int repeatedCursorDetections;
  final bool providerExhausted;
  final String? completionReason;
  final String? cursorIdentifier;
  final String? currentArea;
  final List<MediaCandidate> possibleCopyCandidates;
}
