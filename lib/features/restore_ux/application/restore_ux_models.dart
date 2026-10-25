import '../../recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import '../../recovery/application/restore/system_trash_restore_models.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/data/restore/file_copy_restorer.dart';

enum RestoreRoute { systemTrash, recoveryShield, fileCopy, unavailable }

class RestoreReviewItem {
  const RestoreReviewItem({
    required this.candidate,
    required this.route,
    this.systemRequest,
    this.shieldPreparation,
    this.fileCopyRequest,
  });

  final MediaCandidate candidate;
  final RestoreRoute route;
  final SystemTrashRestoreRequest? systemRequest;
  final RecoveryShieldRestorePreparation? shieldPreparation;
  final FileCopyRestoreRequest? fileCopyRequest;

  bool get isEligible => switch (route) {
    RestoreRoute.systemTrash => systemRequest != null,
    RestoreRoute.recoveryShield => shieldPreparation?.isEligible == true,
    RestoreRoute.fileCopy => fileCopyRequest != null,
    RestoreRoute.unavailable => false,
  };

  String get expectedDestination => switch (route) {
    RestoreRoute.systemTrash =>
      candidate.relativeLocation ?? 'Original shared-media location',
    RestoreRoute.recoveryShield when shieldPreparation?.request != null =>
      shieldPreparation!.request!.relativeDestination ??
          (shieldPreparation!.request!.authorizedDestinationScope != null
              ? 'Authorized storage destination'
              : 'Destination required'),
    RestoreRoute.fileCopy => 'Pictures/Photo Recovery & Restore',
    _ => 'Unavailable',
  };
}

enum RestoreOutcomeStatus {
  restored,
  skippedDuplicate,
  cancelled,
  alreadyPresent,
  userCancelled,
  accessRequired,
  destinationRequired,
  integrityFailure,
  staleOrMissing,
  insufficientStorage,
  verificationFailure,
  notEligible,
  platformFailure,
}

enum RestoreSavedKind {
  trash,
  recoverableCopy,
  thumbnail,
  existingCopy,
  recoveryShield,
}

class RestoreCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

class RestoreItemOutcome {
  const RestoreItemOutcome({
    required this.itemId,
    required this.status,
    this.restoredContentUri,
    this.savedKind,
  });
  final String itemId;
  final RestoreOutcomeStatus status;
  final Uri? restoredContentUri;
  final RestoreSavedKind? savedKind;
}

class RestoreBatchOutcome {
  const RestoreBatchOutcome(this.items);
  final List<RestoreItemOutcome> items;

  int count(RestoreOutcomeStatus status) =>
      items.where((item) => item.status == status).length;
}
