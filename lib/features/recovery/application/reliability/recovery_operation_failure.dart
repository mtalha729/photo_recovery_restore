enum RecoveryOperationFailureKind {
  accessRevoked,
  staleSource,
  storageUnavailable,
  insufficientStorage,
  readFailure,
  writeFailure,
  malformedResponse,
  unsupportedCapability,
  cancelled,
  verificationFailure,
  operationConflict,
  platformFailure,
}

class RecoveryOperationFailure {
  const RecoveryOperationFailure({
    required this.kind,
    required this.operationId,
    this.itemId,
    this.message,
    this.retryable = false,
  });

  final RecoveryOperationFailureKind kind;
  final String operationId;
  final String? itemId;
  final String? message;
  final bool retryable;
}
