import 'current_media_metadata.dart';

abstract interface class CurrentMediaMetadataReader {
  Future<CurrentMediaMetadataResult> getCurrentMediaMetadata(
    int mediaStoreId, {
    Uri? contentUri,
    String? storageVolumeName,
  });
}
