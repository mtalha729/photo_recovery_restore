import '../../domain/deletion_evidence.dart';
import '../../domain/recovery_classification.dart';
import '../media_metadata/current_media_metadata.dart';

class VerifiedTrashItem {
  VerifiedTrashItem._({
    required this.metadata,
    required this.initialBytesReadable,
  }) : deletionEvidence = DeletionEvidence(
         reasons: const [DeletionEvidenceReason.systemTrashRecord],
       );

  factory VerifiedTrashItem.fromPlatformTrash({
    required CurrentMediaMetadata metadata,
    bool initialBytesReadable = true,
  }) {
    return VerifiedTrashItem._(
      metadata: metadata,
      initialBytesReadable: initialBytesReadable,
    );
  }

  final CurrentMediaMetadata metadata;
  final bool initialBytesReadable;
  final DeletionEvidence deletionEvidence;

  RecoveryClassification get classification =>
      RecoveryClassification.verifiedDeleted;
}

class TrashDiscoveryPageRequest {
  const TrashDiscoveryPageRequest({
    required this.pageSize,
    this.afterMediaStoreId,
    this.continuationToken,
  }) : assert(pageSize > 0),
       assert(afterMediaStoreId == null || afterMediaStoreId >= 0);

  final int pageSize;
  final int? afterMediaStoreId;
  final String? continuationToken;
}

class TrashDiscoveryPage {
  const TrashDiscoveryPage({
    required this.items,
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
    this.invalidFilesRejected = 0,
    this.inaccessibleFiles = 0,
    this.rawRowsExamined = 0,
  });

  const TrashDiscoveryPage.empty() : this(items: const []);

  final List<VerifiedTrashItem> items;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;
  final int invalidFilesRejected;
  final int inaccessibleFiles;
  final int rawRowsExamined;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}

enum TrashDiscoveryFailureCode {
  mediaAccessUnavailable,
  securityDenied,
  platformFailure,
  malformedPlatformResponse,
}

class TrashDiscoveryFailure {
  const TrashDiscoveryFailure({required this.code, this.message});

  final TrashDiscoveryFailureCode code;
  final String? message;
}

sealed class TrashDiscoveryResult {
  const TrashDiscoveryResult();
}

class TrashDiscoverySuccess extends TrashDiscoveryResult {
  const TrashDiscoverySuccess(this.page);

  final TrashDiscoveryPage page;
}

class TrashDiscoveryUnsupported extends TrashDiscoveryResult {
  const TrashDiscoveryUnsupported({this.androidApiLevel});

  final int? androidApiLevel;
}

class TrashDiscoveryFailureResult extends TrashDiscoveryResult {
  const TrashDiscoveryFailureResult(this.failure);

  final TrashDiscoveryFailure failure;
}
