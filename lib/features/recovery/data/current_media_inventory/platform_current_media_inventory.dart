import 'package:flutter/services.dart';

import 'current_media_inventory.dart';
import 'current_media_inventory_models.dart';

class PlatformCurrentMediaInventory implements CurrentMediaInventory {
  PlatformCurrentMediaInventory({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/current_media_inventory';
  static const _maximumPageSize = 500;

  final MethodChannel _channel;

  @override
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  ) async {
    if (request.pageSize > _maximumPageSize) {
      throw ArgumentError.value(
        request.pageSize,
        'pageSize',
        'must not exceed $_maximumPageSize',
      );
    }

    try {
      final response = await _channel.invokeMethod<Object?>(
        'getCurrentMediaPage',
        {
          'pageSize': request.pageSize,
          'afterMediaStoreId': request.afterMediaStoreId,
          'continuationToken': request.continuationToken,
        },
      );
      return CurrentMediaInventoryPlatformMapper.fromResponse(response);
    } on PlatformException catch (error) {
      return CurrentMediaInventoryFailureResult(
        CurrentMediaInventoryFailure(
          code: CurrentMediaInventoryFailureCode.platformFailure,
          message: error.message,
        ),
      );
    } on MissingPluginException {
      return const CurrentMediaInventoryFailureResult(
        CurrentMediaInventoryFailure(
          code: CurrentMediaInventoryFailureCode.mediaAccessUnavailable,
        ),
      );
    }
  }
}

class CurrentMediaInventoryPlatformMapper {
  const CurrentMediaInventoryPlatformMapper._();

  static CurrentMediaInventoryResult fromResponse(Object? response) {
    if (response is! Map<Object?, Object?>) {
      return _malformedResponse();
    }

    final status = response['status'];
    if (status == 'failure') {
      return CurrentMediaInventoryFailureResult(
        CurrentMediaInventoryFailure(
          code: _failureCode(response['code']),
          message: response['message'] as String?,
        ),
      );
    }
    if (status != 'success' || response['items'] is! List<Object?>) {
      return _malformedResponse();
    }

    final records = <CurrentMediaRecord>[];
    for (final item in response['items']! as List<Object?>) {
      final record = _recordFromMap(item);
      if (record == null) {
        return _malformedResponse();
      }
      records.add(record);
    }

    final nextAfterMediaStoreId = response['nextAfterMediaStoreId'];
    if (nextAfterMediaStoreId != null && nextAfterMediaStoreId is! int) {
      return _malformedResponse();
    }

    final nextContinuationToken = response['nextContinuationToken'];
    if (nextContinuationToken != null && nextContinuationToken is! String) {
      return _malformedResponse();
    }
    final scannedVolumeName = response['scannedVolumeName'];
    if (scannedVolumeName != null && scannedVolumeName is! String) {
      return _malformedResponse();
    }

    return CurrentMediaInventorySuccess(
      CurrentMediaPage(
        items: List.unmodifiable(records),
        nextAfterMediaStoreId: nextAfterMediaStoreId as int?,
        nextContinuationToken: nextContinuationToken as String?,
        scannedVolumeName: scannedVolumeName as String?,
      ),
    );
  }

  static CurrentMediaRecord? _recordFromMap(Object? value) {
    if (value is! Map<Object?, Object?> || value['mediaStoreId'] is! int) {
      return null;
    }

    final contentUri = value['contentUri'];
    final displayName = value['displayName'];
    final mimeType = value['mimeType'];
    final storageVolumeName = value['storageVolumeName'];
    return CurrentMediaRecord(
      mediaStoreId: value['mediaStoreId']! as int,
      contentUri: contentUri is String ? Uri.tryParse(contentUri) : null,
      displayName: displayName is String ? displayName : null,
      mimeType: mimeType is String ? mimeType : null,
      storageVolumeName: storageVolumeName is String ? storageVolumeName : null,
      byteSize: _nullableInt(value['byteSize']),
      width: _nullableInt(value['width']),
      height: _nullableInt(value['height']),
      dateTaken: _nullableTimestamp(value['dateTaken']),
      dateAdded: _nullableTimestamp(value['dateAdded']),
      dateModified: _nullableTimestamp(value['dateModified']),
      relativePath: _nullableText(value['relativePath']),
      bucketName: _nullableText(value['bucketName']),
      orientationDegrees: _nullableInt(value['orientationDegrees']),
      recoveryArtifactFormat: _nullableText(value['recoveryArtifactFormat']),
      isThumbnailArtifact: value['isThumbnailArtifact'] == true,
      isCacheArtifact: value['isCacheArtifact'] == true,
    );
  }

  static int? _nullableInt(Object? value) =>
      value is int && value >= 0 ? value : null;

  static String? _nullableText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _nullableTimestamp(Object? value) {
    final millis = _nullableInt(value);
    return millis == null || millis == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static CurrentMediaInventoryFailureCode _failureCode(Object? value) {
    return switch (value) {
      'mediaAccessUnavailable' =>
        CurrentMediaInventoryFailureCode.mediaAccessUnavailable,
      'securityDenied' => CurrentMediaInventoryFailureCode.securityDenied,
      'platformFailure' => CurrentMediaInventoryFailureCode.platformFailure,
      _ => CurrentMediaInventoryFailureCode.malformedPlatformResponse,
    };
  }

  static CurrentMediaInventoryFailureResult _malformedResponse() {
    return const CurrentMediaInventoryFailureResult(
      CurrentMediaInventoryFailure(
        code: CurrentMediaInventoryFailureCode.malformedPlatformResponse,
      ),
    );
  }
}
