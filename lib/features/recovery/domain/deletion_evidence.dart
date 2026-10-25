enum DeletionEvidenceReason {
  systemTrashRecord,
  sourceNoLongerAvailable,
  userSelectedDeletedLocation,
  externalStorageRecord,
}

class DeletionEvidence {
  const DeletionEvidence._(this.reasons);

  factory DeletionEvidence({
    Iterable<DeletionEvidenceReason> reasons = const [],
  }) {
    return DeletionEvidence._(Set.unmodifiable(reasons));
  }

  final Set<DeletionEvidenceReason> reasons;

  bool get isEmpty => reasons.isEmpty;
  bool get isNotEmpty => reasons.isNotEmpty;
}
