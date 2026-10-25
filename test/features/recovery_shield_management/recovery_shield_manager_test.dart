import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery_shield_management/recovery_shield_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps full native protected-copy metadata for restore', () async {
    const channel = MethodChannel('test/recovery_shield_management');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getShieldItems');
      return [
        {
          'protectionId': 'protected-1',
          'displayName': 'photo.jpg',
          'mimeType': 'image/jpeg',
          'byteSize': 4096,
          'width': 800,
          'height': 600,
          'originalSource': 'cameraGallery',
          'originalContentUri': 'content://media/external/images/media/7',
          'originalLocation': 'DCIM/Camera/',
          'createdAtMillis': 1700000000000,
          'modifiedAtMillis': 1700000001000,
          'takenAtMillis': 1700000002000,
          'protectedCopyLocation': '/private/recovery_shield/item.bin',
          'sha256Digest': List.filled(64, 'b').join(),
          'protectedAtMillis': 1700000003000,
          'integrityVerified': true,
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final snapshot = await PlatformRecoveryShieldManager(
      channel: channel,
    ).load();

    expect(snapshot.items, hasLength(1));
    final item = snapshot.items.single;
    expect(item.integrityVerified, isTrue);
    final record = item.record!;
    expect(record.protectionId, 'protected-1');
    expect(record.originalSource, MediaSource.cameraGallery);
    expect(
      record.originalContentUri,
      Uri.parse('content://media/external/images/media/7'),
    );
    expect(record.protectedCopyLocation, '/private/recovery_shield/item.bin');
    expect(record.sha256Digest, List.filled(64, 'b').join());
    expect(record.byteSize, 4096);
    expect(record.width, 800);
    expect(record.height, 600);
    expect(record.takenAt, DateTime.fromMillisecondsSinceEpoch(1700000002000));
  });

  test('leaves malformed restore metadata unavailable', () async {
    const channel = MethodChannel('test/recovery_shield_management/malformed');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => [
      {
        'protectionId': 'bad-record',
        'byteSize': 10,
        'integrityVerified': true,
        'originalSource': 'not-a-source',
        'protectedCopyLocation': '/private/copy.bin',
        'sha256Digest': 'not-a-digest',
        'protectedAtMillis': 1700000000000,
      },
    ]);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final item = (await PlatformRecoveryShieldManager(channel: channel).load())
        .items
        .single;
    expect(item.record, isNull);
    expect(item.integrityVerified, isTrue);
  });
}
