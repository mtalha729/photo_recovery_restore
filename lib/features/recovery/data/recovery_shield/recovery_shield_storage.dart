import '../../application/recovery_shield/recovery_shield_models.dart';

abstract interface class RecoveryShieldStorage {
  Future<RecoveryShieldProtectionResult> protect(
    RecoveryShieldProtectionRequest request,
  );

  Future<RecoveryShieldBatchResult> protectBatch(
    Iterable<RecoveryShieldProtectionRequest> requests,
  );
}
