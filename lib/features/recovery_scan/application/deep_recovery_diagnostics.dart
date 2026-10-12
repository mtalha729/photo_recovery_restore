class DeepRecoveryDiagnostics {
  const DeepRecoveryDiagnostics({
    this.androidApiLevel,
    this.accessMode = 'unknown',
    this.deepCapabilityState = 'unknown',
    this.allFilesAccessGranted = false,
    this.volumesScanned = const {},
    this.foldersVisited = 0,
    this.filesExamined = 0,
    this.currentRecordsScanned = 0,
    this.trashCandidates = 0,
    this.safDocumentsScanned = 0,
    this.unindexedFilesFound = 0,
    this.signatureMatches = 0,
    this.standaloneImageCandidates = 0,
    this.cacheCandidates = 0,
    this.messagingCandidates = 0,
    this.copyCandidates = 0,
    this.excludedExisting = 0,
    this.duplicateRecordsSuppressed = 0,
    this.invalidFilesRejected = 0,
    this.unavailableFiles = 0,
    this.unsupportedFiles = 0,
    this.sourceFilteredItems = 0,
    this.finalVerifiedDeleted = 0,
    this.finalFullQualityCopies = 0,
    this.finalReducedCopies = 0,
    this.finalThumbnailCopies = 0,
    this.unknownSourceRetained = 0,
    this.trashLikeCandidates = 0,
    this.thumbnailCandidates = 0,
    this.removableCandidates = 0,
    this.extensionMismatchCandidates = 0,
    this.embeddedPayloads = 0,
    this.duplicateDirectorySkips = 0,
    this.repeatedCursorDetections = 0,
    this.completionReason = 'unknown',
    this.elapsed = Duration.zero,
    this.mediaInventoryMs = 0,
    this.verifiedTrashMs = 0,
    this.firstValidResultMs,
    this.existingIndexBuildMs = 0,
    this.nativeTraversalMs = 0,
    this.entriesExamined = 0,
    this.currentFilesSkipped = 0,
    this.signatureCacheHits = 0,
    this.signatureCacheMisses = 0,
    this.carvedTemporaryBytes = 0,
    this.carvedTempBytesReclaimed = 0,
  });

  final int? androidApiLevel;
  final String accessMode;
  final String deepCapabilityState;
  final bool allFilesAccessGranted;
  final Set<String> volumesScanned;
  final int foldersVisited;
  final int filesExamined;
  final int currentRecordsScanned;
  final int trashCandidates;
  final int safDocumentsScanned;
  final int unindexedFilesFound;
  final int signatureMatches;
  final int standaloneImageCandidates;
  final int cacheCandidates;
  final int messagingCandidates;
  final int copyCandidates;
  final int excludedExisting;
  final int duplicateRecordsSuppressed;
  final int invalidFilesRejected;
  final int unavailableFiles;
  final int unsupportedFiles;
  final int sourceFilteredItems;
  final int finalVerifiedDeleted;
  final int finalFullQualityCopies;
  final int finalReducedCopies;
  final int finalThumbnailCopies;
  final int unknownSourceRetained;
  final int trashLikeCandidates;
  final int thumbnailCandidates;
  final int removableCandidates;
  final int extensionMismatchCandidates;
  final int embeddedPayloads;
  final int duplicateDirectorySkips;
  final int repeatedCursorDetections;
  final String completionReason;
  final Duration elapsed;
  final int mediaInventoryMs;
  final int verifiedTrashMs;
  final int? firstValidResultMs;
  final int existingIndexBuildMs;
  final int nativeTraversalMs;
  final int entriesExamined;
  final int currentFilesSkipped;
  final int signatureCacheHits;
  final int signatureCacheMisses;
  final int carvedTemporaryBytes;
  final int carvedTempBytesReclaimed;

  int get finalPossibleCopies =>
      finalFullQualityCopies + finalReducedCopies + finalThumbnailCopies;
  int get visibleFinalResults => finalVerifiedDeleted + finalPossibleCopies;

  String toDebugSummary() =>
      'Deep recovery: api=${androidApiLevel ?? 'unknown'}, access=$accessMode, deep=$deepCapabilityState, allFiles=$allFilesAccessGranted, '
      'volumes=${volumesScanned.length}, folders=$foldersVisited, '
      'files=$filesExamined, current=$currentRecordsScanned, trash=$trashCandidates, '
      'saf=$safDocumentsScanned, unindexed=$unindexedFilesFound, '
      'signatures=$signatureMatches, standalone=$standaloneImageCandidates, cache=$cacheCandidates, messaging=$messagingCandidates, '
      'copies=$copyCandidates, excludedExisting=$excludedExisting, '
      'duplicates=$duplicateRecordsSuppressed, invalid=$invalidFilesRejected, '
      'unavailable=$unavailableFiles, unsupported=$unsupportedFiles, sourceFiltered=$sourceFilteredItems, '
      'verifiedDeleted=$finalVerifiedDeleted, fullCopies=$finalFullQualityCopies, '
      'reducedCopies=$finalReducedCopies, thumbnails=$finalThumbnailCopies, '
      'unknownRetained=$unknownSourceRetained, trashLike=$trashLikeCandidates, '
      'thumbnailCandidates=$thumbnailCandidates, removable=$removableCandidates, '
      'misnamed=$extensionMismatchCandidates, embedded=$embeddedPayloads, duplicateDirs=$duplicateDirectorySkips, '
      'repeatedCursors=$repeatedCursorDetections, completion=$completionReason, '
      'visible=$visibleFinalResults, '
      'inventoryMs=$mediaInventoryMs, indexMs=$existingIndexBuildMs, nativeMs=$nativeTraversalMs, '
      'entries=$entriesExamined, currentSkipped=$currentFilesSkipped, cacheHits=$signatureCacheHits, cacheMisses=$signatureCacheMisses, carvedBytes=$carvedTemporaryBytes, reclaimedCarvedBytes=$carvedTempBytesReclaimed, '
      'elapsedMs=${elapsed.inMilliseconds}';
}

