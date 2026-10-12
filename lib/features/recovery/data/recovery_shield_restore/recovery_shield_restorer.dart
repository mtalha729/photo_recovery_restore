import '../../application/recovery_shield_restore/recovery_shield_restore_models.dart';

abstract interface class RecoveryShieldRestorer {
  Future<RecoveryShieldRestoreResult> restore(
    RecoveryShieldRestoreRequest request,
  );

  Future<RecoveryShieldRestoreBatchResult> restoreBatch(
    Iterable<RecoveryShieldRestorePreparation> preparations,
  );
}
