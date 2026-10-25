import 'package:flutter/services.dart';

import '../../application/deep_recovery/deep_recovery_provider.dart';
import '../../domain/deletion_evidence.dart';
import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import '../../domain/recovery_discovery_evidence.dart';

enum DeepStorageAccessMode {
  legacySharedRead,
  allFilesAccess,
  scopedMediaRead,
  scopedStorage,
  unavailable,
}

enum DeepStorageCapabilityStatus {
  available,
  accessRequired,
  unavailable,
  unsupported,
  failed,
}

class DeepStorageCapabilityState {
  const DeepStorageCapabilityState({
    required this.status,
    required this.requiresAllFilesAccess,
    required this.mode,
    required this.androidApiLevel,
    this.requestSupported = false,
    this.debugBuild = false,
    this.reason,
  });

  final DeepStorageCapabilityStatus status;
  bool get available => status == DeepStorageCapabilityStatus.available;
  final bool requiresAllFilesAccess;
  final DeepStorageAccessMode mode;
  final int? androidApiLevel;
  final bool requestSupported;
  final bool debugBuild;
  final String? reason;
}

class PlatformDeepStorageRecoveryProvider
    implements
        DeepRecoveryDiscoveryProvider,
        AdvancedStorageCapabilityBoundary {
  const PlatformDeepStorageRecoveryProvider()
    : _channel = const MethodChannel(_channelName);

  const PlatformDeepStorageRecoveryProvider.withChannel(this._channel);

  static const _channelName =
      'com.photorecoveryrestore.app/deep_storage_recovery';
  final MethodChannel _channel;

  @override
  DeepRecoveryProviderKind get kind =>
      DeepRecoveryProviderKind.directSharedStorage;

  @override
  Set<DeepStorageAccessCapability> get requiredCapabilities => const {
    DeepStorageAccessCapability.advancedSharedTraversal,
  };

  Future<DeepStorageCapabilityState> getCapability() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getCapability');
      return mapCapabilityResponse(raw);
    } on PlatformException {
      return _failedCapability;
    } on MissingPluginException {
      return _unsupportedCapability;
    }
  }

  static DeepStorageCapabilityState mapCapabilityResponse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return _failedCapability;
    return DeepStorageCapabilityState(
      status: switch (raw['status']) {
        'available' => DeepStorageCapabilityStatus.available,
        'accessRequired' => DeepStorageCapabilityStatus.accessRequired,
        'unavailable' => DeepStorageCapabilityStatus.unavailable,
        'unsupported' => DeepStorageCapabilityStatus.unsupported,
        _ =>
          raw['available'] == true
              ? DeepStorageCapabilityStatus.available
              : DeepStorageCapabilityStatus.failed,
      },
      requiresAllFilesAccess: raw['requiresAllFilesAccess'] == true,
      mode: switch (raw['accessMode']) {
        'legacySharedRead' => DeepStorageAccessMode.legacySharedRead,
        'allFilesAccess' => DeepStorageAccessMode.allFilesAccess,
        'scopedMediaRead' => DeepStorageAccessMode.scopedMediaRead,
        'scopedStorage' => DeepStorageAccessMode.scopedStorage,
        _ => DeepStorageAccessMode.unavailable,
      },
      androidApiLevel: raw['apiLevel'] is int ? raw['apiLevel']! as int : null,
      requestSupported: raw['requestSupported'] == true,
      debugBuild: raw['debugBuild'] == true,
      reason: _text(raw['reason']),
    );
  }

  Future<void> openAccessSettings() =>
      _channel.invokeMethod<void>('openDeepStorageAccessSettings');

  @override
  Future<void> cancelActiveScan() async {
    try {
      await _channel.invokeMethod<void>('cancelDeepStorageScan');
    } on PlatformException {
      // Cancellation remains best effort; the Dart token still blocks publish.
    } on MissingPluginException {
      // Non-Android hosts have no native scan to cancel.
    }
  }

  @override
  Future<bool> isAvailable(DeepStorageAccessCapability capability) async {
    if (capability != DeepStorageAccessCapability.advancedSharedTraversal) {
      return false;
    }
    return (await getCapability()).available;
  }

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getDeepStoragePage', {
        'pageSize': request.pageSize,
        'profile': request.profile.name,
        'continuationToken': request.continuationToken,
        // The native scan session retains this comparison index. Re-sending
        // it on every page makes large libraries pay the same channel-copy
        // cost hundreds of times.
        if (request.continuationToken == null)
          'existingStorageLocationKeys': request.existingStorageLocationKeys
              .toList(growable: false),
      });
      return mapResponse(raw);
    } on PlatformException catch (error) {
      return DeepRecoveryProviderUnavailable(
        DeepProviderAvailability.failed,
        message: error.message,
      );
    } on MissingPluginException {
      return const DeepRecoveryProviderUnavailable(
        DeepProviderAvailability.unsupported,
      );
    }
  }

  static DeepRecoveryProviderResult mapResponse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return _malformed();
    if (raw['status'] == 'failure') {
      final code = raw['code'];
      return DeepRecoveryProviderUnavailable(
        code == 'accessRequired'
            ? DeepProviderAvailability.accessRequired
            : code == 'unsupported'
            ? DeepProviderAvailability.unsupported
            : DeepProviderAvailability.failed,
        message: _text(raw['message']),
      );
    }
    final values = raw['items'];
    final token = raw['nextContinuationToken'];
    if (raw['status'] != 'success' ||
        values is! List<Object?> ||
        (token != null && token is! String)) {
      return _malformed();
    }
    final records = <DeepRecoveryDiscoveryRecord>[];
    for (final value in values) {
      if (value is! Map<Object?, Object?>) return _malformed();
      final path = _text(value['canonicalPath']) ?? _text(value['filePath']);
      final size = _nonNegative(value['byteSize']);
      final width = _positive(value['width']);
      final height = _positive(value['height']);
      final mime = _text(value['mimeType']);
      if (path == null || size == null || mime == null) return _malformed();
      final thumbnail = value['isThumbnailLike'] == true;
      final qualityUnknown = !thumbnail && (width == null || height == null);
      final reduced =
          thumbnail ||
          (width != null && height != null && width <= 512 && height <= 512);
      final source = _source(value['source']);
      records.add(
        DeepRecoveryDiscoveryRecord(
          provider: thumbnail
              ? DeepRecoveryProviderKind.thumbnailCache
              : value['isTrashLike'] == true
              ? DeepRecoveryProviderKind.oemAccessibleTrash
              : source == MediaSource.messagingSharedMedia
              ? DeepRecoveryProviderKind.messagingSharedMedia
              : DeepRecoveryProviderKind.unindexedOrphan,
          candidate: MediaCandidate(
            id: 'file:$path',
            source: source,
            filePath: path,
            displayName: _text(value['displayName']),
            mimeType: mime,
            relativeLocation: _text(value['relativePath']),
            storageVolumeName: _text(value['storageVolumeName']),
            isRemovableStorage: value['isRemovableStorage'] is bool
                ? value['isRemovableStorage']! as bool
                : null,
            byteSize: size,
            width: width,
            height: height,
            modifiedAt: _date(value['modifiedMillis']),
            classification: RecoveryClassification.possibleCopy,
            deletionEvidence: DeletionEvidence(),
            restoreCapability: qualityUnknown
                ? RestoreCapability.unknownQualityCopy
                : reduced
                ? RestoreCapability.lowerResolutionCopy
                : RestoreCapability.alternateFullQualityCopy,
            recoveryQuality: qualityUnknown
                ? RecoveryQuality.unknownQualityCopy
                : reduced
                ? RecoveryQuality.reducedResolutionCopy
                : RecoveryQuality.completeCopy,
            discoveryEvidence: RecoveryDiscoveryEvidence(
              canonicalPath: path,
              detectedFormat: _text(value['detectedFormat']),
              isTrashLike: value['isTrashLike'] == true,
              isThumbnailLike: thumbnail,
              isCacheLike: value['isCacheLike'] == true,
              isRecoveryCopyLike: value['isRecoveryCopyLike'] == true,
              isHidden: value['isHidden'] == true,
              isExtensionMismatch: value['isExtensionMismatch'] == true,
              isUnindexed: true,
              isEmbeddedPayload: value['isEmbeddedPayload'] == true,
              embeddedOffset: _nonNegative(value['embeddedOffset']),
              containerPath: _text(value['containerPath']),
            ),
          ),
        ),
      );
    }
    return DeepRecoveryProviderPage(
      items: List.unmodifiable(records),
      nextContinuationToken: token as String?,
      filesExamined: _nonNegative(raw['filesExamined']) ?? 0,
      entriesExamined: _nonNegative(raw['entriesExamined']) ?? 0,
      currentFilesSkipped: _nonNegative(raw['currentFilesSkipped']) ?? 0,
      signatureCacheHits: _nonNegative(raw['signatureCacheHits']) ?? 0,
      signatureCacheMisses: _nonNegative(raw['signatureCacheMisses']) ?? 0,
      nativeTraversalMillis: _nonNegative(raw['nativeTraversalMs']) ?? 0,
      carvedTemporaryBytes: _nonNegative(raw['carvedTemporaryBytes']) ?? 0,
      carvedTempBytesReclaimed:
          _nonNegative(raw['carvedTempBytesReclaimed']) ?? 0,
      invalidFilesRejected: _nonNegative(raw['invalidFilesRejected']) ?? 0,
      unavailableFiles: _nonNegative(raw['unavailableFiles']) ?? 0,
      unavailableDirectories: _nonNegative(raw['unavailableDirectories']) ?? 0,
      rootDirectoriesOpened: _nonNegative(raw['rootDirectoriesOpened']) ?? 0,
      signatureFilesInspected: _nonNegative(raw['standaloneFilesInspected']) ?? 0,
      unsupportedFiles: _nonNegative(raw['unsupportedFiles']) ?? 0,
      directoriesExamined: _nonNegative(raw['directoriesExamined']) ?? 0,
      directoryWorkConsumed: _nonNegative(raw['directoryWorkConsumed']) ?? 0,
      candidatesFound: _nonNegative(raw['candidatesFound']) ?? records.length,
      volumesScanned: _stringSet(raw['volumesScanned']),
      remainingDirectoryQueue:
          _nonNegative(raw['remainingDirectoryQueue']) ?? 0,
      visitedDirectoryCount: _nonNegative(raw['visitedDirectoryCount']) ?? 0,
      duplicateDirectorySkips:
          _nonNegative(raw['duplicateDirectorySkips']) ?? 0,
      repeatedCursorDetections:
          _nonNegative(raw['repeatedCursorDetections']) ?? 0,
      providerExhausted: raw['providerExhausted'] == true,
      completionReason: _text(raw['completionReason']),
      currentArea: _text(raw['currentArea']),
    );
  }

  static MediaSource _source(Object? raw) => switch (raw) {
    'cameraGallery' => MediaSource.cameraGallery,
    'screenshots' => MediaSource.screenshots,
    'downloadsSavedMedia' => MediaSource.downloadsSavedMedia,
    'messagingSharedMedia' => MediaSource.messagingSharedMedia,
    'sdCard' => MediaSource.sdCard,
    _ => MediaSource.unknown,
  };

  static DateTime? _date(Object? value) => value is int && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
      : null;
  static int? _nonNegative(Object? value) =>
      value is int && value >= 0 ? value : null;
  static int? _positive(Object? value) =>
      value is int && value > 0 ? value : null;
  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  static Set<String> _stringSet(Object? value) => value is List<Object?>
      ? Set.unmodifiable(value.map(_text).whereType<String>())
      : const {};
  static const _failedCapability = DeepStorageCapabilityState(
    status: DeepStorageCapabilityStatus.failed,
    requiresAllFilesAccess: false,
    mode: DeepStorageAccessMode.unavailable,
    androidApiLevel: null,
  );
  static const _unsupportedCapability = DeepStorageCapabilityState(
    status: DeepStorageCapabilityStatus.unsupported,
    requiresAllFilesAccess: false,
    mode: DeepStorageAccessMode.unavailable,
    androidApiLevel: null,
  );
  static DeepRecoveryProviderUnavailable _malformed() =>
      const DeepRecoveryProviderUnavailable(
        DeepProviderAvailability.failed,
        message: 'Malformed deep-storage response.',
      );
}
