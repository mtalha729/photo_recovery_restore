import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/authorized_folder_media_discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancellation asks the native provider to close its live cursor', () async {
    const channel = MethodChannel('test/folder-scope');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    try {
      await const PlatformAuthorizedFolderMediaDiscovery.withChannel(channel)
          .cancelScan(continuationToken: 'session:2');
      expect(calls.single.method, 'cancelAuthorizedFolderScan');
      expect(calls.single.arguments, {'continuationToken': 'session:2'});
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

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
      'unavailableDirectories': 1,
      'providerExhausted': false,
      'completionReason': 'pageBoundary',
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
    expect(page.unavailableDirectories, 1);
    expect(page.unsupportedFiles, 2);
    expect(page.providerExhausted, isFalse);
    expect(page.completionReason, 'pageBoundary');
    expect(page.mayHaveMore, isTrue);
  });

  test('partial native completion metadata is preserved', () {
    final result = PlatformAuthorizedFolderMediaDiscovery.mapResponse({
      'status': 'success',
      'items': const [],
      'nextContinuationToken': null,
      'providerExhausted': true,
      'completionReason': 'resourceLimit',
      'unavailableDirectories': 2,
    });

    final page = (result as AuthorizedFolderMediaSuccess).page;
    expect(page.providerExhausted, isTrue);
    expect(page.completionReason, 'resourceLimit');
    expect(page.unavailableDirectories, 2);
    expect(page.mayHaveMore, isFalse);
  });

  test('cancelled platform failures remain distinguishable', () {
    final result = PlatformAuthorizedFolderMediaDiscovery.mapResponse({
      'status': 'failure',
      'code': 'cancelled',
      'message': 'Cancelled.',
    });

    expect(
      (result as AuthorizedFolderMediaFailure).code,
      AuthorizedFolderMediaFailureCode.cancelled,
    );
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
