class CurrentMediaMetadata {
  const CurrentMediaMetadata({
    required this.mediaStoreId,
    this.contentUri,
    this.displayName,
    this.mimeType,
    this.byteSize,
    this.width,
    this.height,
    this.dateTaken,
    this.dateAdded,
    this.dateModified,
    this.relativePath,
    this.bucketName,
    this.orientationDegrees,
    this.storageVolumeName,
    this.isRemovableStorage,
  });

  final int mediaStoreId;
  final Uri? contentUri;
  final String? displayName;
  final String? mimeType;
  final int? byteSize;
  final int? width;
  final int? height;
  final DateTime? dateTaken;
  final DateTime? dateAdded;
  final DateTime? dateModified;
  final String? relativePath;
  final String? bucketName;
  final int? orientationDegrees;
  final String? storageVolumeName;
  final bool? isRemovableStorage;
}

enum CurrentMediaMetadataFailureCode {
  mediaAccessUnavailable,
  securityDenied,
  recordUnavailable,
  platformFailure,
  malformedPlatformResponse,
}

class CurrentMediaMetadataFailure {
  const CurrentMediaMetadataFailure({required this.code, this.message});

  final CurrentMediaMetadataFailureCode code;
  final String? message;
}

sealed class CurrentMediaMetadataResult {
  const CurrentMediaMetadataResult();
}

class CurrentMediaMetadataSuccess extends CurrentMediaMetadataResult {
  const CurrentMediaMetadataSuccess(this.metadata);

  final CurrentMediaMetadata metadata;
}

class CurrentMediaMetadataFailureResult extends CurrentMediaMetadataResult {
  const CurrentMediaMetadataFailureResult(this.failure);

  final CurrentMediaMetadataFailure failure;
}
