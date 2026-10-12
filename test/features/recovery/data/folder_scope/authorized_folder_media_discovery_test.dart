import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/authorized_folder_media_discovery.dart';

void main() {
  test('maps bounded SAF pages and opaque continuation', () {
    final result = PlatformAuthorizedFolderMediaDiscovery.mapResponse({
      'status': 'success',
      'items': [
        {
          'documentUri':
              'content://provider/document/primary%3APictures%2Fphoto.jpg',
          'displayName': 'photo.jpg',
          'mimeType': 'image/jpeg',
          'declaredMimeType': 'application/octet-stream',
          'detectedFormat': 'jpeg',
          'byteSize': 2048,
          'modifiedMillis': 1700000000000,
        },
      ],
      'nextContinuationToken': 'opaque-next-page',
      'filesExamined': 4,
      'entriesExamined': 7,
      'skippedNonImages': 3,
      'invalidFilesRejected': 2,
      'unavailableFiles': 1,
      'unsupportedFiles': 2,
    });

    final page = (result as AuthorizedFolderMediaSuccess).page;
    expect(page.items.single.documentUri.scheme, 'content');
    expect(page.items.single.byteSize, 2048);
    expect(page.items.single.detectedFormat, 'jpeg');
    expect(page.items.single.declaredMimeType, 'application/octet-stream');
    expect(page.filesExamined, 4);
    expect(page.entriesExamined, 7);
    expect(page.skippedNonImages, 3);
    expect(page.invalidFilesRejected, 2);
    expect(page.unavailableFiles, 1);
    expect(page.unsupportedFiles, 2);
    expect(page.mayHaveMore, isTrue);
  });

  test('private Android storage and raw file paths are rejected', () {
    for (final uri in [
      'file:///storage/emulated/0/Pictures/photo.jpg',
      'content://provider/document/primary%3AAndroid%2Fdata%2Fprivate.jpg',
      'content://provider/document/primary%3AAndroid%2Fobb%2Fprivate.jpg',
    ]) {
      final result = PlatformAuthorizedFolderMediaDiscovery.mapResponse({
        'status': 'success',
        'items': [
          {'documentUri': uri, 'mimeType': 'image/jpeg'},
        ],
      });
      expect(result, isA<AuthorizedFolderMediaFailure>());
    }
  });

  test('grant loss is structured and never interpreted as deletion', () {
    final result = PlatformAuthorizedFolderMediaDiscovery.mapResponse({
      'status': 'failure',
      'code': 'permissionGrantLost',
      'message': 'Grant lost.',
    });

    expect(
      (result as AuthorizedFolderMediaFailure).code,
      AuthorizedFolderMediaFailureCode.permissionGrantLost,
    );
  });
}
