import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/current_media_metadata.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/platform_current_media_metadata_reader.dart';

void main() {
  CurrentMediaMetadataSuccess mapSuccess(Map<Object?, Object?> metadata) {
    final result = CurrentMediaMetadataPlatformMapper.fromResponse({
      'status': 'success',
      'metadata': metadata,
    });
    return result as CurrentMediaMetadataSuccess;
  }

  test('maps complete current media metadata', () {
    final metadata = mapSuccess({
      'mediaStoreId': 42,
      'contentUri': 'content://media/external/images/media/42',
      'displayName': 'photo.jpg',
      'mimeType': 'image/jpeg',
      'byteSize': 0,
      'width': 4032,
      'height': 3024,
      'dateTakenMillis': 1704067200000,
      'dateAddedSeconds': 1704067200,
      'dateModifiedSeconds': 1704153600,
      'relativePath': 'DCIM/Camera/',
      'bucketName': 'Camera',
      'orientationDegrees': 90,
      'storageVolumeName': 'external_primary',
    }).metadata;

    expect(metadata.mediaStoreId, 42);
    expect(metadata.byteSize, 0);
    expect(metadata.width, 4032);
    expect(metadata.dateTaken, DateTime.utc(2024));
    expect(metadata.dateAdded, DateTime.utc(2024));
    expect(metadata.relativePath, 'DCIM/Camera/');
    expect(metadata.orientationDegrees, 90);
  });

  test('keeps missing optional metadata unknown', () {
    final metadata = mapSuccess({'mediaStoreId': 1}).metadata;

    expect(metadata.contentUri, isNull);
    expect(metadata.byteSize, isNull);
    expect(metadata.width, isNull);
    expect(metadata.relativePath, isNull);
    expect(metadata.storageVolumeName, isNull);
  });

  test('normalizes malformed optional platform metadata safely', () {
    final metadata = mapSuccess({
      'mediaStoreId': 2,
      'displayName': '   ',
      'byteSize': -1,
      'width': 0,
      'height': 'large',
      'dateTakenMillis': 'unknown',
      'orientationDegrees': 45,
    }).metadata;

    expect(metadata.displayName, isNull);
    expect(metadata.byteSize, isNull);
    expect(metadata.width, isNull);
    expect(metadata.height, isNull);
    expect(metadata.dateTaken, isNull);
    expect(metadata.orientationDegrees, isNull);
  });

  test('normalizes MediaStore timestamp units consistently', () {
    final metadata = mapSuccess({
      'mediaStoreId': 3,
      'dateTakenMillis': 1000,
      'dateAddedSeconds': 1,
      'dateModifiedSeconds': 2,
    }).metadata;

    expect(
      metadata.dateTaken,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(
      metadata.dateAdded,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(
      metadata.dateModified,
      DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );
  });

  test('preserves current media identity without deletion inference', () {
    final metadata = mapSuccess({'mediaStoreId': 99}).metadata;

    expect(metadata.mediaStoreId, 99);
    expect(metadata, isA<CurrentMediaMetadata>());
  });

  test('maps unavailable older Android fields as unknown', () {
    final metadata = mapSuccess({
      'mediaStoreId': 4,
      'relativePath': null,
      'storageVolumeName': null,
      'bucketName': '  ',
    }).metadata;

    expect(metadata.relativePath, isNull);
    expect(metadata.storageVolumeName, isNull);
    expect(metadata.bucketName, isNull);
  });

  test('maps access failures safely', () {
    final result = CurrentMediaMetadataPlatformMapper.fromResponse({
      'status': 'failure',
      'code': 'securityDenied',
    });

    expect(
      (result as CurrentMediaMetadataFailureResult).failure.code,
      CurrentMediaMetadataFailureCode.securityDenied,
    );
  });
}
