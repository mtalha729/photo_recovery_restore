enum RecoveryClassification {
  unclassified,
  verifiedDeleted,
  protectedDeleted,
  possibleCopy,
  existingMedia,
  unavailable,
  corrupted,
}

extension RecoveryClassificationX on RecoveryClassification {
  bool get isVerifiedDeleted => this == RecoveryClassification.verifiedDeleted;

  bool get isDeletedRecoveryResult =>
      this == RecoveryClassification.verifiedDeleted ||
      this == RecoveryClassification.protectedDeleted;
}
