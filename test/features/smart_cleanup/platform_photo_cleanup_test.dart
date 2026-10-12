import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/smart_cleanup/application/photo_cleanup_models.dart';
import 'package:photo_recovery_restore/features/smart_cleanup/data/platform_photo_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform digest provider requests an exact content URI only', () async {
    const channel = MethodChannel('test/smart_cleanup_digest');
    final calls = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments);
      return 'a' * 64;
    });
    final provider = PlatformPhotoCleanupDigestProvider(channel: channel);
    final photo = CleanupPhoto(
      id: 'external:1',
      record: CurrentMediaRecord(mediaStoreId: 1, contentUri: Uri.parse('content://media/1')),
    );
    expect(await provider.digest(photo), 'a' * 64);
    expect(calls.single, {'contentUri': 'content://media/1'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('platform delete executor preserves exact deleted and cancelled results', () async {
    const channel = MethodChannel('test/smart_cleanup_delete');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
              'deletedIds': ['external:1'],
              'unavailableIds': ['external:2'],
              'cancelled': true,
            });
    final executor = PlatformPhotoCleanupDeletionExecutor(channel: channel);
    final photo = CleanupPhoto(
      id: 'external:1',
      record: CurrentMediaRecord(mediaStoreId: 1, contentUri: Uri.parse('content://media/1')),
    );
    final result = await executor.deletePhotos([photo]);
    expect(result.deletedIds, {'external:1'});
    expect(result.unavailableIds, {'external:2'});
    expect(result.cancelled, isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
