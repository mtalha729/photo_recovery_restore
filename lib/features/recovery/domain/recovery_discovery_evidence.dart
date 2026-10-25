class RecoveryDiscoveryEvidence {
  const RecoveryDiscoveryEvidence({
    this.canonicalPath,
    this.detectedFormat,
    this.isTrashLike = false,
    this.isThumbnailLike = false,
    this.isCacheLike = false,
    this.isRecoveryCopyLike = false,
    this.isHidden = false,
    this.isExtensionMismatch = false,
    this.isUnindexed = false,
    this.isEmbeddedPayload = false,
    this.isRecoveryShieldBackup = false,
    this.embeddedOffset,
    this.containerPath,
  });

  final String? canonicalPath;
  final String? detectedFormat;
  final bool isTrashLike;
  final bool isThumbnailLike;
  final bool isCacheLike;
  final bool isRecoveryCopyLike;
  final bool isHidden;
  final bool isExtensionMismatch;
  final bool isUnindexed;
  final bool isEmbeddedPayload;
  final bool isRecoveryShieldBackup;
  final int? embeddedOffset;
  final String? containerPath;
}
