import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/media_access/media_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps API 33 full image access without video permission', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('test/media-access');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {'status': 'fullAccess', 'apiLevel': 33};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final state = await PlatformMediaAccessCoordinator(channel: channel)
        .getState();
    expect(state.status, MediaAccessStatus.fullAccess);
    expect(calls.single.arguments, isNull);
    expect(calls.single.toString(), isNot(contains('VIDEO')));
  });

  test('maps Android 14 full and limited selected access distinctly', () {
    expect(
      MediaAccessMapper.fromResponse({'status': 'fullAccess', 'apiLevel': 34})
          .isLimited,
      isFalse,
    );
    final limited = MediaAccessMapper.fromResponse({
      'status': 'limitedSelectedAccess',
      'apiLevel': 34,
    });
    expect(limited.canReadImages, isTrue);
    expect(limited.isLimited, isTrue);
  });

  test('sends the explicit Android 14 access-upgrade intent', () async {
    MethodCall? capturedCall;
    const channel = MethodChannel('test/media-access-intent');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return {'status': 'limitedSelectedAccess', 'apiLevel': 34};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await PlatformMediaAccessCoordinator(channel: channel).requestAccess(
      intent: MediaAccessRequestIntent.fullAccess,
    );

    expect(capturedCall?.method, 'requestMediaAccess');
    expect(capturedCall?.arguments, {'intent': 'fullAccess'});
    expect(capturedCall.toString(), isNot(contains('VIDEO')));
  });

  test(
    'legacy, denied, settings-required, and unknown states are deterministic',
    () {
      expect(
        MediaAccessMapper.fromResponse({'status': 'fullAccess', 'apiLevel': 28})
            .canReadImages,
        isTrue,
      );
      expect(
        MediaAccessMapper.fromResponse({'status': 'denied', 'apiLevel': 32})
            .canReadImages,
        isFalse,
      );
      expect(
        MediaAccessMapper.fromResponse({
          'status': 'settingsRequired',
          'apiLevel': 33,
        }).status,
        MediaAccessStatus.settingsRequired,
      );
      expect(
        MediaAccessMapper.fromResponse(null).status,
        MediaAccessStatus.unknown,
      );
    },
  );
}
