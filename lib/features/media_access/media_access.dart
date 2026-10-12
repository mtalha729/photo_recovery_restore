import 'package:flutter/services.dart';

enum MediaAccessStatus {
  fullAccess,
  limitedSelectedAccess,
  denied,
  settingsRequired,
  notRequired,
  unsupported,
  unknown,
}

enum MediaAccessRequestIntent { initial, changeSelectedPhotos, fullAccess }

class MediaAccessState {
  const MediaAccessState({required this.status, required this.androidApiLevel});
  final MediaAccessStatus status;
  final int androidApiLevel;

  bool get canReadImages =>
      status == MediaAccessStatus.fullAccess ||
      status == MediaAccessStatus.limitedSelectedAccess ||
      status == MediaAccessStatus.notRequired;
  bool get isLimited => status == MediaAccessStatus.limitedSelectedAccess;
}

abstract interface class MediaAccessCoordinator {
  Future<MediaAccessState> getState();
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  });
  Future<void> openSettings();
}

class PlatformMediaAccessCoordinator implements MediaAccessCoordinator {
  PlatformMediaAccessCoordinator({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/media_access';
  final MethodChannel _channel;

  @override
  Future<MediaAccessState> getState() => _invoke('getMediaAccessState');

  @override
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  }) => _invoke('requestMediaAccess', arguments: {'intent': intent.name});

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      return;
    }
  }

  Future<MediaAccessState> _invoke(
    String method, {
    Object? arguments,
  }) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      return MediaAccessMapper.fromResponse(response);
    } on PlatformException {
      return const MediaAccessState(
        status: MediaAccessStatus.unknown,
        androidApiLevel: 0,
      );
    } on MissingPluginException {
      return const MediaAccessState(
        status: MediaAccessStatus.unsupported,
        androidApiLevel: 0,
      );
    }
  }
}

abstract final class MediaAccessMapper {
  static MediaAccessState fromResponse(Object? response) {
    if (response is! Map<Object?, Object?> || response['apiLevel'] is! int) {
      return const MediaAccessState(
        status: MediaAccessStatus.unknown,
        androidApiLevel: 0,
      );
    }
    final status = switch (response['status']) {
      'fullAccess' => MediaAccessStatus.fullAccess,
      'limitedSelectedAccess' => MediaAccessStatus.limitedSelectedAccess,
      'denied' => MediaAccessStatus.denied,
      'settingsRequired' => MediaAccessStatus.settingsRequired,
      'notRequired' => MediaAccessStatus.notRequired,
      'unsupported' => MediaAccessStatus.unsupported,
      _ => MediaAccessStatus.unknown,
    };
    return MediaAccessState(
      status: status,
      androidApiLevel: response['apiLevel']! as int,
    );
  }
}
