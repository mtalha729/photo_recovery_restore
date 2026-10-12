import 'package:flutter/foundation.dart';

import '../../media_access/media_access.dart';
import '../../recovery/application/camera_gallery_recovery/camera_gallery_recovery_pipeline.dart';
import '../../recovery/application/deep_recovery/deep_recovery_provider.dart';
import '../../recovery/application/deep_recovery/deep_recovery_engine.dart';
import '../../recovery/application/deep_recovery/deep_recovery_classifier.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_index.dart';
import '../../recovery/application/messaging_recovery/messaging_recovery_pipeline.dart';
import '../../recovery/application/scoped_storage_recovery/scoped_storage_recovery_pipeline.dart';
import '../../recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import '../../recovery/application/screenshots_downloads_recovery/screenshots_downloads_recovery_pipeline.dart';
import '../../recovery/application/scan_runtime/scan_cancellation.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_models.dart';
import '../../recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
import '../../recovery/data/current_media_inventory/current_media_inventory.dart';
import '../../recovery/data/current_media_inventory/current_media_inventory_models.dart';
import '../../recovery/data/current_media_inventory/platform_current_media_inventory.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import '../../recovery/data/folder_scope/authorized_folder_deep_recovery_provider.dart';
import '../../recovery/data/folder_scope/authorized_folder_media_discovery.dart';
import '../../recovery/data/trash_discovery/platform_trash_discovery.dart';
import '../../recovery/data/trash_discovery/trash_discovery.dart';
import '../../recovery/data/trash_discovery/trash_discovery_models.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/media_source.dart';
import 'deep_recovery_diagnostics.dart';
import 'recovery_scan_models.dart';
import 'recovery_scan_page_source.dart';

