import 'package:flutter/foundation.dart';

import '../../recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import '../../recovery/application/restore/system_trash_restore_models.dart';
import '../../recovery/data/recovery_shield_restore/recovery_shield_restorer.dart';
import '../../recovery/data/restore/platform_system_trash_restore.dart';
import '../../recovery/domain/recovery_result_kind.dart';
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

  Future<RestoreBatchOutcome> restore(
    List<RestoreReviewItem> items, {
    RestoreCancellationToken? cancellation,
    void Function(int completed, int total)? onProgress,
  }) async {
    final outcomes = <RestoreItemOutcome>[];
    final processed = <String>{};
    for (final item in items) {
      if (cancellation?.isCancelled == true) {
        outcomes.add(
          RestoreItemOutcome(
            itemId: item.candidate.id,
            status: RestoreOutcomeStatus.cancelled,
          ),
        );
      } else if (!processed.add(_identity(item))) {
        outcomes.add(
          RestoreItemOutcome(
            itemId: item.candidate.id,
            status: RestoreOutcomeStatus.skippedDuplicate,
          ),
        );
      } else {
        outcomes.add(await _restoreOne(item));
      }
      onProgress?.call(outcomes.length, items.length);
    }
    if (kDebugMode) {
      debugPrint(
        'Restore batch: selected=${items.length}, '
        'savedSuccessfully=${outcomes.where((item) => item.status == RestoreOutcomeStatus.restored).length}, '
        'notSaved=${outcomes.where((item) => item.status != RestoreOutcomeStatus.restored).length}',
      );
    }
    return RestoreBatchOutcome(List.unmodifiable(outcomes));
  }

  String _identity(RestoreReviewItem item) => [
    item.route.name,
    item.candidate.contentUri?.toString() ??
        item.candidate.documentUri?.toString() ??
        item.candidate.filePath ??
        item.candidate.id,
  ].join(':');

  Future<RestoreItemOutcome> _restoreOne(RestoreReviewItem item) async {
    try {
      if (item.route == RestoreRoute.systemTrash &&
          item.systemRequest != null) {
        final result = await systemTrashExecutor.restoreBatch(
          SystemTrashRestoreBatch([item.systemRequest!]),
        );
        final uri = item.candidate.contentUri;
        final confirmed =
            result.status == SystemTrashRestoreStatus.restored &&
            uri != null &&
            result.affectedUris.contains(uri);
        return await _outcomeFor(
          item,
          confirmed
              ? RestoreOutcomeStatus.restored
              : result.status == SystemTrashRestoreStatus.restored
              ? RestoreOutcomeStatus.verificationFailure
              : _systemStatus(result.status),
          restoredContentUri: confirmed ? uri : null,
        );
      }
      if (item.route == RestoreRoute.recoveryShield &&
          item.shieldPreparation?.isEligible == true &&
          shieldRestorer != null) {
        final result = await shieldRestorer!.restore(
          item.shieldPreparation!.request!,
        );
        return await _outcomeFor(
          item,
          _shieldStatus(result.status),
          restoredContentUri:
              result.status == RecoveryShieldRestoreStatus.restored
              ? result.restoredContentUri
              : null,
        );
      }
      if (item.route == RestoreRoute.fileCopy &&
          item.fileCopyRequest != null &&
          fileCopyRestorer != null) {
        final result = await fileCopyRestorer!.restore(item.fileCopyRequest!);
        final uri = result.destinationUri;
        return await _outcomeFor(
          item,
          result.status == FileCopyRestoreStatus.restored &&
                  (uri == null || uri.scheme != 'content')
              ? RestoreOutcomeStatus.verificationFailure
              : _fileCopyStatus(result.status),
          restoredContentUri: uri,
        );
      }
      return RestoreItemOutcome(
        itemId: item.candidate.id,
        status: _rejectionStatus(item),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Restore item failed: ${error.runtimeType}');
      return RestoreItemOutcome(
        itemId: item.candidate.id,
        status: RestoreOutcomeStatus.platformFailure,
      );
    }
  }

  Future<RestoreItemOutcome> _outcomeFor(
    RestoreReviewItem item,
    RestoreOutcomeStatus status, {
    Uri? restoredContentUri,
  }) async {
    final verifiedUri =
        status == RestoreOutcomeStatus.restored &&
            restoredContentUri?.scheme == 'content'
        ? restoredContentUri
        : null;
    if (verifiedUri != null && historyStore != null) {
      try {
        await historyStore!.upsert(
          RecoveredPhotoRecord.fromCandidate(
            contentUri: verifiedUri,
            candidate: item.candidate,
            restoredAt: _clock(),
          ),
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Saved-photo history update failed: ${error.runtimeType}');
        }
      }
    }
    return RestoreItemOutcome(
      itemId: item.candidate.id,
      status: status,
      restoredContentUri: verifiedUri,
      savedKind: status == RestoreOutcomeStatus.restored
          ? switch (item.route) {
              RestoreRoute.systemTrash => RestoreSavedKind.trash,
              RestoreRoute.recoveryShield => RestoreSavedKind.recoveryShield,
              RestoreRoute.fileCopy => switch (resultKindFor(item.candidate)) {
                RecoveryResultKind.thumbnail => RestoreSavedKind.thumbnail,
                RecoveryResultKind.existingPhoto =>
                  RestoreSavedKind.existingCopy,
                _ => RestoreSavedKind.recoverableCopy,
              },
              RestoreRoute.unavailable => null,
            }
          : null,
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
