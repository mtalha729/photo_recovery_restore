import '../../domain/media_candidate.dart';
import '../recovery_shield/recovery_shield_models.dart';
import '../scoped_storage_recovery/storage_scope_models.dart';
import '../reliability/recovery_operation_failure.dart';

enum RecoveryShieldRestoreStatus {
  restored,
  alreadyPresent,
  notEligible,
  protectedCopyMissing,
  integrityFailure,
  destinationRequired,
  accessRequired,
  insufficientStorage,
  writeFailure,
  verificationFailure,
  operationInProgress,
  platformFailure,
}

class RecoveryShieldRestoreRequest {
  const RecoveryShieldRestoreRequest({
    required this.record,
    required this.originalCandidate,
    this.relativeDestination,
    this.authorizedDestinationScope,
  });

  final ProtectedMediaRecord record;
  final MediaCandidate originalCandidate;
  final String? relativeDestination;
  final AuthorizedFolderScope? authorizedDestinationScope;
}

class RecoveryShieldRestorePreparation {
  const RecoveryShieldRestorePreparation._({this.request, this.rejection});

  const RecoveryShieldRestorePreparation.eligible(
    RecoveryShieldRestoreRequest value,
  ) : this._(request: value);

  const RecoveryShieldRestorePreparation.rejected(
    RecoveryShieldRestoreResult value,
  ) : this._(rejection: value);

  final RecoveryShieldRestoreRequest? request;
  final RecoveryShieldRestoreResult? rejection;

  bool get isEligible => request != null;
}

class RecoveryShieldRestoreResult {
  const RecoveryShieldRestoreResult({
    required this.protectionId,
    required this.status,
    this.restoredContentUri,
    this.message,
    this.usedPendingPublish = false,
    this.failure,
  });

  final String protectionId;
  final RecoveryShieldRestoreStatus status;
  final Uri? restoredContentUri;
  final String? message;
  final bool usedPendingPublish;
  final RecoveryOperationFailure? failure;

  bool get isSuccessful => status == RecoveryShieldRestoreStatus.restored;
}

class RecoveryShieldRestoreBatchResult {
  const RecoveryShieldRestoreBatchResult(this.items);

  final List<RecoveryShieldRestoreResult> items;
}
