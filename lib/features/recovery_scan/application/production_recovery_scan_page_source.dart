import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media_access/media_access.dart';
import '../../recovery/application/camera_gallery_recovery/camera_gallery_recovery_pipeline.dart';
import '../../recovery/application/current_photo_discovery/current_photo_candidate_mapper.dart';
import '../../recovery/application/deep_recovery/deep_recovery_provider.dart';
import '../../recovery/application/deep_recovery/deep_recovery_engine.dart';
import '../../recovery/application/deep_recovery/deep_recovery_classifier.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_index.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../../recovery/application/existing_media_exclusion/existing_media_exclusion_models.dart';
import '../../recovery/application/recovery_evidence_classifier/recovery_evidence_classifier.dart';
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
import '../../recovery/data/folder_scope/authorized_folder_media_discovery.dart';
import '../../recovery/data/folder_scope/folder_scope_selector.dart';
import '../../recovery/data/folder_scope/platform_folder_scope_selector.dart';
import '../../recovery/data/trash_discovery/platform_trash_discovery.dart';
import '../../recovery/data/trash_discovery/trash_discovery.dart';
import '../../recovery/data/trash_discovery/trash_discovery_models.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/recovery_classification.dart';
import '../../recovery/domain/media_source.dart';
import '../../recovery/domain/deletion_evidence.dart';
import '../../recovery/domain/recovery_quality.dart';
import '../../recovery/domain/recovery_discovery_evidence.dart';
import '../../recovery/domain/restore_capability.dart';
import 'authorized_folder_scan_models.dart';
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
        DeepScanCapabilityAwarePageSource,
        AuthorizedFolderScanAwarePageSource {
  static const _inventoryPageSize = 500;
  static const _maximumRetainedSelectedFolderCandidates = 10000;
  static const _deepScanContinuationToken = '__photo_recovery_deep_scan_v1__';
  static const _pendingFailureContinuationToken =
      '__photo_recovery_pending_failure_v1__';

  ProductionRecoveryScanPageSource({
    MediaAccessCoordinator? accessCoordinator,
    CurrentMediaInventory? inventory,
    TrashDiscovery? trashDiscovery,
    PlatformDeepStorageRecoveryProvider? deepStorageProvider,
    FolderScopeSelector? folderScopeSelector,
    AuthorizedFolderMediaDiscovery? authorizedFolderDiscovery,
    this.includeDeepStorage = false,
    this.profile = PhotoRecoveryProfile.fastDeep,
    this.maximumCurrentInventoryPages = 1000,
    this.maximumCurrentInventoryRecords = 100000,
  }) : assert(maximumCurrentInventoryPages > 0),
       assert(maximumCurrentInventoryRecords > 0),
       _accessCoordinator =
           accessCoordinator ?? PlatformMediaAccessCoordinator(),
       _inventory = inventory ?? PlatformCurrentMediaInventory(),
       _trashDiscovery = trashDiscovery ?? PlatformTrashDiscovery(),
       _deepStorageProvider =
           deepStorageProvider ?? const PlatformDeepStorageRecoveryProvider(),
       _folderScopeSelector =
           folderScopeSelector ?? const PlatformFolderScopeSelector(),
       _authorizedFolderDiscovery =
           authorizedFolderDiscovery ??
           const PlatformAuthorizedFolderMediaDiscovery();

  final MediaAccessCoordinator _accessCoordinator;
  final CurrentMediaInventory _inventory;
  final TrashDiscovery _trashDiscovery;
  _PrefetchedTrashDiscovery? _prefetchedTrash;
  _PrefetchedDeepStoragePage? _prefetchedDeep;
  final PlatformDeepStorageRecoveryProvider _deepStorageProvider;
  final FolderScopeSelector _folderScopeSelector;
  final AuthorizedFolderMediaDiscovery _authorizedFolderDiscovery;
  final bool includeDeepStorage;
  final PhotoRecoveryProfile profile;
  final int maximumCurrentInventoryPages;
  final int maximumCurrentInventoryRecords;
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
  int _remainingNativeQueue = 0;
  String? _activeFolderContinuationToken;
  bool _folderProviderSessionActive = false;
  bool _canRequestDeepStorageAccess = false;
  String _deepRunState = 'notRequested';
  String _lastContinuationState = 'unknown';
  VerifiedSourceRecoveryFailure? _pendingStandardFailure;
  DeepStorageCapabilityStatus _deepCapabilityStatus =
      DeepStorageCapabilityStatus.failed;
  String? _deepCapabilityMessage;
  void Function(DeepRecoveryEngineProgress progress)? onDeepProgress;

  DeepRecoveryDiagnostics get diagnostics => _diagnostics.build();
  bool get deepProviderExhausted => _deepRunState == 'completed';
  String get deepProviderRunState => _deepRunState;
  String get lastContinuationState => _lastContinuationState;
  int get pendingProviderRequests => _pendingProviderRequests;
  int get pendingClassificationTasks => 0;
  int get remainingNativeQueue => _remainingNativeQueue;

  @override
  void beginScanSession() {
    _delegate = null;
    _failure = null;
    _cancellationToken = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _prefetchedTrash = null;
    _prefetchedDeep = null;
    _deepScanComplete = false;
    _diagnosticsPrinted = false;
    _pendingProviderRequests = 0;
    _remainingNativeQueue = 0;
    _activeFolderContinuationToken = null;
    _folderProviderSessionActive = false;
    _canRequestDeepStorageAccess = false;
    _deepRunState = includeDeepStorage ? 'pending' : 'notRequested';
    _lastContinuationState = 'unknown';
    _pendingStandardFailure = null;
    _deepCapabilityStatus = DeepStorageCapabilityStatus.failed;
    _deepCapabilityMessage = null;
    isLimitedAccess = false;
    _diagnostics = DeepRecoveryDiagnosticsBuilder();
  }

  @override
  void endScanSession() {
    if (_folderProviderSessionActive) {
      unawaited(
        _cancelAuthorizedFolderScan(
          continuationToken: _activeFolderContinuationToken,
        ),
      );
    }
    _folderProviderSessionActive = false;
    _delegate = null;
    _failure = null;
    _cancellationToken = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _prefetchedTrash = null;
    _prefetchedDeep = null;
    _deepScanComplete = false;
    _pendingProviderRequests = 0;
    _remainingNativeQueue = 0;
    _activeFolderContinuationToken = null;
    _pendingStandardFailure = null;
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
  bool get canRequestDeepStorageAccess => _canRequestDeepStorageAccess;

  @override
  Future<void> openDeepScanSettings() => _canRequestDeepStorageAccess
      ? _deepStorageProvider.openAccessSettings()
      : Future<void>.value();

  @override
  Future<bool> refreshDeepScanCapability() async {
    final capability = await _deepStorageProvider.getCapability();
    _deepCapabilityStatus = capability.status;
    _canRequestDeepStorageAccess = capability.requestSupported;
    _deepCapabilityMessage = _capabilityMessage(capability);
    if (!capability.available) return false;
    _failure = null;
    _delegate = null;
    _possibleCopies = const [];
    _existingMediaIndex = null;
    _prefetchedTrash = null;
    _prefetchedDeep = null;
    _deepScanComplete = false;
    _deepRunState = 'pending';
    _lastContinuationState = 'unknown';
    _remainingNativeQueue = 0;
    _diagnosticsPrinted = false;
    return true;
  }

  @override
  set cancellationToken(ScanCancellationToken? value) {
    _cancellationToken = value;
  }

  @override
  Future<void> cancelActiveScan() async {
    await Future.wait<void>([
      _deepStorageProvider.cancelActiveScan(),
      _cancelAuthorizedFolderScan(
        continuationToken: _activeFolderContinuationToken,
      ),
    ]);
  }

  Future<void> _cancelAuthorizedFolderScan({String? continuationToken}) async {
    await _authorizedFolderDiscovery.cancelScan(
      continuationToken: continuationToken,
    );
  }

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
    if (request.continuationToken == _pendingFailureContinuationToken) {
      final failure = _pendingStandardFailure;
      _pendingStandardFailure = null;
      _printDiagnosticsOnce();
      return failure ?? _emptyPage(source.mediaSource);
    }

    if (request.continuationToken == _deepScanContinuationToken) {
      if (includeDeepStorage && !_deepScanComplete) {
        final index = _existingMediaIndex;
        if (index != null) {
          await _scanDeepStorage(source, index);
        } else {
          _deepRunState = 'skippedNoCurrentMediaIndex';
          _deepCapabilityMessage = 'The optional deep scan was skipped because current media could not be indexed safely.';
        }
        _deepScanComplete = true;
      }
      _printDiagnosticsOnce();
      final failure = _pendingStandardFailure;
      _pendingStandardFailure = null;
      return failure ?? _emptyPage(source.mediaSource);
    }

    await _initialize(source);
    if (_failure case final failure?) {
      _printDiagnosticsOnce();
      return failure;
    }
    VerifiedSourceRecoveryResult result;
    try {
      result = await _delegate!.loadPage(source, request);
    } catch (error) {
      _diagnostics.verifiedTrashProviderState = 'failed:exception';
      result = VerifiedSourceRecoveryFailure(
        source: source.mediaSource,
        code: VerifiedSourceRecoveryFailureCode.platformFailure,
        message:
            'The standard photo provider failed (${error.runtimeType}); permitted deep scanning will still be attempted.',
      );
    }
    if (result is VerifiedSourceRecoverySuccess) {
      _diagnostics.excludedExisting += result.diagnostics.excludedExistingCount;
      _diagnostics.sourceFilteredItems +=
          result.diagnostics.filteredOtherSourceCount;
      _diagnostics.ineligibleRecordsRejected +=
          result.diagnostics.filteredIneligibleCount;
      _diagnostics.finalVerifiedDeleted += result.items.length;
      if (result.items.isNotEmpty) _diagnostics.markFirstValidResult();
      final volume = result.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        _diagnostics.volumesScanned.add(volume);
      }
      if (!result.mayHaveMore && includeDeepStorage && !_deepScanComplete) {
        // Return the finished MediaStore page first. The scanner will publish
        // those verified rows before a second page runs the optional deep
        // provider, so deep traversal cannot hide standard results behind a
        // long native pass.
        return VerifiedSourceRecoverySuccess(
          source: result.source,
          items: result.items,
          diagnostics: result.diagnostics,
          nextContinuationToken: _deepScanContinuationToken,
          scannedVolumeName: result.scannedVolumeName,
        );
      }
      if (!result.mayHaveMore && _pendingStandardFailure != null) {
        // Keep this final provider page before surfacing incomplete inventory
        // coverage; the controller must retain any verified items it contains.
        return VerifiedSourceRecoverySuccess(
          source: result.source,
          items: result.items,
          diagnostics: result.diagnostics,
          nextContinuationToken: _pendingFailureContinuationToken,
          scannedVolumeName: result.scannedVolumeName,
        );
      }
      if (!result.mayHaveMore) _printDiagnosticsOnce();
      return result;
    }

    if (result is VerifiedSourceRecoveryUnsupported) {
      if (includeDeepStorage && !_deepScanComplete) {
        return VerifiedSourceRecoverySuccess(
          source: source.mediaSource,
          items: const [],
          diagnostics: const VerifiedSourceRecoveryDiagnostics(
            examinedCount: 0,
            excludedExistingCount: 0,
            filteredOtherSourceCount: 0,
            filteredIneligibleCount: 0,
          ),
          nextContinuationToken: _deepScanContinuationToken,
        );
      }
      if (_pendingStandardFailure case final failure?) {
        _pendingStandardFailure = null;
        _printDiagnosticsOnce();
        return failure;
      }
    }

    if (result is VerifiedSourceRecoveryFailure) {
      if (includeDeepStorage &&
          !_deepScanComplete &&
          _existingMediaIndex != null) {
        // A trash-provider error is recorded, but it does not suppress an
        // independently permitted deep provider. The failure is returned after
        // that attempt; the controller retains every item already published.
        _rememberPendingStandardFailure(result);
        return VerifiedSourceRecoverySuccess(
          source: source.mediaSource,
          items: const [],
          diagnostics: const VerifiedSourceRecoveryDiagnostics(
            examinedCount: 0,
            excludedExistingCount: 0,
            filteredOtherSourceCount: 0,
            filteredIneligibleCount: 0,
          ),
          nextContinuationToken: _deepScanContinuationToken,
        );
      }
      if (_pendingStandardFailure != null) {
        _rememberPendingStandardFailure(result);
        final failure = _pendingStandardFailure!;
        _pendingStandardFailure = null;
        _printDiagnosticsOnce();
        return failure;
      }
    }
    _printDiagnosticsOnce();
    return result;
  }

  void _rememberPendingStandardFailure(VerifiedSourceRecoveryFailure failure) {
    final pending = _pendingStandardFailure;
    if (pending == null) {
      _pendingStandardFailure = failure;
      return;
    }
    if (pending.code == VerifiedSourceRecoveryFailureCode.resourceLimit &&
        failure.message != null &&
        failure.message!.isNotEmpty &&
        failure.message != pending.message) {
      _pendingStandardFailure = VerifiedSourceRecoveryFailure(
        source: pending.source,
        code: pending.code,
        message:
            '${pending.message} Additional provider issue: ${failure.message}',
      );
    }
  }

  VerifiedSourceRecoverySuccess _emptyPage(MediaSource source) =>
      VerifiedSourceRecoverySuccess(
        source: source,
        items: const [],
        diagnostics: const VerifiedSourceRecoveryDiagnostics(
          examinedCount: 0,
          excludedExistingCount: 0,
          filteredOtherSourceCount: 0,
          filteredIneligibleCount: 0,
        ),
      );

  void _printDiagnosticsOnce() {
    if (!kDebugMode || _diagnosticsPrinted) return;
    _diagnosticsPrinted = true;
    debugPrint('Recovery build=debug; ${diagnostics.toDebugSummary()}');
  }

  @override
  bool get canScanAuthorizedFolder => true;

  @override
  Future<AuthorizedFolderScanOutcome> scanAuthorizedFolder({
    required RecoveryScanSource source,
    required void Function(AuthorizedFolderScanProgress progress) onProgress,
  }) async {
    if (source != RecoveryScanSource.allPhotos) {
      return const AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.unsupported,
        message: 'Choose a folder from the primary Recover Photos scan.',
      );
    }

    FolderScopeSelectionResult selection;
    try {
      selection = await _folderScopeSelector.selectFolder();
    } catch (_) {
      _diagnostics.selectedFolderProviderState = 'selectionFailed';
      return const AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.unsupported,
        message: 'Android folder selection is unavailable on this device.',
      );
    }
    if (selection.status == FolderScopeSelectionStatus.cancelled) {
      _diagnostics.selectedFolderProviderState = 'cancelledByUser';
      return const AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.selectionCancelled,
      );
    }
    if (selection.status != FolderScopeSelectionStatus.selected ||
        selection.scope == null) {
      final status = switch (selection.status) {
        FolderScopeSelectionStatus.accessUnavailable =>
          AuthorizedFolderScanStatus.accessRequired,
        FolderScopeSelectionStatus.permissionGrantLost =>
          AuthorizedFolderScanStatus.permissionGrantLost,
        FolderScopeSelectionStatus.restrictedLocation =>
          AuthorizedFolderScanStatus.unsupported,
        _ => AuthorizedFolderScanStatus.partialFailure,
      };
      _diagnostics.selectedFolderProviderState =
          'selection:${selection.status.name}';
      return AuthorizedFolderScanOutcome(
        status: status,
        message:
            selection.message ?? 'The selected folder could not be opened.',
      );
    }

    final scope = selection.scope!;
    if (scope.grantState != FolderGrantState.active ||
        scope.treeUri.scheme != 'content') {
      _diagnostics.selectedFolderProviderState = 'invalidGrant';
      return const AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.accessRequired,
        message: 'The selected folder did not provide a valid read-only grant.',
      );
    }

    // The SAF tree grant is independent of broad library access. Build the
    // strongest current-media index available, but do not suppress this
    // explicitly user-authorized provider if library access is denied.
    if (_delegate == null) _failure = null;
    try {
      await _initialize(
        RecoveryScanSource.allPhotos,
        allowMissingMediaAccess: true,
      );
    } catch (_) {
      _diagnostics.currentMediaInventoryState = 'failed';
      _failure = VerifiedSourceRecoveryFailure(
        source: source.mediaSource,
        code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
        message: 'Current photos could not be indexed for comparison.',
      );
    }
    if (_cancellationToken?.isCancelled == true) {
      _diagnostics.selectedFolderProviderState = 'cancelled';
      return const AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.cancelled,
        message:
            'Selected-folder scan cancelled before folder traversal began.',
      );
    }
    final currentIndexComplete =
        _existingMediaIndex != null &&
        _failure == null &&
        !isLimitedAccess &&
        _diagnostics.currentMediaInventoryState == 'completed';
    if (_existingMediaIndex == null) {
      _diagnostics.currentMediaInventoryState = 'unavailableForFolderScan';
      _existingMediaIndex = ExistingMediaIndex.build(records: const []);
      _failure = null;
      _delegate = null;
    } else if (_failure != null) {
      // Keep a partial index for conservative exclusion, but report selected-
      // folder coverage as partial rather than treating the index as complete.
      _failure = null;
      _delegate = null;
    }
    final existingIndex = _existingMediaIndex!;

    _diagnostics.selectedFolderProviderState = 'running';
    final seenTokens = <String>{};
    final seenUris = <String>{};
    String? token;
    _activeFolderContinuationToken = null;
    var filesExamined = 0;
    var entriesExamined = 0;
    var pageCount = 0;
    var candidatesFound = 0;
    do {
      if (_cancellationToken?.isCancelled == true) {
        _diagnostics.selectedFolderProviderState = 'cancelled';
        await _cancelAuthorizedFolderScan(
          continuationToken: _activeFolderContinuationToken ?? token,
        );
        _activeFolderContinuationToken = null;
        _folderProviderSessionActive = false;
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.cancelled,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message:
              'Selected-folder scan cancelled; results found so far are kept.',
        );
      }
      _activeFolderContinuationToken = token;
      _folderProviderSessionActive = true;
      final result = await _authorizedFolderDiscovery.getPage(
        treeUri: scope.treeUri,
        pageSize: 100,
        continuationToken: token,
      );
      if (result is AuthorizedFolderMediaFailure) {
        await _cancelAuthorizedFolderScan(continuationToken: token);
        _folderProviderSessionActive = false;
        _activeFolderContinuationToken = null;
        final grantLost =
            result.code == AuthorizedFolderMediaFailureCode.permissionGrantLost;
        final cancelled =
            _cancellationToken?.isCancelled == true ||
            result.code == AuthorizedFolderMediaFailureCode.cancelled;
        _diagnostics.selectedFolderProviderState = cancelled
            ? 'cancelled'
            : grantLost
            ? 'permissionGrantLost'
            : 'partialFailure';
        return AuthorizedFolderScanOutcome(
          status: cancelled
              ? AuthorizedFolderScanStatus.cancelled
              : grantLost
              ? AuthorizedFolderScanStatus.permissionGrantLost
              : candidatesFound > 0
              ? AuthorizedFolderScanStatus.partialFailure
              : AuthorizedFolderScanStatus.unsupported,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message:
              result.message ??
              'The selected folder could not be scanned safely.',
        );
      }
      final page = (result as AuthorizedFolderMediaSuccess).page;
      _activeFolderContinuationToken = page.nextContinuationToken;
      _folderProviderSessionActive = page.nextContinuationToken != null;
      pageCount++;
      filesExamined += page.filesExamined;
      entriesExamined += page.entriesExamined;
      _diagnostics.selectedFolderPages++;
      _diagnostics.filesExamined += page.filesExamined;
      _diagnostics.entriesExamined += page.entriesExamined;
      _diagnostics.invalidFilesRejected += page.invalidFilesRejected;
      _diagnostics.unavailableFiles += page.unavailableFiles;
      _diagnostics.unavailableDirectories += page.unavailableDirectories;
      _diagnostics.unsupportedFiles += page.unsupportedFiles;

      final pageCandidates = <MediaCandidate>[];
      var resultLimitReached = false;
      for (final record in page.items) {
        if (_cancellationToken?.isCancelled == true) break;
        final uriKey = record.documentUri.toString();
        if (seenUris.contains(uriKey)) continue;
        final candidate = MediaCandidate(
          id: 'saf:$uriKey',
          source: scope.volume?.isRemovable == true
              ? MediaSource.sdCard
              : MediaSource.unknown,
          documentUri: record.documentUri,
          displayName: record.displayName,
          mimeType: record.mimeType,
          relativeLocation: record.relativeLocation,
          storageVolumeName: scope.volume?.mediaStoreVolumeName,
          isRemovableStorage: scope.volume?.isRemovable,
          byteSize: record.byteSize,
          modifiedAt: record.modifiedAt,
          classification: RecoveryClassification.possibleCopy,
          deletionEvidence: DeletionEvidence(),
          restoreCapability: RestoreCapability.unknownQualityCopy,
          recoveryQuality: RecoveryQuality.unknownQualityCopy,
          discoveryEvidence: RecoveryDiscoveryEvidence(
            detectedFormat: record.detectedFormat,
            isUnindexed: true,
          ),
        );
        final identity = const ExistingMediaExclusionEngine().evaluate(
          candidate,
          existingIndex,
        );
        if (identity.type != ExistingMediaDecisionType.noExistingMatch) {
          continue;
        }
        if (candidate.source != MediaSource.unknown &&
            candidate.source != source.mediaSource) {
          continue;
        }
        if (candidatesFound >= _maximumRetainedSelectedFolderCandidates) {
          resultLimitReached = true;
          break;
        }
        seenUris.add(uriKey);
        pageCandidates.add(candidate);
        candidatesFound++;
      }
      onProgress(
        AuthorizedFolderScanProgress(
          pageCandidates: List.unmodifiable(pageCandidates),
          filesExamined: filesExamined,
          pageCount: pageCount,
          entriesExamined: entriesExamined,
        ),
      );

      if (resultLimitReached) {
        _diagnostics.selectedFolderProviderState = 'resultMemoryLimit';
        await _cancelAuthorizedFolderScan(
          continuationToken: page.nextContinuationToken ?? token,
        );
        _activeFolderContinuationToken = null;
        _folderProviderSessionActive = false;
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.partialFailure,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message: 'The selected folder reached the safe retained-result limit; coverage is partial and results found so far are kept.',
        );
      }

      final reason = page.completionReason;
      if (_cancellationToken?.isCancelled == true || reason == 'cancelled') {
        _diagnostics.selectedFolderProviderState = 'cancelled';
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.cancelled,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message:
              'Selected-folder scan cancelled; results found so far are kept.',
        );
      }
      if (reason == 'permissionGrantLost') {
        _diagnostics.selectedFolderProviderState = 'permissionGrantLost';
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.permissionGrantLost,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message: 'Folder access ended during the scan; results found so far are kept.',
        );
      }
      if (reason == 'resourceLimit' ||
          reason == 'exhaustedWithUnreadableEntries') {
        _diagnostics.selectedFolderProviderState = 'partialFailure';
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.partialFailure,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message: reason == 'resourceLimit'
              ? 'The selected folder exceeded a safe traversal limit; partial results are kept.'
              : 'Some selected-folder files or subfolders could not be read; coverage is partial.',
        );
      }

      final next = page.nextContinuationToken;
      if (page.providerExhausted) {
        if (next != null || reason != 'exhausted') {
          _diagnostics.selectedFolderProviderState = 'inconsistentCompletion';
          return AuthorizedFolderScanOutcome(
            status: AuthorizedFolderScanStatus.partialFailure,
            filesExamined: filesExamined,
            pageCount: pageCount,
            candidatesFound: candidatesFound,
            message: 'The selected folder stopped without a trustworthy completion signal; partial results are kept.',
          );
        }
        token = null;
      } else if (next == null) {
        _diagnostics.selectedFolderProviderState = 'missingContinuation';
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.partialFailure,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message: 'The selected folder scan stopped before reporting full coverage; partial results are kept.',
        );
      } else if (!seenTokens.add(next)) {
        _diagnostics.selectedFolderProviderState = 'repeatedContinuation';
        return AuthorizedFolderScanOutcome(
          status: AuthorizedFolderScanStatus.partialFailure,
          filesExamined: filesExamined,
          pageCount: pageCount,
          candidatesFound: candidatesFound,
          message: 'The selected folder scan repeated a continuation; partial copies are kept.',
        );
      } else {
        token = next;
      }
    } while (token != null);

    _diagnostics.selectedFolderCopies += candidatesFound;
    if (candidatesFound > 0) _diagnostics.markFirstValidResult();
    if (!currentIndexComplete) {
      _diagnostics.selectedFolderProviderState =
          'completedWithoutFullCurrentMediaIndex';
      return AuthorizedFolderScanOutcome(
        status: AuthorizedFolderScanStatus.partialFailure,
        filesExamined: filesExamined,
        pageCount: pageCount,
        candidatesFound: candidatesFound,
        message: 'The selected folder scan finished, but the full current-photo library could not be cross-checked (library permission was denied, limited, or unavailable). Accessible items remain possible copies; none are labeled deleted.',
      );
    }
    _diagnostics.selectedFolderProviderState = 'completed';
    return AuthorizedFolderScanOutcome(
      status: AuthorizedFolderScanStatus.completed,
      filesExamined: filesExamined,
      pageCount: pageCount,
      candidatesFound: candidatesFound,
      message: 'Only the folder you selected was searched. These are surviving possible copies, not verified-deleted photos.',
    );
  }

  Future<void> _initialize(
    RecoveryScanSource source, {
    bool allowMissingMediaAccess = false,
  }) async {
    if (_delegate != null || (_failure != null && !allowMissingMediaAccess)) {
      return;
    }
    if (allowMissingMediaAccess) _failure = null;

    MediaAccessState access;
    try {
      access = await _accessCoordinator.getState();
    } catch (_) {
      _diagnostics.currentMediaInventoryState = 'failed';
      if (!allowMissingMediaAccess) {
        _rememberPendingStandardFailure(
          VerifiedSourceRecoveryFailure(
            source: source.mediaSource,
            code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
            message: 'Photo-library access status could not be checked.',
          ),
        );
      }
      // Continue permitted providers with a conservative, empty comparison
      // index. Their results remain explicitly partial because inventory
      // coverage is unknown.
      _buildRecoveryPipeline(records: const [], androidApiLevel: 0);
      return;
    }
    isLimitedAccess = access.isLimited;
    _diagnostics.androidApiLevel = access.androidApiLevel;
    _diagnostics.accessMode = access.status.name;
    if (!access.canReadImages) {
      _diagnostics.currentMediaInventoryState =
          'notGranted:${access.status.name}';
      if (!allowMissingMediaAccess) {
        _rememberPendingStandardFailure(
          VerifiedSourceRecoveryFailure(
            source: source.mediaSource,
            code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
            message: 'Photo-library access is required for a complete current-media comparison.',
          ),
        );
      }
      // Do not let missing broad photo access prevent an independent provider
      // from running. The empty index can exclude nothing, so mark the scan
      // partial and keep the provider's evidence separate from copy matches.
      _buildRecoveryPipeline(
        records: const [],
        androidApiLevel: access.androidApiLevel,
      );
      return;
    }

    // The first verified-trash page is independent of the current-photo
    // comparison index. Query it while the inventory is being built, then
    // classify and publish it through the existing pipeline once ready.
    if (_trashDiscovery is PlatformTrashDiscovery) {
      _prefetchedTrash ??= _PrefetchedTrashDiscovery(_trashDiscovery);
    }
    if (includeDeepStorage && _prefetchedDeep == null) {
      _prefetchedDeep = _PrefetchedDeepStoragePage(
        _deepStorageProvider,
        source: source.mediaSource,
        profile: profile,
      );
    }

    final recordsByIdentity = <String, CurrentMediaRecord>{};
    _diagnostics.currentMediaInventoryState = 'running';
    final inventoryTimer = Stopwatch()..start();
    int? legacyContinuation;
    String? continuationToken;
    final seenContinuations = <String>{};
    var inventoryLimitReached = false;
    do {
      if (_isCancelled(source)) {
        _diagnostics.currentMediaInventoryState = 'cancelled';
        return;
      }
      CurrentMediaInventoryResult result;
      try {
        result = await _inventory.getCurrentMediaPage(
          CurrentMediaPageRequest(
            pageSize: _inventoryPageSize,
            afterMediaStoreId: legacyContinuation,
            continuationToken: continuationToken,
          ),
        );
      } catch (error) {
        inventoryTimer.stop();
        _diagnostics.mediaInventoryMs = inventoryTimer.elapsedMilliseconds;
        _diagnostics.currentMediaInventoryState = 'failed:exception';
        _rememberPendingStandardFailure(
          VerifiedSourceRecoveryFailure(
            source: source.mediaSource,
            code: VerifiedSourceRecoveryFailureCode.platformFailure,
            message:
                'Current-photo comparison failed (${error.runtimeType}); permitted recovery providers will still run with partial coverage.',
          ),
        );
        _buildRecoveryPipeline(
          records: recordsByIdentity.values,
          androidApiLevel: access.androidApiLevel,
        );
        return;
      }
      if (result is CurrentMediaInventoryFailureResult) {
        inventoryTimer.stop();
        _diagnostics.mediaInventoryMs = inventoryTimer.elapsedMilliseconds;
        _diagnostics.currentMediaInventoryState =
            'failed:${result.failure.code.name}';
        _rememberPendingStandardFailure(
          VerifiedSourceRecoveryFailure(
            source: source.mediaSource,
            code: switch (result.failure.code) {
              CurrentMediaInventoryFailureCode.mediaAccessUnavailable ||
              CurrentMediaInventoryFailureCode.securityDenied =>
                VerifiedSourceRecoveryFailureCode.accessUnavailable,
              CurrentMediaInventoryFailureCode.platformFailure ||
              CurrentMediaInventoryFailureCode.malformedPlatformResponse =>
                VerifiedSourceRecoveryFailureCode.platformFailure,
            },
            message: result.failure.message,
          ),
        );
        _buildRecoveryPipeline(
          records: recordsByIdentity.values,
          androidApiLevel: access.androidApiLevel,
        );
        return;
      }
      final page = (result as CurrentMediaInventorySuccess).page;
      _diagnostics.mediaInventoryPages++;
      _diagnostics.mediaStoreRowsReturned += page.items.length;
      final volume = page.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        _diagnostics.volumesScanned.add(volume);
      }
      for (final record in page.items) {
        if (_isCancelled(source)) return;
        final key =
            record.contentUri?.toString() ??
            '${record.storageVolumeName ?? 'unknown'}:${record.mediaStoreId}';
        if (recordsByIdentity.containsKey(key)) {
          _diagnostics.currentDuplicatesSuppressed++;
          continue;
        }
        if (recordsByIdentity.length >= maximumCurrentInventoryRecords) {
          inventoryLimitReached = true;
          break;
        }
        recordsByIdentity[key] = record;
        final candidate = const CurrentPhotoCandidateMapper().map(record);
        if (candidate == null) {
          _diagnostics.currentRowsRejected++;
          continue;
        }
        _diagnostics.currentPhotosMapped++;
      }
      if (kDebugMode) {
        debugPrint(
          'Recovery inventory page=${_diagnostics.mediaInventoryPages} '
          'rows=${page.items.length} mapped=${_diagnostics.currentPhotosMapped} '
          'totalRows=${_diagnostics.mediaStoreRowsReturned} '
          'valid=${_diagnostics.currentPhotosMapped} '
          'rejected=${_diagnostics.currentRowsRejected} '
          'duplicates=${_diagnostics.currentDuplicatesSuppressed}',
        );
      }
      if (inventoryLimitReached) break;
      final nextToken = page.nextContinuationToken;
      final nextId = page.nextAfterMediaStoreId;
      if (nextToken == null && nextId == null) break;
      if (_diagnostics.mediaInventoryPages >= maximumCurrentInventoryPages) {
        inventoryLimitReached = true;
        break;
      }
      final key = nextToken ?? 'legacy:$nextId';
      if (!seenContinuations.add(key)) {
        inventoryTimer.stop();
        _diagnostics.mediaInventoryMs = inventoryTimer.elapsedMilliseconds;
        _diagnostics.currentMediaInventoryState = 'failed:repeatedContinuation';
        _rememberPendingStandardFailure(
          VerifiedSourceRecoveryFailure(
            source: source.mediaSource,
            code: VerifiedSourceRecoveryFailureCode.platformFailure,
            message: 'Current-media pagination continuation repeated.',
          ),
        );
        _buildRecoveryPipeline(
          records: recordsByIdentity.values,
          androidApiLevel: access.androidApiLevel,
        );
        return;
      }
      continuationToken = nextToken;
      legacyContinuation = nextToken == null ? nextId : null;
    } while (true);
    inventoryTimer.stop();
    _diagnostics.mediaInventoryMs = inventoryTimer.elapsedMilliseconds;

    if (_isCancelled(source)) return;

    final records = recordsByIdentity.values.toList(growable: false);
    if (inventoryLimitReached) {
      _diagnostics.currentMediaInventoryState = 'resourceLimitPartial';
      _rememberPendingStandardFailure(
        VerifiedSourceRecoveryFailure(
          source: source.mediaSource,
          code: VerifiedSourceRecoveryFailureCode.resourceLimit,
          message: 'Current-media comparison reached a safe page or record limit. Permitted recovery providers still ran, but comparison and overall coverage are partial.',
        ),
      );
      _buildRecoveryPipeline(
        records: records,
        androidApiLevel: access.androidApiLevel,
      );
      return;
    }
    _diagnostics.currentMediaInventoryState = 'completed';
    _buildRecoveryPipeline(
      records: records,
      androidApiLevel: access.androidApiLevel,
    );
  }

  void _buildRecoveryPipeline({
    required Iterable<CurrentMediaRecord> records,
    required int androidApiLevel,
  }) {
    final retainedRecords = records.toList(growable: false);
    _diagnostics.currentRecordsScanned = retainedRecords.length;
    final indexTimer = Stopwatch()..start();
    final existingMediaIndex = ExistingMediaIndex.build(
      records: retainedRecords,
    );
    indexTimer.stop();
    _diagnostics.existingIndexBuildMs = indexTimer.elapsedMilliseconds;
    _existingMediaIndex = existingMediaIndex;

    final artifactMapper = const CurrentPhotoCandidateMapper();
    final exclusionEngine = const ExistingMediaExclusionEngine();
    final evidenceClassifier = const RecoveryEvidenceClassifier();
    final artifacts = <String, MediaCandidate>{};
    for (final record in retainedRecords) {
      final candidate = artifactMapper.mapRecoveryArtifact(record);
      if (candidate == null) continue;
      final decision = evidenceClassifier.classify(
        candidate: candidate,
        existingMediaDecision: exclusionEngine.evaluate(
          candidate,
          existingMediaIndex,
        ),
      );
      if (decision.classification == RecoveryClassification.possibleCopy) {
        artifacts.putIfAbsent(candidate.id, () => candidate);
      }
    }
    if (artifacts.isNotEmpty) {
      _possibleCopies = List<MediaCandidate>.unmodifiable(artifacts.values);
      _diagnostics.mediaStoreArtifactsDiscovered = artifacts.length;
      _refreshPossibleCopyDiagnostics();
      _diagnostics.markFirstValidResult();
    }

    final trash = _DiagnosticsTrashDiscovery(
      delegate: _prefetchedTrash ?? _trashDiscovery,
      diagnostics: _diagnostics,
    );
    final shared = VerifiedSourceRecoveryPipeline(trashDiscovery: trash);
    _delegate = ExistingRecoveryPipelinePageSource(
      cameraGallery: CameraGalleryRecoveryPipeline(trashDiscovery: trash),
      messaging: MessagingRecoveryPipeline(trashDiscovery: trash),
      screenshotsDownloads: ScreenshotsDownloadsRecoveryPipeline(
        trashDiscovery: trash,
      ),
      scopedStorage: ScopedStorageRecoveryPipeline(sourcePipeline: shared),
      allPhotos: shared,
      existingMediaIndex: existingMediaIndex,
      androidApiLevel: androidApiLevel,
    );
  }

  Future<void> _scanDeepStorage(
    RecoveryScanSource source,
    ExistingMediaIndex existingMediaIndex,
  ) async {
    _deepRunState = 'checkingCapability';
    DeepStorageCapabilityState capability;
    try {
      capability = await _deepStorageProvider.getCapability();
    } catch (_) {
      _deepRunState = 'failedCapabilityCheck';
      _deepCapabilityStatus = DeepStorageCapabilityStatus.failed;
      _deepCapabilityMessage = 'Optional shared-storage scanning could not be checked. Recovery candidates already found are retained.';
      _diagnostics.deepCapabilityState = _deepRunState;
      _diagnostics.deepProviderState = _deepRunState;
      return;
    }
    _deepCapabilityStatus = capability.status;
    _canRequestDeepStorageAccess = capability.requestSupported;
    _deepCapabilityMessage = _capabilityMessage(capability);
    _diagnostics.deepCapabilityState = capability.status.name;
    _diagnostics.deepProviderState =
        capability.status == DeepStorageCapabilityStatus.available
        ? 'running'
        : 'skipped:${capability.status.name}';
    _diagnostics.allFilesAccessGranted =
        capability.requiresAllFilesAccess && capability.available;
    _diagnostics.accessMode = capability.mode.name;
    if (!capability.available) {
      if (_prefetchedDeep != null)
        await _deepStorageProvider.cancelActiveScan();
      _deepRunState = switch (capability.status) {
        DeepStorageCapabilityStatus.accessRequired => 'skippedAccessRequired',
        DeepStorageCapabilityStatus.unavailable => 'skippedUnavailable',
        DeepStorageCapabilityStatus.unsupported => 'skippedUnsupported',
        DeepStorageCapabilityStatus.failed => 'skippedCapabilityFailure',
        DeepStorageCapabilityStatus.available => 'pending',
      };
      _diagnostics.deepProviderState = _deepRunState;
      return;
    }
    if (_isCancelled(source)) {
      _deepRunState = 'cancelled';
      _diagnostics.deepProviderState = _deepRunState;
      _deepCapabilityMessage = 'The optional deep scan was cancelled. Results found so far are kept.';
      return;
    }

    _deepRunState = 'running';
    _diagnostics.deepProviderState = 'running';
    DeepRecoveryEngineResult result;
    try {
      result = await const DeepRecoveryEngine().scan(
        providers: [_prefetchedDeep ?? _deepStorageProvider],
        existingMediaIndex: existingMediaIndex,
        alreadyDiscoveredStorageLocationKeys: _possibleCopies
            .map(
              (candidate) => ExistingMediaKeys.storageLocation(
                storageVolumeName: candidate.storageVolumeName,
                relativeLocation: candidate.relativeLocation,
                displayName: candidate.displayName,
                byteSize: candidate.byteSize,
              ),
            )
            .whereType<String>()
            .toSet(),
        source: source.mediaSource,
        profile: profile,
        cancellationToken: _cancellationToken,
        pageSize: 200,
        onProgress: (progress) {
          _diagnostics.deepProviderPages = progress.pageCount;
          _remainingNativeQueue = progress.providerExhausted
              ? 0
              : progress.remainingDirectoryQueue;
          _lastContinuationState = progress.providerExhausted
              ? 'exhausted'
              : 'present';
          if (kDebugMode) {
            debugPrint(
              'Deep page=${progress.pageCount} cursor=${progress.cursorIdentifier ?? 'none'} '
              'files=${progress.pageFilesExamined} directories=${progress.pageDirectoriesConsumed} '
              'records=${progress.pageRecordsReturned} inaccessibleDirs=${progress.unavailableDirectories} '
              'remaining=${progress.remainingDirectoryQueue} '
              'visited=${progress.visitedDirectoryCount} duplicateDirs=${progress.duplicateDirectorySkips} '
              'repeatedCursors=${progress.repeatedCursorDetections} exhausted=${progress.providerExhausted} '
              'reason=${progress.completionReason ?? 'continuing'}',
            );
          }
          _publishProgressCandidates(progress);
          onDeepProgress?.call(progress);
        },
      );
    } catch (error) {
      _deepRunState = 'partialFailure';
      _lastContinuationState = 'failedOrExpired';
      _deepCapabilityMessage = 'The optional deep scan ended early; recovery candidates already found are kept.';
      _diagnostics.deepProviderState = _deepRunState;
      _diagnostics.completionReason = 'providerException:${error.runtimeType}';
      return;
    }

    _diagnostics.filesExamined += result.filesExamined;
    _diagnostics.deepRecordsDiscovered += result.recordsDiscovered;
    _diagnostics.foldersVisited += result.directoriesExamined;
    _diagnostics.rootDirectoriesOpened = result.rootDirectoriesOpened;
    _diagnostics.signatureFilesInspected = result.signatureFilesInspected;
    _diagnostics.entriesExamined += result.entriesExamined;
    _diagnostics.currentFilesSkipped += result.currentFilesSkipped;
    _diagnostics.signatureCacheHits += result.signatureCacheHits;
    _diagnostics.signatureCacheMisses += result.signatureCacheMisses;
    _diagnostics.nativeTraversalMs = result.nativeTraversalMillis;
    _diagnostics.carvedTemporaryBytes = result.carvedTemporaryBytes;
    _diagnostics.carvedTempBytesReclaimed = result.carvedTempBytesReclaimed;
    _diagnostics.invalidFilesRejected += result.invalidFilesRejected;
    _diagnostics.unavailableFiles += result.unavailableFiles;
    _diagnostics.unavailableDirectories += result.unavailableDirectories;
    _diagnostics.unsupportedFiles += result.unsupportedFiles;
    _diagnostics.duplicateRecordsSuppressed +=
        result.duplicateRecordsSuppressed;
    _diagnostics.duplicateDirectorySkips += result.duplicateDirectorySkips;
    _diagnostics.repeatedCursorDetections += result.repeatedCursorDetections;
    _diagnostics.completionReason = result.completionReason ?? 'exhausted';
    _diagnostics.volumesScanned.addAll(result.volumesScanned);
    _diagnostics.excludedExisting += result.existingRecordsExcluded;
    _diagnostics.lowerPriorityRecordsOmitted +=
        result.lowerPriorityRecordsOmitted;
    _publishFinalDeepCandidates(result);
    _diagnostics.deepProviderState = result.completed
        ? 'completed'
        : _cancellationToken?.isCancelled == true
        ? 'cancelled'
        : 'partialFailure';
    if (result.completed) {
      _deepRunState = 'completed';
      _lastContinuationState = 'exhausted';
      _deepCapabilityMessage = null;
    } else if (_cancellationToken?.isCancelled == true ||
        result.completionReason == 'cancelled') {
      _deepRunState = 'cancelled';
      _lastContinuationState = result.failureAvailability == null
          ? 'cancelled'
          : 'failedOrExpired';
      _deepCapabilityMessage = 'The optional deep scan was cancelled. Results found so far are kept.';
    } else {
      _deepRunState = 'partialFailure';
      _lastContinuationState = 'failedOrExpired';
      _deepCapabilityMessage = result.failureMessage ?? 'The optional deep scan ended early; recovery candidates already found are kept.';
    }
  }

  void _publishProgressCandidates(DeepRecoveryEngineProgress progress) {
    if (progress.possibleCopyCandidates.isEmpty) return;
    final byId = {for (final item in _possibleCopies) item.id: item};
    for (final candidate in progress.possibleCopyCandidates) {
      if (candidate.classification == RecoveryClassification.possibleCopy) {
        byId.putIfAbsent(candidate.id, () => candidate);
      }
    }
    _possibleCopies = List<MediaCandidate>.unmodifiable(byId.values);
    if (_possibleCopies.isNotEmpty) {
      _diagnostics.copyCandidates = _possibleCopies.length;
      _diagnostics.markFirstValidResult();
    }
  }

  void _publishFinalDeepCandidates(DeepRecoveryEngineResult result) {
    final byId = {for (final item in _possibleCopies) item.id: item};
    for (final bucket in [
      DeepRecoveryDisposition.possibleFullQualityCopy,
      DeepRecoveryDisposition.possibleLowerQualityCopy,
      DeepRecoveryDisposition.possibleUnknownQualityCopy,
      DeepRecoveryDisposition.thumbnailCopy,
    ]) {
      for (final candidate in result.byDisposition[bucket] ?? const []) {
        byId.putIfAbsent(candidate.id, () => candidate);
      }
    }
    _possibleCopies = List<MediaCandidate>.unmodifiable(byId.values);
    _diagnostics.signatureMatches = result.recordsDiscovered;
    _refreshPossibleCopyDiagnostics();
    if (_possibleCopies.isNotEmpty) _diagnostics.markFirstValidResult();
  }

  void _refreshPossibleCopyDiagnostics() {
    _diagnostics.copyCandidates = _possibleCopies.length;
    _diagnostics.unknownSourceRetained = 0;
    _diagnostics.trashLikeCandidates = 0;
    _diagnostics.cacheCandidates = 0;
    _diagnostics.thumbnailCandidates = 0;
    _diagnostics.messagingCandidates = 0;
    _diagnostics.removableCandidates = 0;
    _diagnostics.extensionMismatchCandidates = 0;
    _diagnostics.embeddedPayloads = 0;
    _diagnostics.standaloneImageCandidates = 0;
    _diagnostics.finalFullQualityCopies = 0;
    _diagnostics.finalReducedCopies = 0;
    _diagnostics.finalUnknownQualityCopies = 0;
    _diagnostics.finalThumbnailCopies = 0;
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
      if (evidence.isThumbnailLike) {
        _diagnostics.finalThumbnailCopies++;
      } else if (candidate.recoveryQuality == RecoveryQuality.completeCopy) {
        _diagnostics.finalFullQualityCopies++;
      } else if (candidate.recoveryQuality ==
          RecoveryQuality.reducedResolutionCopy) {
        _diagnostics.finalReducedCopies++;
      } else {
        _diagnostics.finalUnknownQualityCopies++;
      }
    }
  }

  static String? _capabilityMessage(DeepStorageCapabilityState capability) {
    if (capability.available) return null;
    return switch (capability.status) {
      DeepStorageCapabilityStatus.accessRequired =>
        'Some protected locations could not be checked.',
      DeepStorageCapabilityStatus.unavailable =>
        'Some protected locations could not be checked.',
      DeepStorageCapabilityStatus.unsupported =>
        'Some protected locations could not be checked.',
      DeepStorageCapabilityStatus.failed =>
        'Some protected locations could not be checked.',
      DeepStorageCapabilityStatus.available => null,
    };
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

class _PrefetchedTrashDiscovery implements TrashDiscovery {
  _PrefetchedTrashDiscovery(this.delegate) {
    _firstPage = _loadFirstPage();
  }

  final TrashDiscovery delegate;
  late final Future<TrashDiscoveryResult> _firstPage;
  bool _used = false;
  bool wasPrefetchedLastCall = false;
  int firstPageElapsedMs = 0;

  Future<TrashDiscoveryResult> _loadFirstPage() async {
    final timer = Stopwatch()..start();
    try {
      return await delegate.getVerifiedTrashPage(
        const TrashDiscoveryPageRequest(pageSize: 200),
      );
    } catch (_) {
      return const TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(code: TrashDiscoveryFailureCode.platformFailure),
      );
    } finally {
      firstPageElapsedMs = timer.elapsedMilliseconds;
    }
  }

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) {
    wasPrefetchedLastCall = false;
    if (!_used &&
        request.pageSize == 200 &&
        request.afterMediaStoreId == null &&
        request.continuationToken == null) {
      _used = true;
      wasPrefetchedLastCall = true;
      return _firstPage;
    }
    return delegate.getVerifiedTrashPage(request);
  }
}

