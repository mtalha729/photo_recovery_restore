import 'package:flutter/services.dart';

abstract interface class OnboardingCompletionStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

class PlatformOnboardingCompletionStore implements OnboardingCompletionStore {
  PlatformOnboardingCompletionStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/onboarding';
  final MethodChannel _channel;

  @override
  Future<bool> isComplete() async {
    try {
      return await _channel.invokeMethod<bool>('isOnboardingComplete') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> markComplete() async {
    try {
      await _channel.invokeMethod<void>('markOnboardingComplete');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
