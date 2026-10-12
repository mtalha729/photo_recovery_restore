import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../possible_copies/possible_copy_models.dart';

/// Every legitimate discovery mechanism has an explicit provider identity.
enum DeepRecoveryProviderKind {
  currentMediaStore,
  verifiedMediaStoreTrash,
  directSharedStorage,
  unindexedOrphan,
  fileSignature,
  thumbnailCache,
  messagingSharedMedia,
  oemAccessibleTrash,
  authorizedSafTree,
  removableSharedVolume,
  recoveryShield,
}

enum DeepStorageAccessCapability {
  mediaStore,
  persistedSafTree,
  legacySharedRead,
  advancedSharedTraversal,
}

enum DeepProviderAvailability { available, accessRequired, unsupported, failed }

/// Controls how much of the same image-recovery pipeline is enabled.
///
/// Profiles do not change the truth rules used for classification. They only
/// control whether the optional, bounded container pass is requested after
/// the normal shared-storage traversal.
enum PhotoRecoveryProfile { fastDeep, thorough }

class DeepRecoveryDiscoveryRecord {
  const DeepRecoveryDiscoveryRecord({
    required this.candidate,
    required this.provider,
    this.relatedDeletedCandidateId,
    this.provenCopyType,
    this.relationshipEvidence,
    this.isAccessibleCurrentMedia = false,
  });

  final MediaCandidate candidate;
  final DeepRecoveryProviderKind provider;
  final String? relatedDeletedCandidateId;
  final PossibleCopyType? provenCopyType;
  final PossibleCopyRelationshipEvidence? relationshipEvidence;
  final bool isAccessibleCurrentMedia;

  bool get hasStrongCopyRelationship =>
      relatedDeletedCandidateId != null &&
      provenCopyType != null &&
      relationshipEvidence != null;
}

class DeepRecoveryProviderRequest {
  const DeepRecoveryProviderRequest({
    required this.pageSize,
    required this.source,
    this.profile = PhotoRecoveryProfile.fastDeep,
    this.continuationToken,
    this.currentMediaLocationKeys = const {},
  }) : assert(pageSize > 0 && pageSize <= 200);

  final int pageSize;
  final MediaSource source;
  final PhotoRecoveryProfile profile;
  final String? continuationToken;

  /// Passed only when a native direct-storage session is created. These are
  /// exact identities, not filename-only matches.
  final Set<String> currentMediaLocationKeys;
}

sealed class DeepRecoveryProviderResult {
  const DeepRecoveryProviderResult();
}

class DeepRecoveryProviderPage extends DeepRecoveryProviderResult {
  const DeepRecoveryProviderPage({
    required this.items,
    this.nextContinuationToken,
    this.filesExamined = 0,
    this.entriesExamined = 0,
    this.currentFilesSkipped = 0,
    this.signatureCacheHits = 0,
    this.signatureCacheMisses = 0,
    this.nativeTraversalMillis = 0,
    this.carvedTemporaryBytes = 0,
    this.carvedTempBytesReclaimed = 0,
    this.invalidFilesRejected = 0,
    this.unavailableFiles = 0,
    this.unsupportedFiles = 0,
    this.directoriesExamined = 0,
    this.directoryWorkConsumed = 0,
    this.candidatesFound = 0,
    this.volumesScanned = const {},
    this.remainingDirectoryQueue = 0,
    this.visitedDirectoryCount = 0,
    this.duplicateDirectorySkips = 0,
    this.repeatedCursorDetections = 0,
    this.providerExhausted = false,
    this.completionReason,
    this.currentArea,
  });

  final List<DeepRecoveryDiscoveryRecord> items;
  final String? nextContinuationToken;
  final int filesExamined;
  final int entriesExamined;
  final int currentFilesSkipped;
  final int signatureCacheHits;
  final int signatureCacheMisses;
  final int nativeTraversalMillis;
  final int carvedTemporaryBytes;
  final int carvedTempBytesReclaimed;
  final int invalidFilesRejected;
  final int unavailableFiles;
  final int unsupportedFiles;
  final int directoriesExamined;
  final int directoryWorkConsumed;
  final int candidatesFound;
  final Set<String> volumesScanned;
  final int remainingDirectoryQueue;
  final int visitedDirectoryCount;
  final int duplicateDirectorySkips;
  final int repeatedCursorDetections;
  final bool providerExhausted;
  final String? completionReason;
  final String? currentArea;
}

class DeepRecoveryProviderUnavailable extends DeepRecoveryProviderResult {
  const DeepRecoveryProviderUnavailable(this.availability, {this.message});

  final DeepProviderAvailability availability;
  final String? message;
}

abstract interface class DeepRecoveryDiscoveryProvider {
  DeepRecoveryProviderKind get kind;
  Set<DeepStorageAccessCapability> get requiredCapabilities;

  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  );
}

/// Boundary for any future Play-reviewed storage capability. V2 never silently
/// upgrades to broad filesystem access.
abstract interface class AdvancedStorageCapabilityBoundary {
  Future<bool> isAvailable(DeepStorageAccessCapability capability);
}
