import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/platform_current_media_inventory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts larger bounded pages for current-media scan setup', () async {
    const channel = MethodChannel('test/current_media_inventory');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var requestedPageSize = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      requestedPageSize =
          (call.arguments as Map<Object?, Object?>)['pageSize']! as int;
      return {
        'status': 'success',
        'items': <Object?>[],
        'nextContinuationToken': null,
        'nextAfterMediaStoreId': null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final inventory = PlatformCurrentMediaInventory(channel: channel);
    final result = await inventory.getCurrentMediaPage(
      const CurrentMediaPageRequest(pageSize: 500),
    );

    expect(requestedPageSize, 500);
    expect(result, isA<CurrentMediaInventorySuccess>());
  });

  group('CurrentMediaInventoryPlatformMapper', () {
    test('maps current media records without recovery classification', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'success',
        'items': [
          {
            'mediaStoreId': 42,
            'contentUri': 'content://media/external/images/media/42',
            'displayName': 'photo.jpg',
            'mimeType': 'image/jpeg',
          },
        ],
        'nextAfterMediaStoreId': null,
      });

      final success = result as CurrentMediaInventorySuccess;
      expect(success.page.items.single.mediaStoreId, 42);
      expect(success.page.items.single.displayName, 'photo.jpg');
    });

    test('maps batch metadata returned with an inventory row', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'success',
        'items': [
          {
            'mediaStoreId': 42,
            'byteSize': 2048,
            'width': 1080,
            'height': 1920,
            'dateTaken': 1700000000000,
            'dateAdded': 1700000001000,
            'dateModified': 1700000002000,
            'relativePath': 'DCIM/Camera/',
            'bucketName': 'Camera',
            'orientationDegrees': 90,
          },
        ],
      });

      final item = (result as CurrentMediaInventorySuccess).page.items.single;
      expect(item.byteSize, 2048);
      expect(item.width, 1080);
      expect(item.height, 1920);
      expect(item.relativePath, 'DCIM/Camera/');
      expect(item.dateTaken, isNotNull);
    });

    test('maps an empty inventory page', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'success',
        'items': <Object?>[],
        'nextAfterMediaStoreId': null,
      });

      final success = result as CurrentMediaInventorySuccess;
      expect(success.page.items, isEmpty);
      expect(success.page.mayHaveMore, isFalse);
    });

    test('preserves continuation state for bounded pages', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'success',
        'items': [
          {'mediaStoreId': 10},
          {'mediaStoreId': 11},
        ],
        'nextAfterMediaStoreId': 11,
      });

      final success = result as CurrentMediaInventorySuccess;
      expect(success.page.mayHaveMore, isTrue);
      expect(success.page.nextAfterMediaStoreId, 11);
    });

    test('maps permission failures safely', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'failure',
        'code': 'securityDenied',
        'message': 'Media access is unavailable.',
      });

      final failure = result as CurrentMediaInventoryFailureResult;
      expect(
        failure.failure.code,
        CurrentMediaInventoryFailureCode.securityDenied,
      );
    });

    test('ignores malformed optional platform metadata', () {
      final result = CurrentMediaInventoryPlatformMapper.fromResponse({
        'status': 'success',
        'items': [
          {
            'mediaStoreId': 7,
            'contentUri': 99,
            'displayName': ['not', 'a', 'name'],
            'mimeType': false,
          },
        ],
        'nextAfterMediaStoreId': null,
      });

      final record = (result as CurrentMediaInventorySuccess).page.items.single;
      expect(record.contentUri, isNull);
      expect(record.displayName, isNull);
      expect(record.mimeType, isNull);
    });

    test('an absent inventory record is not deletion evidence', () {
      const page = CurrentMediaPage.empty();

      expect(page.items.where((item) => item.mediaStoreId == 999), isEmpty);
    });
  });

  test('preserves multi-volume identity and opaque continuation', () {
    final result = CurrentMediaInventoryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [
        {
          'mediaStoreId': 7,
          'contentUri': 'content://media/external_primary/images/media/7',
          'storageVolumeName': 'external_primary',
        },
        {
          'mediaStoreId': 7,
          'contentUri': 'content://media/1234-5678/images/media/7',
          'storageVolumeName': '1234-5678',
        },
      ],
      'nextContinuationToken': 'mv1:1:7',
      'scannedVolumeName': 'external_primary',
    });

    final page = (result as CurrentMediaInventorySuccess).page;
    expect(page.items.map((item) => item.storageVolumeName).toSet(), {
      'external_primary',
      '1234-5678',
    });
    expect(page.nextContinuationToken, 'mv1:1:7');
    expect(page.scannedVolumeName, 'external_primary');
    expect(page.mayHaveMore, isTrue);
  });
}
