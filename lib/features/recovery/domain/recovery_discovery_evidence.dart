class RecoveryDiscoveryEvidence {
  const RecoveryDiscoveryEvidence({
    this.canonicalPath,
    this.detectedFormat,
    this.isTrashLike = false,
    this.isThumbnailLike = false,
    this.isCacheLike = false,
    this.isHidden = false,
    this.isExtensionMismatch = false,
    this.isUnindexed = false,
    this.isEmbeddedPayload = false,
    this.embeddedOffset,
    this.containerPath,
  });

  final String? canonicalPath;
  final String? detectedFormat;
  final bool isTrashLike;
  final bool isThumbnailLike;
  final bool isCacheLike;
  final bool isHidden;
  final bool isExtensionMismatch;
  final bool isUnindexed;
  final bool isEmbeddedPayload;
  final int? embeddedOffset;
  final String? containerPath;
}
