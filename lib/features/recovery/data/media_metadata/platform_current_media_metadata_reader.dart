import 'package:flutter/services.dart';

import 'current_media_metadata.dart';
import 'current_media_metadata_reader.dart';

class PlatformCurrentMediaMetadataReader implements CurrentMediaMetadataReader {
  PlatformCurrentMediaMetadataReader({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/current_media_metadata';

  final MethodChannel _channel;

  @override
  Future<CurrentMediaMetadataResult> getCurrentMediaMetadata(
    int mediaStoreId, {
    Uri? contentUri,
    String? storageVolumeName,
  }) async {
    if (mediaStoreId < 0) {
      throw ArgumentError.value(
        mediaStoreId,
        'mediaStoreId',
        'must be non-negative',
      );
    }

    try {
      final response = await _channel.invokeMethod<Object?>(
        'getCurrentMediaMetadata',
        {
          'mediaStoreId': mediaStoreId,
          'contentUri': contentUri?.toString(),
          'storageVolumeName': storageVolumeName,
        },
      );
      return CurrentMediaMetadataPlatformMapper.fromResponse(response);
    } on PlatformException catch (error) {
      return CurrentMediaMetadataFailureResult(
        CurrentMediaMetadataFailure(
          code: CurrentMediaMetadataFailureCode.platformFailure,
          message: error.message,
        ),
      );
    } on MissingPluginException {
      return const CurrentMediaMetadataFailureResult(
        CurrentMediaMetadataFailure(
          code: CurrentMediaMetadataFailureCode.mediaAccessUnavailable,
        ),
      );
    }
  }
}

class CurrentMediaMetadataPlatformMapper {
  const CurrentMediaMetadataPlatformMapper._();

  static CurrentMediaMetadataResult fromResponse(Object? response) {
    if (response is! Map<Object?, Object?>) {
      return _malformedResponse();
    }
    if (response['status'] == 'failure') {
      return CurrentMediaMetadataFailureResult(
        CurrentMediaMetadataFailure(
          code: _failureCode(response['code']),
          message: _stringOrNull(response['message']),
        ),
      );
    }
    if (response['status'] != 'success' ||
        response['metadata'] is! Map<Object?, Object?>) {
      return _malformedResponse();
    }

    final metadata = response['metadata']! as Map<Object?, Object?>;
    final mediaStoreId = metadata['mediaStoreId'];
    if (mediaStoreId is! int || mediaStoreId < 0) {
      return _malformedResponse();
    }

    return CurrentMediaMetadataSuccess(
      CurrentMediaMetadata(
        mediaStoreId: mediaStoreId,
        contentUri: _uriOrNull(metadata['contentUri']),
        displayName: _nonBlankStringOrNull(metadata['displayName']),
        mimeType: _nonBlankStringOrNull(metadata['mimeType']),
        byteSize: _nonNegativeIntOrNull(metadata['byteSize']),
        width: _positiveIntOrNull(metadata['width']),
        height: _positiveIntOrNull(metadata['height']),
        dateTaken: _millisecondsTimestampOrNull(metadata['dateTakenMillis']),
        dateAdded: _secondsTimestampOrNull(metadata['dateAddedSeconds']),
        dateModified: _secondsTimestampOrNull(metadata['dateModifiedSeconds']),
        relativePath: _nonBlankStringOrNull(metadata['relativePath']),
        bucketName: _nonBlankStringOrNull(metadata['bucketName']),
        orientationDegrees: _orientationOrNull(metadata['orientationDegrees']),
        storageVolumeName: _nonBlankStringOrNull(metadata['storageVolumeName']),
        isRemovableStorage: metadata['isRemovableStorage'] is bool
            ? metadata['isRemovableStorage']! as bool
            : null,
      ),
    );
  }

  static String? _stringOrNull(Object? value) => value is String ? value : null;

  static String? _nonBlankStringOrNull(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static Uri? _uriOrNull(Object? value) {
    final uri = _nonBlankStringOrNull(value);
    return uri == null ? null : Uri.tryParse(uri);
  }

  static int? _nonNegativeIntOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }

  static int? _positiveIntOrNull(Object? value) {
    return value is int && value > 0 ? value : null;
  }

  static int? _orientationOrNull(Object? value) {
    const validOrientations = {0, 90, 180, 270};
    return value is int && validOrientations.contains(value) ? value : null;
  }

  static DateTime? _millisecondsTimestampOrNull(Object? value) {
    return value is int && value > 0
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
        : null;
  }

  static DateTime? _secondsTimestampOrNull(Object? value) {
    return value is int && value > 0
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        : null;
  }

  static CurrentMediaMetadataFailureCode _failureCode(Object? value) {
    return switch (value) {
      'mediaAccessUnavailable' =>
        CurrentMediaMetadataFailureCode.mediaAccessUnavailable,
      'securityDenied' => CurrentMediaMetadataFailureCode.securityDenied,
      'recordUnavailable' => CurrentMediaMetadataFailureCode.recordUnavailable,
      'platformFailure' => CurrentMediaMetadataFailureCode.platformFailure,
      _ => CurrentMediaMetadataFailureCode.malformedPlatformResponse,
    };
  }

  static CurrentMediaMetadataFailureResult _malformedResponse() {
    return const CurrentMediaMetadataFailureResult(
      CurrentMediaMetadataFailure(
        code: CurrentMediaMetadataFailureCode.malformedPlatformResponse,
      ),
    );
  }
}
