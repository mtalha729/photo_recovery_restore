class CurrentMediaRecord {
  const CurrentMediaRecord({
    required this.mediaStoreId,
    this.contentUri,
    this.displayName,
    this.mimeType,
    this.storageVolumeName,
    this.byteSize,
    this.width,
    this.height,
    this.dateTaken,
    this.dateAdded,
    this.dateModified,
    this.relativePath,
    this.bucketName,
    this.orientationDegrees,
  });

  final int mediaStoreId;
  final Uri? contentUri;
  final String? displayName;
  final String? mimeType;
  final String? storageVolumeName;
  final int? byteSize;
  final int? width;
  final int? height;
  final DateTime? dateTaken;
  final DateTime? dateAdded;
  final DateTime? dateModified;
  final String? relativePath;
  final String? bucketName;
  final int? orientationDegrees;
}

class CurrentMediaPageRequest {
  const CurrentMediaPageRequest({
    required this.pageSize,
    this.afterMediaStoreId,
    this.continuationToken,
  }) : assert(pageSize > 0),
       assert(afterMediaStoreId == null || afterMediaStoreId >= 0);

  final int pageSize;
  final int? afterMediaStoreId;
  final String? continuationToken;
}

class CurrentMediaPage {
  const CurrentMediaPage({
    required this.items,
    this.nextAfterMediaStoreId,
    this.nextContinuationToken,
    this.scannedVolumeName,
  });

  const CurrentMediaPage.empty() : this(items: const []);

  final List<CurrentMediaRecord> items;
  final int? nextAfterMediaStoreId;
  final String? nextContinuationToken;
  final String? scannedVolumeName;

  bool get mayHaveMore =>
      nextContinuationToken != null || nextAfterMediaStoreId != null;
}

enum CurrentMediaInventoryFailureCode {
  mediaAccessUnavailable,
  securityDenied,
  platformFailure,
  malformedPlatformResponse,
}

class CurrentMediaInventoryFailure {
  const CurrentMediaInventoryFailure({required this.code, this.message});

  final CurrentMediaInventoryFailureCode code;
  final String? message;
}

sealed class CurrentMediaInventoryResult {
  const CurrentMediaInventoryResult();
}

class CurrentMediaInventorySuccess extends CurrentMediaInventoryResult {
  const CurrentMediaInventorySuccess(this.page);

  final CurrentMediaPage page;
}

class CurrentMediaInventoryFailureResult extends CurrentMediaInventoryResult {
  const CurrentMediaInventoryFailureResult(this.failure);

  final CurrentMediaInventoryFailure failure;
}
