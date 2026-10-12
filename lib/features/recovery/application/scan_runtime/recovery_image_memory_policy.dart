class RecoveryImageMemoryPolicy {
  const RecoveryImageMemoryPolicy._();

  static const int maximumThumbnailDimension = 512;

  static bool isSizeAppropriateThumbnailRequest({
    required int width,
    required int height,
  }) =>
      width > 0 &&
      height > 0 &&
      width <= maximumThumbnailDimension &&
      height <= maximumThumbnailDimension;
}
