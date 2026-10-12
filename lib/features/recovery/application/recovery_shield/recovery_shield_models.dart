import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../reliability/recovery_operation_failure.dart';

class RecoveryShieldProtectionRequest {
  const RecoveryShieldProtectionRequest({
    required this.protectionId,
    required this.candidate,
    required this.sourceUri,
    required this.stableSourceIdentity,
  });

  final String protectionId;
  final MediaCandidate candidate;
  final Uri sourceUri;
  final String stableSourceIdentity;
}

enum RecoveryShieldProtectionStatus {
  protected,
  alreadyProtected,
  updated,
  sourceUnavailable,
  accessFailure,
  insufficientStorage,
  integrityFailure,
  cancelled,
  operationInProgress,
  platformFailure,
}

class ProtectedMediaRecord {
  const ProtectedMediaRecord({
    required this.protectionId,
    required this.originalSource,
    required this.protectedCopyLocation,
    required this.sha256Digest,
    required this.protectedAt,
    required this.byteSize,
    this.originalContentUri,
    this.displayName,
    this.mimeType,
    this.originalLocation,
    this.width,
    this.height,
    this.createdAt,
    this.modifiedAt,
    this.takenAt,
  });

  final String protectionId;
  final Uri? originalContentUri;
  final MediaSource originalSource;
  final String? displayName;
  final String? mimeType;
  final String? originalLocation;
  final int byteSize;
  final int? width;
  final int? height;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final DateTime? takenAt;
  final String protectedCopyLocation;
  final String sha256Digest;
  final DateTime protectedAt;
}

class RecoveryShieldProtectionResult {
  const RecoveryShieldProtectionResult({
    required this.protectionId,
    required this.status,
    this.record,
    this.message,
    this.failure,
  });

  final String protectionId;
  final RecoveryShieldProtectionStatus status;
  final ProtectedMediaRecord? record;
  final String? message;
  final RecoveryOperationFailure? failure;

  bool get isSuccessful =>
      status == RecoveryShieldProtectionStatus.protected ||
      status == RecoveryShieldProtectionStatus.alreadyProtected ||
      status == RecoveryShieldProtectionStatus.updated;
}

class RecoveryShieldBatchResult {
  const RecoveryShieldBatchResult(this.items);

  final List<RecoveryShieldProtectionResult> items;
}

class RecoveryShieldProtectionState {
  RecoveryShieldProtectionState({
    Iterable<ProtectedMediaRecord> records = const [],
  }) : _records = {for (final record in records) record.protectionId: record};

  final Map<String, ProtectedMediaRecord> _records;

  ProtectedMediaRecord? recordFor(String protectionId) =>
      _records[protectionId];

  void apply(RecoveryShieldProtectionResult result) {
    if (result.isSuccessful && result.record != null) {
      _records[result.protectionId] = result.record!;
    }
  }
}
