import '../../recovery/application/source_recovery/verified_source_recovery_models.dart';
import '../../recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import '../../recovery/data/trash_discovery/trash_discovery_models.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/media_source.dart';
import 'recovery_scan_models.dart';
import 'recovery_scan_page_source.dart';

/// Presents the existing, source-isolated photo pipelines as one user-facing
/// photo scan. It never changes a candidate's source identity.
class AllPhotosRecoveryScanPageSource
    implements
        RecoveryScanPageSource,
        CancellationAwarePageSource,
        ActiveScanCancellationAwarePageSource,
        PossibleCopiesAwarePageSource,
        LimitedAccessAwarePageSource,
        DeepScanCapabilityAwarePageSource {
  AllPhotosRecoveryScanPageSource({
    required List<RecoveryScanPageSource> sources,
  }) : _sources = List.unmodifiable(sources) {
    if (_sources.length != _photoSources.length) {
      throw ArgumentError.value(
        sources,
        'sources',
        'One page source per photo source is required.',
      );
    }
  }

  static const _photoSources = [
    RecoveryScanSource.cameraGallery,
    RecoveryScanSource.screenshots,
    RecoveryScanSource.downloads,
    RecoveryScanSource.messaging,
  ];

  final List<RecoveryScanPageSource> _sources;
  final List<MediaCandidate> _possibleCopies = [];
  var _activeIndex = 0;
  TrashDiscoveryPageRequest _activeRequest = const TrashDiscoveryPageRequest(
    pageSize: 100,
  );

  @override
  set cancellationToken(value) {
    for (final source in _sources) {
      if (source is CancellationAwarePageSource) {
        (source as CancellationAwarePageSource).cancellationToken = value;
      }
    }
  }

  @override
  bool get isLimitedAccess => _sources.any(
    (source) =>
        source is LimitedAccessAwarePageSource &&
        (source as LimitedAccessAwarePageSource).isLimitedAccess,
  );

  @override
  List<MediaCandidate> get possibleCopies {
    final copiesById = <String, MediaCandidate>{};
    for (final candidate in _possibleCopies) {
      copiesById.putIfAbsent(candidate.id, () => candidate);
    }
    return List.unmodifiable(copiesById.values);
  }

  @override
  DeepStorageCapabilityStatus get deepCapabilityStatus {
    for (final source in _sources) {
      if (source is DeepScanCapabilityAwarePageSource &&
          (source as DeepScanCapabilityAwarePageSource).deepCapabilityStatus !=
              DeepStorageCapabilityStatus.available) {
        return (source as DeepScanCapabilityAwarePageSource)
            .deepCapabilityStatus;
      }
    }
    return DeepStorageCapabilityStatus.available;
  }

  @override
  String? get deepCapabilityMessage {
    for (final source in _sources) {
      if (source is DeepScanCapabilityAwarePageSource &&
          (source as DeepScanCapabilityAwarePageSource).deepCapabilityMessage !=
              null) {
        return (source as DeepScanCapabilityAwarePageSource)
            .deepCapabilityMessage;
      }
    }
    return null;
  }

  @override
  bool get canRequestDeepStorageAccess => _sources.any(
    (source) =>
        source is DeepScanCapabilityAwarePageSource &&
        (source as DeepScanCapabilityAwarePageSource)
            .canRequestDeepStorageAccess,
  );

  @override
  Future<void> openDeepScanSettings() async {
    for (final source in _sources) {
      if (source is DeepScanCapabilityAwarePageSource) {
        await (source as DeepScanCapabilityAwarePageSource)
            .openDeepScanSettings();
        return;
      }
    }
  }

  @override
  Future<bool> refreshDeepScanCapability() async {
    var available = true;
    for (final source in _sources) {
      if (source is DeepScanCapabilityAwarePageSource) {
        available =
            await (source as DeepScanCapabilityAwarePageSource)
                .refreshDeepScanCapability() &&
            available;
      }
    }
    return available;
  }

  @override
  Future<void> cancelActiveScan() async {
    for (final source in _sources) {
      if (source is ActiveScanCancellationAwarePageSource) {
        await (source as ActiveScanCancellationAwarePageSource)
            .cancelActiveScan();
      }
    }
  }

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource _,
    TrashDiscoveryPageRequest request,
  ) async {
    while (_activeIndex < _sources.length) {
      final source = _sources[_activeIndex];
      final result = await source.loadPage(
        _photoSources[_activeIndex],
        _activeRequest,
      );
      if (result is VerifiedSourceRecoveryUnsupported) {
        _advance();
        continue;
      }
      if (result is VerifiedSourceRecoveryFailure) return result;
      final success = result as VerifiedSourceRecoverySuccess;
      if (success.mayHaveMore) {
        _activeRequest = TrashDiscoveryPageRequest(
          pageSize: request.pageSize,
          afterMediaStoreId: success.nextAfterMediaStoreId,
          continuationToken: success.nextContinuationToken,
        );
        return success;
      }
      _collectCopies(source);
      _advance();
      return VerifiedSourceRecoverySuccess(
        source: MediaSource.unknown,
        items: success.items,
        diagnostics: success.diagnostics,
        nextContinuationToken: _activeIndex < _sources.length
            ? 'photo-source:$_activeIndex'
            : null,
        scannedVolumeName: success.scannedVolumeName,
      );
    }
    return const VerifiedSourceRecoverySuccess(
      source: MediaSource.unknown,
      items: [],
      diagnostics: VerifiedSourceRecoveryDiagnostics(
        examinedCount: 0,
        excludedExistingCount: 0,
        filteredOtherSourceCount: 0,
        filteredIneligibleCount: 0,
      ),
    );
  }

  void _collectCopies(RecoveryScanPageSource source) {
    if (source is PossibleCopiesAwarePageSource) {
      _possibleCopies.addAll(
        (source as PossibleCopiesAwarePageSource).possibleCopies,
      );
    }
  }

  void _advance() {
    _activeIndex++;
    _activeRequest = const TrashDiscoveryPageRequest(pageSize: 100);
  }
}
