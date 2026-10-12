import 'package:flutter/services.dart';

import '../application/photo_cleanup_models.dart';

class PlatformPhotoCleanupDigestProvider implements PhotoCleanupDigestProvider {
  PlatformPhotoCleanupDigestProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/smart_cleanup_digest';
  final MethodChannel _channel;

  @override
  Future<String?> digest(CleanupPhoto photo) async {
    final uri = photo.record.contentUri;
    if (uri == null || uri.scheme != 'content') return null;
    try {
      final value = await _channel.invokeMethod<Object?>('sha256', {'contentUri': uri.toString()});
      return value is String && value.isNotEmpty ? value : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class PlatformPhotoCleanupDeletionExecutor implements PhotoCleanupDeletionExecutor {
  PlatformPhotoCleanupDeletionExecutor({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/smart_cleanup_delete';
  final MethodChannel _channel;

  @override
  Future<PhotoCleanupDeleteResult> deletePhotos(Iterable<CleanupPhoto> photos) async {
    final selected = photos
        .where((photo) => photo.record.contentUri?.scheme == 'content')
        .map((photo) => {'id': photo.id, 'contentUri': photo.record.contentUri.toString()})
        .toList(growable: false);
    if (selected.isEmpty) return const PhotoCleanupDeleteResult();
    try {
      final response = await _channel.invokeMethod<Object?>('deletePhotos', {'photos': selected});
      if (response is! Map<Object?, Object?>) return const PhotoCleanupDeleteResult();
      Set<String> ids(String key) => (response[key] as List<Object?>? ?? const [])
          .whereType<String>().toSet();
      return PhotoCleanupDeleteResult(
        deletedIds: ids('deletedIds'),
        unavailableIds: ids('unavailableIds'),
        cancelled: response['cancelled'] == true,
      );
    } on PlatformException {
      return PhotoCleanupDeleteResult(unavailableIds: selected.map((row) => row['id']!).toSet());
    } on MissingPluginException {
      return PhotoCleanupDeleteResult(unavailableIds: selected.map((row) => row['id']!).toSet());
    }
  }
}