class DeepRecoveryDiagnosticsBuilder {
  final Stopwatch _stopwatch = Stopwatch()..start();
  int? androidApiLevel;
  String accessMode = 'unknown';
  String deepCapabilityState = 'unknown';
  bool allFilesAccessGranted = false;
  final Set<String> volumesScanned = {};
  int foldersVisited = 0;
  int filesExamined = 0;
  int currentRecordsScanned = 0;
  int trashCandidates = 0;
  int safDocumentsScanned = 0;
  int unindexedFilesFound = 0;
  int signatureMatches = 0;
  int standaloneImageCandidates = 0;
  int cacheCandidates = 0;
  int messagingCandidates = 0;
  int copyCandidates = 0;
  int excludedExisting = 0;
  int duplicateRecordsSuppressed = 0;
  int invalidFilesRejected = 0;
  int unavailableFiles = 0;
  int unsupportedFiles = 0;
  int sourceFilteredItems = 0;
  int finalVerifiedDeleted = 0;
  int finalFullQualityCopies = 0;
  int finalReducedCopies = 0;
  int finalThumbnailCopies = 0;
  int unknownSourceRetained = 0;
  int trashLikeCandidates = 0;
  int thumbnailCandidates = 0;
  int removableCandidates = 0;
  int extensionMismatchCandidates = 0;
  int embeddedPayloads = 0;
  int duplicateDirectorySkips = 0;
  int repeatedCursorDetections = 0;
  String completionReason = 'unknown';
  int mediaInventoryMs = 0;
  int verifiedTrashMs = 0;
  int? firstValidResultMs;

  void markFirstValidResult() =>
      firstValidResultMs ??= _stopwatch.elapsedMilliseconds;
  int existingIndexBuildMs = 0;
  int nativeTraversalMs = 0;
  int entriesExamined = 0;
  int currentFilesSkipped = 0;
  int signatureCacheHits = 0;
  int signatureCacheMisses = 0;
  int carvedTemporaryBytes = 0;
  int carvedTempBytesReclaimed = 0;

  DeepRecoveryDiagnostics build() => DeepRecoveryDiagnostics(
    androidApiLevel: androidApiLevel,
    accessMode: accessMode,
    deepCapabilityState: deepCapabilityState,
    allFilesAccessGranted: allFilesAccessGranted,
    volumesScanned: Set.unmodifiable(volumesScanned),
    foldersVisited: foldersVisited,
    filesExamined: filesExamined,
    currentRecordsScanned: currentRecordsScanned,
    trashCandidates: trashCandidates,
    safDocumentsScanned: safDocumentsScanned,
    unindexedFilesFound: unindexedFilesFound,
    signatureMatches: signatureMatches,
    standaloneImageCandidates: standaloneImageCandidates,
    cacheCandidates: cacheCandidates,
    messagingCandidates: messagingCandidates,
    copyCandidates: copyCandidates,
    excludedExisting: excludedExisting,
    duplicateRecordsSuppressed: duplicateRecordsSuppressed,
    invalidFilesRejected: invalidFilesRejected,
    unavailableFiles: unavailableFiles,
    unsupportedFiles: unsupportedFiles,
    sourceFilteredItems: sourceFilteredItems,
    finalVerifiedDeleted: finalVerifiedDeleted,
    finalFullQualityCopies: finalFullQualityCopies,
    finalReducedCopies: finalReducedCopies,
    finalThumbnailCopies: finalThumbnailCopies,
    unknownSourceRetained: unknownSourceRetained,
    trashLikeCandidates: trashLikeCandidates,
    thumbnailCandidates: thumbnailCandidates,
    removableCandidates: removableCandidates,
    extensionMismatchCandidates: extensionMismatchCandidates,
    embeddedPayloads: embeddedPayloads,
    duplicateDirectorySkips: duplicateDirectorySkips,
    repeatedCursorDetections: repeatedCursorDetections,
    completionReason: completionReason,
    elapsed: _stopwatch.elapsed,
    mediaInventoryMs: mediaInventoryMs,
    verifiedTrashMs: verifiedTrashMs,
    firstValidResultMs: firstValidResultMs,
    existingIndexBuildMs: existingIndexBuildMs,
    nativeTraversalMs: nativeTraversalMs,
    entriesExamined: entriesExamined,
    currentFilesSkipped: currentFilesSkipped,
    signatureCacheHits: signatureCacheHits,
    signatureCacheMisses: signatureCacheMisses,
    carvedTemporaryBytes: carvedTemporaryBytes,
    carvedTempBytesReclaimed: carvedTempBytesReclaimed,
  );
}
