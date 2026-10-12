enum RestoreCapability {
  originalFullQuality,
  protectedOriginal,
  alternateFullQualityCopy,
  lowerResolutionCopy,
  metadataOnly,
  notRestorable,
}

extension RestoreCapabilityX on RestoreCapability {
  bool get hasRecoverableBytes =>
      this != RestoreCapability.metadataOnly &&
      this != RestoreCapability.notRestorable;

  bool get isFullQuality =>
      this == RestoreCapability.originalFullQuality ||
      this == RestoreCapability.protectedOriginal ||
      this == RestoreCapability.alternateFullQualityCopy;
}
