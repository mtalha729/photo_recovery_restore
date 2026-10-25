class DeepRecoveryDiagnostics {
  const DeepRecoveryDiagnostics({
    this.androidApiLevel,
    this.accessMode = 'unknown',
    this.deepCapabilityState = 'unknown',
    this.currentMediaInventoryState = 'notStarted',
    this.verifiedTrashProviderState = 'notStarted',
    this.deepProviderState = 'notRequested',
    this.mediaInventoryPages = 0,
    this.verifiedTrashPages = 0,
    this.deepProviderPages = 0,
    this.selectedFolderProviderState = 'notRequested',
    this.selectedFolderPages = 0,
    this.selectedFolderCopies = 0,
    this.allFilesAccessGranted = false,
    this.volumesScanned = const {},
    this.rootDirectoriesOpened = 0,
    this.signatureFilesInspected = 0,
    this.foldersVisited = 0,
    this.filesExamined = 0,
    this.currentRecordsScanned = 0,
    this.mediaStoreRowsReturned = 0,
    this.currentPhotosMapped = 0,
    this.currentRowsRejected = 0,
    this.currentDuplicatesSuppressed = 0,
    this.trashCandidates = 0,
    this.rawTrashRows = 0,
    this.deepRecordsDiscovered = 0,
    this.mediaStoreArtifactsDiscovered = 0,
    this.lowerPriorityRecordsOmitted = 0,
    this.inaccessibleTrashRows = 0,
    this.unindexedFilesFound = 0,
    this.signatureMatches = 0,
    this.standaloneImageCandidates = 0,
    this.cacheCandidates = 0,
    this.messagingCandidates = 0,
    this.copyCandidates = 0,
    this.excludedExisting = 0,
    this.duplicateRecordsSuppressed = 0,
    this.invalidFilesRejected = 0,
    this.ineligibleRecordsRejected = 0,
    this.unavailableFiles = 0,
    this.unavailableDirectories = 0,
    this.unsupportedFiles = 0,
    this.sourceFilteredItems = 0,
    this.finalVerifiedDeleted = 0,
    this.finalFullQualityCopies = 0,
    this.finalReducedCopies = 0,
    this.finalUnknownQualityCopies = 0,
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
  final String currentMediaInventoryState;
  final String verifiedTrashProviderState;
  final String deepProviderState;
  final int mediaInventoryPages;
  final int verifiedTrashPages;
  final int deepProviderPages;
  final String selectedFolderProviderState;
  final int selectedFolderPages;
  final int selectedFolderCopies;
  final bool allFilesAccessGranted;
  final Set<String> volumesScanned;
  final int rootDirectoriesOpened;
  final int signatureFilesInspected;
  final int foldersVisited;
  final int filesExamined;
  final int currentRecordsScanned;
  final int mediaStoreRowsReturned;
  final int currentPhotosMapped;
  final int currentRowsRejected;
  final int currentDuplicatesSuppressed;
  final int trashCandidates;
  final int rawTrashRows;
  final int deepRecordsDiscovered;
  final int mediaStoreArtifactsDiscovered;
  final int lowerPriorityRecordsOmitted;
  final int inaccessibleTrashRows;
  final int unindexedFilesFound;
  final int signatureMatches;
  final int standaloneImageCandidates;
  final int cacheCandidates;
  final int messagingCandidates;
  final int copyCandidates;
  final int excludedExisting;
  final int duplicateRecordsSuppressed;
  final int invalidFilesRejected;
  final int ineligibleRecordsRejected;
  final int unavailableFiles;
  final int unavailableDirectories;
  final int unsupportedFiles;
  final int sourceFilteredItems;
  final int finalVerifiedDeleted;
  final int finalFullQualityCopies;
  final int finalReducedCopies;
  final int finalUnknownQualityCopies;
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
      finalFullQualityCopies +
      finalReducedCopies +
      finalUnknownQualityCopies +
      finalThumbnailCopies;
  int get visibleFinalResults => finalVerifiedDeleted + finalPossibleCopies;
  // Native records and raw trash rows can be ordinary current originals.
  // Only candidates retained for recovery belong in this headline count.
  int get discoveredCandidates => finalVerifiedDeleted + copyCandidates;
  int get rejectedCandidates =>
      invalidFilesRejected + ineligibleRecordsRejected;

  String toDebugSummary() =>
      'Recovery providers: api=${androidApiLevel ?? 'unknown'}, access=$accessMode, '
      'currentMedia=$currentMediaInventoryState($mediaInventoryPages pages), '
      'verifiedTrash=$verifiedTrashProviderState($verifiedTrashPages pages), '
      'deep=$deepProviderState($deepProviderPages pages), capability=$deepCapabilityState, '
      'selectedFolder=$selectedFolderProviderState($selectedFolderPages pages, $selectedFolderCopies copies), '
      'allFiles=$allFilesAccessGranted, '
      'volumesOpened=${volumesScanned.length}, rootsOpened=$rootDirectoriesOpened, foldersOpened=$foldersVisited, '
      'files=$filesExamined, current=$currentRecordsScanned, mediaStoreRows=$mediaStoreRowsReturned, currentMapped=$currentPhotosMapped, currentRejected=$currentRowsRejected, currentDuplicates=$currentDuplicatesSuppressed, trash=$trashCandidates/$rawTrashRows, inaccessibleTrash=$inaccessibleTrashRows, '
      'candidateCounts: discovered=$discoveredCandidates, rejected=$rejectedCandidates, duplicates=$duplicateRecordsSuppressed, possibleRecoverable=$finalPossibleCopies, verifiedDeleted=$finalVerifiedDeleted, mediaStoreArtifacts=$mediaStoreArtifactsDiscovered, '
      'deepRecordsRetained=$signatureMatches, standalone=$standaloneImageCandidates, cache=$cacheCandidates, messaging=$messagingCandidates, '
      'copies=$copyCandidates, excludedExisting=$excludedExisting, lowerPriorityOmitted=$lowerPriorityRecordsOmitted, '
      'duplicates=$duplicateRecordsSuppressed, invalid=$invalidFilesRejected, '
      'unavailableFiles=$unavailableFiles, unavailableDirs=$unavailableDirectories, unsupported=$unsupportedFiles, sourceFiltered=$sourceFilteredItems, '
      'verifiedDeleted=$finalVerifiedDeleted, fullCopies=$finalFullQualityCopies, '
      'reducedCopies=$finalReducedCopies, unknownQualityCopies=$finalUnknownQualityCopies, thumbnails=$finalThumbnailCopies, '
      'unknownRetained=$unknownSourceRetained, trashLike=$trashLikeCandidates, '
      'thumbnailCandidates=$thumbnailCandidates, removable=$removableCandidates, '
      'misnamed=$extensionMismatchCandidates, embedded=$embeddedPayloads, duplicateDirs=$duplicateDirectorySkips, '
      'repeatedCursors=$repeatedCursorDetections, completion=$completionReason, '
      'visible=$visibleFinalResults, '
      'inventoryMs=$mediaInventoryMs, indexMs=$existingIndexBuildMs, nativeMs=$nativeTraversalMs, '
      'entries=$entriesExamined, currentSkipped=$currentFilesSkipped, signaturesInspected=$signatureFilesInspected, cacheHits=$signatureCacheHits, cacheMisses=$signatureCacheMisses, carvedBytes=$carvedTemporaryBytes, reclaimedCarvedBytes=$carvedTempBytesReclaimed, '
      'elapsedMs=${elapsed.inMilliseconds}';
}

class DeepRecoveryDiagnosticsBuilder {
  final Stopwatch _stopwatch = Stopwatch()..start();
  int? androidApiLevel;
  String accessMode = 'unknown';
  String deepCapabilityState = 'unknown';
  String currentMediaInventoryState = 'notStarted';
  String verifiedTrashProviderState = 'notStarted';
  String deepProviderState = 'notRequested';
  int mediaInventoryPages = 0;
  int verifiedTrashPages = 0;
  int deepProviderPages = 0;
  String selectedFolderProviderState = 'notRequested';
  int selectedFolderPages = 0;
  int selectedFolderCopies = 0;
  bool allFilesAccessGranted = false;
  final Set<String> volumesScanned = {};
  int rootDirectoriesOpened = 0;
  int signatureFilesInspected = 0;
  int foldersVisited = 0;
  int filesExamined = 0;
  int currentRecordsScanned = 0;
  int mediaStoreRowsReturned = 0;
  int currentPhotosMapped = 0;
  int currentRowsRejected = 0;
  int currentDuplicatesSuppressed = 0;
  int trashCandidates = 0;
  int rawTrashRows = 0;
  int deepRecordsDiscovered = 0;
  int mediaStoreArtifactsDiscovered = 0;
  int lowerPriorityRecordsOmitted = 0;
  int inaccessibleTrashRows = 0;
  int unindexedFilesFound = 0;
  int signatureMatches = 0;
  int standaloneImageCandidates = 0;
  int cacheCandidates = 0;
  int messagingCandidates = 0;
  int copyCandidates = 0;
  int excludedExisting = 0;
  int duplicateRecordsSuppressed = 0;
  int invalidFilesRejected = 0;
  int ineligibleRecordsRejected = 0;
  int unavailableFiles = 0;
  int unavailableDirectories = 0;
  int unsupportedFiles = 0;
  int sourceFilteredItems = 0;
  int finalVerifiedDeleted = 0;
  int finalFullQualityCopies = 0;
  int finalReducedCopies = 0;
  int finalUnknownQualityCopies = 0;
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
    currentMediaInventoryState: currentMediaInventoryState,
    verifiedTrashProviderState: verifiedTrashProviderState,
    deepProviderState: deepProviderState,
    mediaInventoryPages: mediaInventoryPages,
    verifiedTrashPages: verifiedTrashPages,
    deepProviderPages: deepProviderPages,
    selectedFolderProviderState: selectedFolderProviderState,
    selectedFolderPages: selectedFolderPages,
    selectedFolderCopies: selectedFolderCopies,
    allFilesAccessGranted: allFilesAccessGranted,
    volumesScanned: Set.unmodifiable(volumesScanned),
    rootDirectoriesOpened: rootDirectoriesOpened,
    signatureFilesInspected: signatureFilesInspected,
    foldersVisited: foldersVisited,
    filesExamined: filesExamined,
    currentRecordsScanned: currentRecordsScanned,
    mediaStoreRowsReturned: mediaStoreRowsReturned,
    currentPhotosMapped: currentPhotosMapped,
    currentRowsRejected: currentRowsRejected,
    currentDuplicatesSuppressed: currentDuplicatesSuppressed,
    trashCandidates: trashCandidates,
    rawTrashRows: rawTrashRows,
    deepRecordsDiscovered: deepRecordsDiscovered,
    mediaStoreArtifactsDiscovered: mediaStoreArtifactsDiscovered,
    lowerPriorityRecordsOmitted: lowerPriorityRecordsOmitted,
    inaccessibleTrashRows: inaccessibleTrashRows,
    unindexedFilesFound: unindexedFilesFound,
    signatureMatches: signatureMatches,
    standaloneImageCandidates: standaloneImageCandidates,
    cacheCandidates: cacheCandidates,
    messagingCandidates: messagingCandidates,
    copyCandidates: copyCandidates,
    excludedExisting: excludedExisting,
    duplicateRecordsSuppressed: duplicateRecordsSuppressed,
    invalidFilesRejected: invalidFilesRejected,
    ineligibleRecordsRejected: ineligibleRecordsRejected,
    unavailableFiles: unavailableFiles,
    unavailableDirectories: unavailableDirectories,
    unsupportedFiles: unsupportedFiles,
    sourceFilteredItems: sourceFilteredItems,
    finalVerifiedDeleted: finalVerifiedDeleted,
    finalFullQualityCopies: finalFullQualityCopies,
    finalReducedCopies: finalReducedCopies,
    finalUnknownQualityCopies: finalUnknownQualityCopies,
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
