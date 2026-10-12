import 'deletion_evidence.dart';
import 'media_source.dart';
import 'recovery_classification.dart';
import 'recovery_quality.dart';
import 'recovery_discovery_evidence.dart';
import 'restore_capability.dart';
import 'verified_content_digest.dart';

class MediaCandidate {
  MediaCandidate({
    required this.id,
    required this.source,
    required this.classification,
    required this.deletionEvidence,
    required this.restoreCapability,
    required this.recoveryQuality,
    this.contentUri,
    this.mediaStoreId,
    this.filePath,
    this.displayName,
    this.mimeType,
    this.relativeLocation,
    this.bucketName,
    this.storageVolumeName,
    this.isRemovableStorage,
    this.documentUri,
    this.verifiedContentDigest,
    this.byteSize,
    this.width,
    this.height,
    this.createdAt,
    this.modifiedAt,
    this.takenAt,
    this.deletedAt,
    this.discoveryEvidence = const RecoveryDiscoveryEvidence(),
  }) : assert(id != '');

  final String id;
  final MediaSource source;
  final Uri? contentUri;
  final int? mediaStoreId;
  final String? filePath;
  final String? displayName;
  final String? mimeType;
  final String? relativeLocation;
  final String? bucketName;
  final String? storageVolumeName;
  final bool? isRemovableStorage;
  final Uri? documentUri;
  final VerifiedContentDigest? verifiedContentDigest;
  final int? byteSize;
  final int? width;
  final int? height;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final DateTime? takenAt;
  final DateTime? deletedAt;
  final RecoveryDiscoveryEvidence discoveryEvidence;
  final RecoveryClassification classification;
  final DeletionEvidence deletionEvidence;
  final RestoreCapability restoreCapability;
  final RecoveryQuality recoveryQuality;

  bool get isVerifiedDeleted => classification.isVerifiedDeleted;

  bool get isDeletedRecoveryResult => classification.isDeletedRecoveryResult;

  MediaCandidate withSource(MediaSource value) {
    return MediaCandidate(
      id: id,
      source: value,
      contentUri: contentUri,
      mediaStoreId: mediaStoreId,
      filePath: filePath,
      displayName: displayName,
      mimeType: mimeType,
      relativeLocation: relativeLocation,
      bucketName: bucketName,
      storageVolumeName: storageVolumeName,
      isRemovableStorage: isRemovableStorage,
      documentUri: documentUri,
      verifiedContentDigest: verifiedContentDigest,
      byteSize: byteSize,
      width: width,
      height: height,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      takenAt: takenAt,
      deletedAt: deletedAt,
      discoveryEvidence: discoveryEvidence,
      classification: classification,
      deletionEvidence: deletionEvidence,
      restoreCapability: restoreCapability,
      recoveryQuality: recoveryQuality,
    );
  }
}