class ProductionRecoveryScanPageSource
    implements
        RecoveryScanPageSource,
        LimitedAccessAwarePageSource,
        CancellationAwarePageSource,
        ActiveScanCancellationAwarePageSource,
        ScanSessionLifecyclePageSource,
        PossibleCopiesAwarePageSource,
        DeepScanCapabilityAwarePageSource {
  ProductionRecoveryScanPageSource({
    MediaAccessCoordinator? accessCoordinator,
    CurrentMediaInventory? inventory,
    TrashDiscovery? trashDiscovery,
    AuthorizedFolderMediaDiscovery? folderMediaDiscovery,
    PlatformDeepStorageRecoveryProvider? deepStorageProvider,
    this.authorizedFolderScope,
    this.includeDeepStorage = false,
    this.profile = PhotoRecoveryProfile.fastDeep,
  }) : _accessCoordinator =
           accessCoordinator ?? PlatformMediaAccessCoordinator(),
       _inventory = inventory ?? PlatformCurrentMediaInventory(),
       _trashDiscovery = trashDiscovery ?? PlatformTrashDiscovery(),
       _folderMediaDiscovery =
           folderMediaDiscovery ??
           const PlatformAuthorizedFolderMediaDiscovery(),
       _deepStorageProvider =
           deepStorageProvider ?? const PlatformDeepStorageRecoveryProvider();

  final MediaAccessCoordinator _accessCoordinator;
  final CurrentMediaInventory _inventory;
  final TrashDiscovery _trashDiscovery;
  final AuthorizedFolderMediaDiscovery _folderMediaDiscovery;
  final PlatformDeepStorageRecoveryProvider _deepStorageProvider;
  final AuthorizedFolderScope? authorizedFolderScope;
  final bool includeDeepStorage;
  final PhotoRecoveryProfile profile;
  DeepRecoveryDiagnosticsBuilder _diagnostics =
      DeepRecoveryDiagnosticsBuilder();
  ExistingRecoveryPipelinePageSource? _delegate;
  VerifiedSourceRecoveryFailure? _failure;
  ScanCancellationToken? _cancellationToken;
  List<MediaCandidate> _possibleCopies = const [];
  ExistingMediaIndex? _existingMediaIndex;
  bool _deepScanComplete = false;
  bool _diagnosticsPrinted = false;
  int _pendingProviderRequests = 0;
  DeepStorageCapabilityStatus _deepCapabilityStatus =
      DeepStorageCapabilityStatus.failed;
  String? _deepCapabilityMessage;
  void Function(DeepRecoveryEngineProgress progress)? onDeepProgress;

  DeepRecoveryDiagnostics get diagnostics => _diagnostics.build();
  bool get deepProviderExhausted => !includeDeepStorage || _deepScanComplete;
  int get pendingProviderRequests => _pendingProviderRequests;
  int get remainingNativeQueue => _deepScanComplete ? 0 : 1;

  @override
  void beginScanSession() {
    _delegate = null;
    _failure = null;
    _cancellationToken = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _deepScanComplete = false;
    _diagnosticsPrinted = false;
    _pendingProviderRequests = 0;
    _deepCapabilityStatus = DeepStorageCapabilityStatus.failed;
    _deepCapabilityMessage = null;
    isLimitedAccess = false;
    _diagnostics = DeepRecoveryDiagnosticsBuilder();
  }

  @override
  void endScanSession() {
    _delegate = null;
    _failure = null;
    _cancellationToken = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _deepScanComplete = false;
    _pendingProviderRequests = 0;
    onDeepProgress = null;
  }

  @override
  bool isLimitedAccess = false;

  @override
  List<MediaCandidate> get possibleCopies => _possibleCopies;

  @override
  DeepStorageCapabilityStatus get deepCapabilityStatus => _deepCapabilityStatus;

  @override
  String? get deepCapabilityMessage => _deepCapabilityMessage;

  @override
  Future<void> openDeepScanSettings() =>
      _deepStorageProvider.openAccessSettings();

  @override
  Future<bool> refreshDeepScanCapability() async {
    final capability = await _deepStorageProvider.getCapability();
    _deepCapabilityStatus = capability.status;
    if (!capability.available) return false;
    _failure = null;
    _delegate = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _deepScanComplete = false;
    _diagnosticsPrinted = false;
    return true;
  }

  @override
  set cancellationToken(ScanCancellationToken? value) {
    _cancellationToken = value;
  }

  @override
  Future<void> cancelActiveScan() => _deepStorageProvider.cancelActiveScan();

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    _pendingProviderRequests++;
    try {
      return await _loadPage(source, request);
    } finally {
      _pendingProviderRequests--;
    }
  }

  Future<VerifiedSourceRecoveryResult> _loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    await _initialize(source);
    if (_failure case final failure?) {
      _printDiagnosticsOnce();
      return failure;
    }
    final result = await _delegate!.loadPage(source, request);
    if (result is VerifiedSourceRecoverySuccess) {
      _diagnostics.excludedExisting += result.diagnostics.excludedExistingCount;
      _diagnostics.sourceFilteredItems +=
          result.diagnostics.filteredOtherSourceCount;
      _diagnostics.finalVerifiedDeleted += result.items.length;
      if (result.items.isNotEmpty) _diagnostics.markFirstValidResult();
      final volume = result.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        _diagnostics.volumesScanned.add(volume);
      }
      if (!result.mayHaveMore && includeDeepStorage && !_deepScanComplete) {
        await _scanDeepStorage(source, _existingMediaIndex!);
        _deepScanComplete = true;
        if (_failure case final failure?) {
          _printDiagnosticsOnce();
          return failure;
        }
      }
      if (!result.mayHaveMore) _printDiagnosticsOnce();
    }
    if (result is VerifiedSourceRecoveryUnsupported &&
        includeDeepStorage &&
        !_deepScanComplete) {
      await _scanDeepStorage(source, _existingMediaIndex!);
      _deepScanComplete = true;
      if (_failure case final failure?) {
        _printDiagnosticsOnce();
        return failure;
      }
      _printDiagnosticsOnce();
      return VerifiedSourceRecoverySuccess(
        source: source.mediaSource,
        items: const [],
        diagnostics: const VerifiedSourceRecoveryDiagnostics(
          examinedCount: 0,
          excludedExistingCount: 0,
          filteredOtherSourceCount: 0,
          filteredIneligibleCount: 0,
        ),
      );
    }
    return result;
  }

  void _printDiagnosticsOnce() {
    if (!kDebugMode || _diagnosticsPrinted) return;
    _diagnosticsPrinted = true;
    debugPrint(diagnostics.toDebugSummary());
  }

  Future<void> _initialize(RecoveryScanSource source) async {
    if (_delegate != null || _failure != null) return;
    final access = await _accessCoordinator.getState();
    isLimitedAccess = access.isLimited;
    _diagnostics.androidApiLevel = access.androidApiLevel;
    _diagnostics.accessMode = access.isLimited ? 'limited' : 'full';
    if (!access.canReadImages) {
      _failure = VerifiedSourceRecoveryFailure(
        source: source.mediaSource,
        code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
        message: 'Image access is required before scanning.',
      );
      return;
    }

    final recordsByIdentity = <String, CurrentMediaRecord>{};
    final inventoryTimer = Stopwatch()..start();
    int? legacyContinuation;
    String? continuationToken;
    final seenContinuations = <String>{};
    do {
      if (_isCancelled(source)) return;
      final result = await _inventory.getCurrentMediaPage(
        CurrentMediaPageRequest(
          pageSize: 200,
          afterMediaStoreId: legacyContinuation,
          continuationToken: continuationToken,
        ),
      );
      if (result is CurrentMediaInventoryFailureResult) {
        _failure = VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
          message: result.failure.message,
        );
        return;
      }
      final page = (result as CurrentMediaInventorySuccess).page;
      final volume = page.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        _diagnostics.volumesScanned.add(volume);
      }
      for (final record in page.items) {
        if (_isCancelled(source)) return;
        final key =
            record.contentUri?.toString() ??
            '${record.storageVolumeName ?? 'unknown'}:${record.mediaStoreId}';
        if (recordsByIdentity.containsKey(key)) continue;
        recordsByIdentity[key] = record;
      }
      final nextToken = page.nextContinuationToken;
      final nextId = page.nextAfterMediaStoreId;
      if (nextToken == null && nextId == null) break;
      final key = nextToken ?? 'legacy:$nextId';
      if (!seenContinuations.add(key)) {
        _failure = VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code: VerifiedSourceRecoveryFailureCode.platformFailure,
          message: 'Current-media pagination continuation repeated.',
        );
        return;
      }
      continuationToken = nextToken;
      legacyContinuation = nextToken == null ? nextId : null;
    } while (true);
    inventoryTimer.stop();
    _diagnostics.mediaInventoryMs = inventoryTimer.elapsedMilliseconds;

    if (_isCancelled(source)) return;
    await _scanAuthorizedFolder(source);
    if (_failure != null) return;

    final records = recordsByIdentity.values.toList(growable: false);
    _diagnostics.currentRecordsScanned = records.length;
    final trash = _DiagnosticsTrashDiscovery(
      delegate: _trashDiscovery,
      diagnostics: _diagnostics,
    );
    final shared = VerifiedSourceRecoveryPipeline(trashDiscovery: trash);
    final indexTimer = Stopwatch()..start();
    final existingMediaIndex = ExistingMediaIndex.build(records: records);
    indexTimer.stop();
    _diagnostics.existingIndexBuildMs = indexTimer.elapsedMilliseconds;
    _existingMediaIndex = existingMediaIndex;
    _delegate = ExistingRecoveryPipelinePageSource(
      cameraGallery: CameraGalleryRecoveryPipeline(trashDiscovery: trash),
      messaging: MessagingRecoveryPipeline(trashDiscovery: trash),
      screenshotsDownloads: ScreenshotsDownloadsRecoveryPipeline(
        trashDiscovery: trash,
      ),
      scopedStorage: ScopedStorageRecoveryPipeline(sourcePipeline: shared),
      allPhotos: shared,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: access.androidApiLevel,
      authorizedFolderScope: authorizedFolderScope,
    );
  }

  Future<void> _scanDeepStorage(
    RecoveryScanSource source,
    ExistingMediaIndex existingMediaIndex,
  ) async {
    final capability = await _deepStorageProvider.getCapability();
    _deepCapabilityStatus = capability.status;
    _deepCapabilityMessage = _capabilityMessage(capability.status);
    _diagnostics.deepCapabilityState = capability.status.name;
    _diagnostics.allFilesAccessGranted =
        capability.requiresAllFilesAccess && capability.available;
    if (capability.status == DeepStorageCapabilityStatus.accessRequired) {
      // The verified MediaStore pass has already completed. Optional deeper
      // filesystem access must not discard or block those real results.
      return;
    }
    if (!capability.available || _isCancelled(source)) return;
    final result = await const DeepRecoveryEngine().scan(
      providers: [_deepStorageProvider],
      existingMediaIndex: existingMediaIndex,
      source: source.mediaSource,
      currentMediaLocationKeys: existingMediaIndex.storageLocationKeys,
      profile: profile,
      cancellationToken: _cancellationToken,
      pageSize: 200,
      onProgress: (progress) {
        if (kDebugMode) {
          debugPrint(
            'Deep page=${progress.pageCount} cursor=${progress.cursorIdentifier ?? 'none'} '
            'files=${progress.pageFilesExamined} directories=${progress.pageDirectoriesConsumed} '
            'records=${progress.pageRecordsReturned} remaining=${progress.remainingDirectoryQueue} '
            'visited=${progress.visitedDirectoryCount} duplicateDirs=${progress.duplicateDirectorySkips} '
            'repeatedCursors=${progress.repeatedCursorDetections} exhausted=${progress.providerExhausted} '
            'reason=${progress.completionReason ?? 'continuing'}',
          );
        }
        onDeepProgress?.call(progress);
      },
    );
    if (!result.completed) {
      if (!_isCancelled(source)) {
        _failure = VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code:
              result.failureAvailability ==
                  DeepProviderAvailability.accessRequired
              ? VerifiedSourceRecoveryFailureCode.accessUnavailable
              : VerifiedSourceRecoveryFailureCode.platformFailure,
          message:
              result.failureMessage ??
              'Photo recovery could not finish safely.',
        );
      }
      return;
    }
    _diagnostics.filesExamined += result.filesExamined;
    _diagnostics.foldersVisited += result.directoriesExamined;
    _diagnostics.entriesExamined += result.entriesExamined;
    _diagnostics.currentFilesSkipped += result.currentFilesSkipped;
    _diagnostics.signatureCacheHits += result.signatureCacheHits;
    _diagnostics.signatureCacheMisses += result.signatureCacheMisses;
    _diagnostics.nativeTraversalMs = result.nativeTraversalMillis;
    _diagnostics.carvedTemporaryBytes = result.carvedTemporaryBytes;
    _diagnostics.carvedTempBytesReclaimed = result.carvedTempBytesReclaimed;
    _diagnostics.invalidFilesRejected += result.invalidFilesRejected;
    _diagnostics.unavailableFiles += result.unavailableFiles;
    _diagnostics.unsupportedFiles += result.unsupportedFiles;
    _diagnostics.duplicateRecordsSuppressed +=
        result.duplicateRecordsSuppressed;
    _diagnostics.duplicateDirectorySkips += result.duplicateDirectorySkips;
    _diagnostics.repeatedCursorDetections += result.repeatedCursorDetections;
    _diagnostics.completionReason = result.completionReason ?? 'exhausted';
    _diagnostics.volumesScanned.addAll(result.volumesScanned);
    _diagnostics.excludedExisting +=
        result.byDisposition[DeepRecoveryDisposition.existingMedia]?.length ??
        0;
    _possibleCopies = List<MediaCandidate>.unmodifiable([
      ...?result.byDisposition[DeepRecoveryDisposition.possibleFullQualityCopy],
      ...?result.byDisposition[DeepRecoveryDisposition
          .possibleLowerQualityCopy],
      ...?result.byDisposition[DeepRecoveryDisposition.thumbnailCopy],
    ]);
    _diagnostics.copyCandidates += _possibleCopies.length;
    if (_possibleCopies.isNotEmpty) _diagnostics.markFirstValidResult();
    _diagnostics.signatureMatches += _possibleCopies.length;
    _diagnostics.unindexedFilesFound += _possibleCopies.length;
    for (final candidate in _possibleCopies) {
      final evidence = candidate.discoveryEvidence;
      if (candidate.source == MediaSource.unknown) {
        _diagnostics.unknownSourceRetained++;
      }
      if (evidence.isTrashLike) _diagnostics.trashLikeCandidates++;
      if (evidence.isCacheLike) _diagnostics.cacheCandidates++;
      if (evidence.isThumbnailLike) _diagnostics.thumbnailCandidates++;
      if (candidate.source == MediaSource.messagingSharedMedia) {
        _diagnostics.messagingCandidates++;
      }
      if (candidate.isRemovableStorage == true) {
        _diagnostics.removableCandidates++;
      }
      if (evidence.isExtensionMismatch) {
        _diagnostics.extensionMismatchCandidates++;
      }
      if (evidence.isEmbeddedPayload) {
        _diagnostics.embeddedPayloads++;
      } else {
        _diagnostics.standaloneImageCandidates++;
      }
    }
    _diagnostics.finalFullQualityCopies +=
        result
            .byDisposition[DeepRecoveryDisposition.possibleFullQualityCopy]
            ?.length ??
        0;
    _diagnostics.finalReducedCopies +=
        result
            .byDisposition[DeepRecoveryDisposition.possibleLowerQualityCopy]
            ?.length ??
        0;
    _diagnostics.finalThumbnailCopies +=
        result.byDisposition[DeepRecoveryDisposition.thumbnailCopy]?.length ??
        0;
  }

  static String? _capabilityMessage(DeepStorageCapabilityStatus status) =>
      switch (status) {
        DeepStorageCapabilityStatus.accessRequired =>
          'Photo Recovery Access is required for the full photo scan.',
        DeepStorageCapabilityStatus.unavailable =>
          'Broader photo recovery access is unavailable on this device.',
        DeepStorageCapabilityStatus.unsupported =>
          'Broader photo recovery access is unsupported on this platform.',
        DeepStorageCapabilityStatus.failed =>
          'Photo Recovery Access could not be checked.',
        DeepStorageCapabilityStatus.available => null,
      };

  Future<void> _scanAuthorizedFolder(RecoveryScanSource source) async {
    final scope = authorizedFolderScope;
    if (source != RecoveryScanSource.customFolder ||
        scope == null ||
        scope.grantState != FolderGrantState.active) {
      return;
    }
    final provider = AuthorizedFolderDeepRecoveryProvider(
      treeUri: scope.treeUri,
      discovery: _folderMediaDiscovery,
    );
    String? continuationToken;
    final seenContinuations = <String>{};
    final seenDocuments = <String>{};
    do {
      if (_isCancelled(source)) return;
      final result = await provider.getPage(
        DeepRecoveryProviderRequest(
          pageSize: 200,
          source: source.mediaSource,
          continuationToken: continuationToken,
        ),
      );
      if (result is DeepRecoveryProviderUnavailable) {
        _failure = VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code: result.availability == DeepProviderAvailability.accessRequired
              ? VerifiedSourceRecoveryFailureCode.accessUnavailable
              : VerifiedSourceRecoveryFailureCode.platformFailure,
          message: result.message,
        );
        return;
      }
      final page = result as DeepRecoveryProviderPage;
      _diagnostics.foldersVisited++;
      _diagnostics.filesExamined += page.filesExamined;
      _diagnostics.invalidFilesRejected += page.invalidFilesRejected;
      _diagnostics.signatureMatches += page.items.length;
      _diagnostics.unavailableFiles += page.unavailableFiles;
      _diagnostics.unsupportedFiles += page.unsupportedFiles;
      for (final item in page.items) {
        final uri = item.candidate.documentUri;
        if (uri != null) seenDocuments.add(uri.toString());
      }
      final next = page.nextContinuationToken;
      if (next == null) break;
      if (!seenContinuations.add(next)) {
        _failure = VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code: VerifiedSourceRecoveryFailureCode.platformFailure,
          message: 'Authorized-folder pagination continuation repeated.',
        );
        return;
      }
      continuationToken = next;
    } while (true);
    _diagnostics.safDocumentsScanned = seenDocuments.length;
    _diagnostics.unindexedFilesFound = seenDocuments.length;
  }

  bool _isCancelled(RecoveryScanSource source) {
    if (_cancellationToken?.isCancelled != true) return false;
    _failure ??= VerifiedSourceRecoveryFailure(
      source: source.mediaSource,
      code: VerifiedSourceRecoveryFailureCode.platformFailure,
      message: 'Scan cancelled safely.',
    );
    return true;
  }
}

class _DiagnosticsTrashDiscovery implements TrashDiscovery {
  const _DiagnosticsTrashDiscovery({
    required this.delegate,
    required this.diagnostics,
  });

  final TrashDiscovery delegate;
  final DeepRecoveryDiagnosticsBuilder diagnostics;

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    final result = await delegate.getVerifiedTrashPage(request);
    diagnostics.verifiedTrashMs += stopwatch.elapsedMilliseconds;
    if (result is TrashDiscoverySuccess) {
      diagnostics.trashCandidates += result.page.items.length;
      final volume = result.page.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        diagnostics.volumesScanned.add(volume);
      }
    }
    return result;
  }
}
