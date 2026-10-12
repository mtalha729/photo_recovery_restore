import '../../recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import '../../recovery/application/restore/system_trash_restore_models.dart';
import '../../recovery/data/recovery_shield_restore/recovery_shield_restorer.dart';
import '../../recovery/data/restore/platform_system_trash_restore.dart';
import 'restore_ux_models.dart';
import '../../recovery/data/restore/file_copy_restorer.dart';
import '../../recovered_photos/application/recovered_photos_store.dart';

class RestoreUxCoordinator {
  const RestoreUxCoordinator({
    required this.systemTrashExecutor,
    this.shieldRestorer,
    this.fileCopyRestorer,
    this.historyStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SystemTrashRestoreExecutor systemTrashExecutor;
  final RecoveryShieldRestorer? shieldRestorer;
  final FileCopyRestorer? fileCopyRestorer;
  final RecoveredPhotosStore? historyStore;
  final DateTime Function() _clock;

  Future<RestoreBatchOutcome> restore(List<RestoreReviewItem> items) async {
    final outcomes = <RestoreItemOutcome>[];
    final systemItems = items
        .where((item) => item.route == RestoreRoute.systemTrash)
        .toList();
    final systemRequests = systemItems
        .map((item) => item.systemRequest)
        .whereType<SystemTrashRestoreRequest>()
        .toList();
    if (systemRequests.isNotEmpty) {
      final result = await systemTrashExecutor.restoreBatch(
        SystemTrashRestoreBatch(systemRequests),
      );
      final affectedUris = result.affectedUris.map((uri) => uri.toString()).toSet();
      for (final item in systemItems.where(
        (item) => item.systemRequest != null,
      )) {
        final restoredUri = item.candidate.contentUri;
        final confirmed = result.status == SystemTrashRestoreStatus.restored &&
            restoredUri != null && affectedUris.contains(restoredUri.toString());
        outcomes.add(
          await _outcomeFor(
            item,
            confirmed ? RestoreOutcomeStatus.restored :
                (result.status == SystemTrashRestoreStatus.restored
                    ? RestoreOutcomeStatus.verificationFailure
                    : _systemStatus(result.status)),
            restoredContentUri: confirmed ? restoredUri : null,
          ),
        );
      }
    }

    for (final item in items) {
      if (item.route == RestoreRoute.systemTrash &&
          item.systemRequest != null) {
        continue;
      }
      if (item.route == RestoreRoute.recoveryShield &&
          item.shieldPreparation?.isEligible == true &&
          shieldRestorer != null) {
        final result = await shieldRestorer!.restore(
          item.shieldPreparation!.request!,
        );
        outcomes.add(
          await _outcomeFor(
            item,
            _shieldStatus(result.status),
            restoredContentUri: result.status == RecoveryShieldRestoreStatus.restored
                ? result.restoredContentUri
                : null,
          ),
        );
      } else if (item.route == RestoreRoute.fileCopy &&
          item.fileCopyRequest != null &&
          fileCopyRestorer != null) {
        final result = await fileCopyRestorer!.restore(item.fileCopyRequest!);
        outcomes.add(
          await _outcomeFor(
            item,
            _fileCopyStatus(result.status),
            restoredContentUri: result.status == FileCopyRestoreStatus.restored
                ? result.destinationUri
                : null,
          ),
        );
      } else {
        outcomes.add(
          RestoreItemOutcome(
            itemId: item.candidate.id,
            status: _rejectionStatus(item),
          ),
        );
      }
    }
    return RestoreBatchOutcome(List.unmodifiable(outcomes));
  }

  Future<RestoreItemOutcome> _outcomeFor(
    RestoreReviewItem item,
    RestoreOutcomeStatus status, {
    Uri? restoredContentUri,
  }) async {
    final verifiedUri = status == RestoreOutcomeStatus.restored &&
            restoredContentUri?.scheme == 'content'
        ? restoredContentUri
        : null;
    if (verifiedUri != null && historyStore != null) {
      await historyStore!.upsert(
        RecoveredPhotoRecord.fromCandidate(
          contentUri: verifiedUri,
          candidate: item.candidate,
          restoredAt: _clock(),
        ),
      );
    }
    return RestoreItemOutcome(
      itemId: item.candidate.id,
      status: status,
      restoredContentUri: verifiedUri,
    );
  }
  static RestoreOutcomeStatus _systemStatus(SystemTrashRestoreStatus status) =>
      switch (status) {
        SystemTrashRestoreStatus.restored => RestoreOutcomeStatus.restored,
        SystemTrashRestoreStatus.userDeniedOrCancelled =>
          RestoreOutcomeStatus.userCancelled,
        SystemTrashRestoreStatus.staleOrMissingMediaItem =>
          RestoreOutcomeStatus.staleOrMissing,
        SystemTrashRestoreStatus.accessFailure =>
          RestoreOutcomeStatus.accessRequired,
        SystemTrashRestoreStatus.verificationFailed =>
          RestoreOutcomeStatus.verificationFailure,
        _ => RestoreOutcomeStatus.platformFailure,
      };

  static RestoreOutcomeStatus _shieldStatus(
    RecoveryShieldRestoreStatus status,
  ) => switch (status) {
    RecoveryShieldRestoreStatus.restored => RestoreOutcomeStatus.restored,
    RecoveryShieldRestoreStatus.alreadyPresent =>
      RestoreOutcomeStatus.alreadyPresent,
    RecoveryShieldRestoreStatus.destinationRequired =>
      RestoreOutcomeStatus.destinationRequired,
    RecoveryShieldRestoreStatus.accessRequired =>
      RestoreOutcomeStatus.accessRequired,
    RecoveryShieldRestoreStatus.integrityFailure =>
      RestoreOutcomeStatus.integrityFailure,
    RecoveryShieldRestoreStatus.protectedCopyMissing =>
      RestoreOutcomeStatus.staleOrMissing,
    RecoveryShieldRestoreStatus.insufficientStorage =>
      RestoreOutcomeStatus.insufficientStorage,
    RecoveryShieldRestoreStatus.verificationFailure =>
      RestoreOutcomeStatus.verificationFailure,
    RecoveryShieldRestoreStatus.notEligible => RestoreOutcomeStatus.notEligible,
    _ => RestoreOutcomeStatus.platformFailure,
  };

  static RestoreOutcomeStatus _rejectionStatus(RestoreReviewItem item) {
    final shieldStatus = item.shieldPreparation?.rejection?.status;
    return shieldStatus == null
        ? RestoreOutcomeStatus.notEligible
        : _shieldStatus(shieldStatus);
  }

  static RestoreOutcomeStatus _fileCopyStatus(FileCopyRestoreStatus status) =>
      switch (status) {
        FileCopyRestoreStatus.restored => RestoreOutcomeStatus.restored,
        FileCopyRestoreStatus.sourceUnavailable =>
          RestoreOutcomeStatus.staleOrMissing,
        FileCopyRestoreStatus.accessRequired =>
          RestoreOutcomeStatus.accessRequired,
        FileCopyRestoreStatus.insufficientStorage =>
          RestoreOutcomeStatus.insufficientStorage,
        FileCopyRestoreStatus.verificationFailure ||
        FileCopyRestoreStatus.invalidImage =>
          RestoreOutcomeStatus.verificationFailure,
        FileCopyRestoreStatus.writeFailure ||
        FileCopyRestoreStatus.platformFailure =>
          RestoreOutcomeStatus.platformFailure,
      };
}