/// Holds one bounded native page until the complete current-photo index can
/// safely classify it. The provider's continuation remains in the same scan.
class _PrefetchedDeepStoragePage implements DeepRecoveryDiscoveryProvider {
  _PrefetchedDeepStoragePage(
    this.delegate, {
    required MediaSource source,
    required PhotoRecoveryProfile profile,
  }) {
    _firstPage = _loadFirstPage(source, profile);
  }

  final PlatformDeepStorageRecoveryProvider delegate;
  late final Future<DeepRecoveryProviderResult> _firstPage;
  bool _used = false;

  Future<DeepRecoveryProviderResult> _loadFirstPage(
    MediaSource source,
    PhotoRecoveryProfile profile,
  ) async {
    try {
      return await delegate.getPage(
        DeepRecoveryProviderRequest(
          pageSize: 200,
          source: source,
          profile: profile,
        ),
      );
    } catch (error) {
      return DeepRecoveryProviderUnavailable(
        DeepProviderAvailability.failed,
        message: 'The prefetched deep page failed (${error.runtimeType}).',
      );
    }
  }

  @override
  DeepRecoveryProviderKind get kind => delegate.kind;

  @override
  Set<DeepStorageAccessCapability> get requiredCapabilities =>
      delegate.requiredCapabilities;

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) {
    if (!_used &&
        request.continuationToken == null &&
        request.pageSize == 200) {
      _used = true;
      return _firstPage;
    }
    return delegate.getPage(request);
  }

  @override
  Future<void> cancelActiveScan() => delegate.cancelActiveScan();
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
    diagnostics.verifiedTrashMs +=
        delegate is _PrefetchedTrashDiscovery &&
            (delegate as _PrefetchedTrashDiscovery).wasPrefetchedLastCall
        ? (delegate as _PrefetchedTrashDiscovery).firstPageElapsedMs
        : stopwatch.elapsedMilliseconds;
    if (result is TrashDiscoverySuccess) {
      diagnostics.verifiedTrashPages++;
      diagnostics.verifiedTrashProviderState = result.page.mayHaveMore
          ? 'running'
          : 'completed';
      diagnostics.trashCandidates += result.page.items.length;
      diagnostics.rawTrashRows += result.page.rawRowsExamined;
      diagnostics.inaccessibleTrashRows += result.page.inaccessibleFiles;
      diagnostics.invalidFilesRejected += result.page.invalidFilesRejected;
      diagnostics.unavailableFiles += result.page.inaccessibleFiles;
      final volume = result.page.scannedVolumeName;
      if (volume != null && volume.isNotEmpty) {
        diagnostics.volumesScanned.add(volume);
      }
    } else if (result is TrashDiscoveryUnsupported) {
      diagnostics.verifiedTrashProviderState = 'unsupported';
    } else if (result is TrashDiscoveryFailureResult) {
      diagnostics.verifiedTrashProviderState =
          'failed:${result.failure.code.name}';
    }
    return result;
  }
}
