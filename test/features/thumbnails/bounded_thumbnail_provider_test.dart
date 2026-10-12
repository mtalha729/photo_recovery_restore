import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/thumbnails/bounded_thumbnail_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/thumbnail');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('dimensions are clamped to 512 and bytes are returned', () async {
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          arguments = call.arguments as Map<Object?, Object?>;
          return {
            'status': 'success',
            'bytes': Uint8List.fromList([1, 2]),
          };
        });
    final result = await PlatformBoundedThumbnailProvider(channel: channel)
        .load(Uri.parse('content://media/1'), width: 4000, height: 3000);
    expect(arguments!['width'], 512);
    expect(arguments!['height'], 512);
    expect(result.bytes, isNotNull);
  });

  test('stale URI fails safely without original-byte fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'failure', 'code': 'missing'},
        );
    final result = await PlatformBoundedThumbnailProvider(channel: channel)
        .load(Uri.parse('content://media/stale'), width: 256, height: 256);
    expect(result.failure, ThumbnailFailure.missing);
    expect(result.bytes, isNull);
  });
}
