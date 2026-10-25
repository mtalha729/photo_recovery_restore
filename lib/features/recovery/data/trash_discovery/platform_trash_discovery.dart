import 'package:flutter/services.dart';

import '../media_metadata/current_media_metadata.dart';
import '../media_metadata/platform_current_media_metadata_reader.dart';
import 'trash_discovery.dart';
import 'trash_discovery_models.dart';

class PlatformTrashDiscovery implements TrashDiscovery {
  PlatformTrashDiscovery({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/verified_trash_discovery';
  static const _maximumPageSize = 200;

  final MethodChannel _channel;

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
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
        'getVerifiedTrashPage',
        {
          'pageSize': request.pageSize,
          'afterMediaStoreId': request.afterMediaStoreId,
          'continuationToken': request.continuationToken,
        },
      );
      return TrashDiscoveryPlatformMapper.fromResponse(response);
    } on PlatformException catch (error) {
      return TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(
          code: TrashDiscoveryFailureCode.platformFailure,
          message: error.message,
        ),
      );
    } on MissingPluginException {
      return const TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(
          code: TrashDiscoveryFailureCode.mediaAccessUnavailable,
        ),
      );
    }
  }
}

class TrashDiscoveryPlatformMapper {
  const TrashDiscoveryPlatformMapper._();

  static TrashDiscoveryResult fromResponse(Object? response) {
    if (response is! Map<Object?, Object?>) return _malformedResponse();

    if (response['status'] == 'unsupported') {
      final apiLevel = response['androidApiLevel'];
      return TrashDiscoveryUnsupported(
        androidApiLevel: apiLevel is int ? apiLevel : null,
      );
    }
    if (response['status'] == 'failure') {
      return TrashDiscoveryFailureResult(
        TrashDiscoveryFailure(
          code: _failureCode(response['code']),
          message: response['message'] is String
              ? response['message']! as String
              : null,
        ),
      );
    }
    if (response['status'] != 'success' ||
        response['items'] is! List<Object?>) {
      return _malformedResponse();
    }

    final items = <VerifiedTrashItem>[];
    for (final value in response['items']! as List<Object?>) {
      if (value is! Map<Object?, Object?> || value['isTrashed'] != true) {
        return _malformedResponse();
      }
      if (value['initialBytesReadable'] != null &&
          value['initialBytesReadable'] is! bool) {
        return _malformedResponse();
      }
      final mappedMetadata = CurrentMediaMetadataPlatformMapper.fromResponse({
        'status': 'success',
        'metadata': value,
      });
      if (mappedMetadata is! CurrentMediaMetadataSuccess) {
        return _malformedResponse();
      }
      items.add(
        VerifiedTrashItem.fromPlatformTrash(
          metadata: mappedMetadata.metadata,
          initialBytesReadable: value['initialBytesReadable'] != false,
        ),
      );
    }

    final continuation = response['nextAfterMediaStoreId'];
    if (continuation != null && continuation is! int) {
      return _malformedResponse();
    }

    final continuationToken = response['nextContinuationToken'];
    if (continuationToken != null && continuationToken is! String) {
      return _malformedResponse();
    }
    final scannedVolumeName = response['scannedVolumeName'];
    if (scannedVolumeName != null && scannedVolumeName is! String) {
      return _malformedResponse();
    }
    final invalidFilesRejected = response['invalidFilesRejected'];
    if (invalidFilesRejected != null &&
        (invalidFilesRejected is! int || invalidFilesRejected < 0)) {
      return _malformedResponse();
    }
    final inaccessibleFiles = response['inaccessibleFiles'];
    if (inaccessibleFiles != null &&
        (inaccessibleFiles is! int || inaccessibleFiles < 0)) {
      return _malformedResponse();
    }
    final rawRowsExamined = response['rawRowsExamined'];
    if (rawRowsExamined != null &&
        (rawRowsExamined is! int || rawRowsExamined < 0)) {
      return _malformedResponse();
    }

    return TrashDiscoverySuccess(
      TrashDiscoveryPage(
        items: List.unmodifiable(items),
        nextAfterMediaStoreId: continuation as int?,
        nextContinuationToken: continuationToken as String?,
        scannedVolumeName: scannedVolumeName as String?,
        invalidFilesRejected: invalidFilesRejected is int
            ? invalidFilesRejected
            : 0,
        inaccessibleFiles: inaccessibleFiles is int ? inaccessibleFiles : 0,
        rawRowsExamined: rawRowsExamined is int ? rawRowsExamined : 0,
      ),
    );
  }

  static TrashDiscoveryFailureCode _failureCode(Object? value) {
    return switch (value) {
      'mediaAccessUnavailable' =>
        TrashDiscoveryFailureCode.mediaAccessUnavailable,
      'securityDenied' => TrashDiscoveryFailureCode.securityDenied,
      'platformFailure' => TrashDiscoveryFailureCode.platformFailure,
      _ => TrashDiscoveryFailureCode.malformedPlatformResponse,
    };
  }

  static TrashDiscoveryFailureResult _malformedResponse() {
    return const TrashDiscoveryFailureResult(
      TrashDiscoveryFailure(
        code: TrashDiscoveryFailureCode.malformedPlatformResponse,
      ),
    );
  }
}
