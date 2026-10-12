import 'package:flutter/services.dart';

import '../recovery/application/scan_runtime/recovery_image_memory_policy.dart';

enum ThumbnailFailure { missing, accessDenied, platformFailure }

class ThumbnailResult {
  const ThumbnailResult._({this.bytes, this.failure});
  const ThumbnailResult.success(Uint8List value) : this._(bytes: value);
  const ThumbnailResult.failed(ThumbnailFailure value) : this._(failure: value);
  final Uint8List? bytes;
  final ThumbnailFailure? failure;
}

abstract interface class BoundedThumbnailProvider {
  Future<ThumbnailResult> load(
    Uri contentUri, {
    required int width,
    required int height,
  });

  Future<ThumbnailResult> loadFile(
    String filePath, {
    required int width,
    required int height,
  }) async => const ThumbnailResult.failed(ThumbnailFailure.missing);
}

class PlatformBoundedThumbnailProvider implements BoundedThumbnailProvider {
  PlatformBoundedThumbnailProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);
  static const _channelName =
      'com.photorecoveryrestore.app/bounded_thumbnail';
  final MethodChannel _channel;

  @override
  Future<ThumbnailResult> load(
    Uri contentUri, {
    required int width,
    required int height,
  }) async {
    final boundedWidth = width.clamp(
      1,
      RecoveryImageMemoryPolicy.maximumThumbnailDimension,
    );
    final boundedHeight = height.clamp(
      1,
      RecoveryImageMemoryPolicy.maximumThumbnailDimension,
    );
    try {
      final response = await _channel.invokeMethod<Object?>('loadThumbnail', {
        'contentUri': contentUri.toString(),
        'width': boundedWidth,
        'height': boundedHeight,
      });
      if (response is! Map<Object?, Object?>) {
        return const ThumbnailResult.failed(ThumbnailFailure.platformFailure);
      }
      final bytes = response['bytes'];
      if (response['status'] == 'success' && bytes is Uint8List) {
        return ThumbnailResult.success(bytes);
      }
      return ThumbnailResult.failed(switch (response['code']) {
        'missing' => ThumbnailFailure.missing,
        'accessDenied' => ThumbnailFailure.accessDenied,
        _ => ThumbnailFailure.platformFailure,
      });
    } on PlatformException {
      return const ThumbnailResult.failed(ThumbnailFailure.platformFailure);
    }
  }

  @override
  Future<ThumbnailResult> loadFile(
    String filePath, {
    required int width,
    required int height,
  }) => _load({
    'filePath': filePath,
    'width': width,
    'height': height,
  });

  Future<ThumbnailResult> _load(Map<String, Object?> arguments) async {
    final boundedWidth = (arguments['width']! as int).clamp(
      1,
      RecoveryImageMemoryPolicy.maximumThumbnailDimension,
    );
    final boundedHeight = (arguments['height']! as int).clamp(
      1,
      RecoveryImageMemoryPolicy.maximumThumbnailDimension,
    );
    try {
      final response = await _channel.invokeMethod<Object?>('loadThumbnail', {
        ...arguments,
        'width': boundedWidth,
        'height': boundedHeight,
      });
      if (response is! Map<Object?, Object?>) {
        return const ThumbnailResult.failed(ThumbnailFailure.platformFailure);
      }
      final bytes = response['bytes'];
      if (response['status'] == 'success' && bytes is Uint8List) {
        return ThumbnailResult.success(bytes);
      }
      return ThumbnailResult.failed(switch (response['code']) {
        'missing' => ThumbnailFailure.missing,
        'accessDenied' => ThumbnailFailure.accessDenied,
        _ => ThumbnailFailure.platformFailure,
      });
    } on PlatformException {
      return const ThumbnailResult.failed(ThumbnailFailure.platformFailure);
    }
  }
}
