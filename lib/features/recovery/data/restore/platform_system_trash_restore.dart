import 'package:flutter/services.dart';

import '../../application/restore/system_trash_restore_models.dart';
import '../../application/restore/system_trash_restore_policy.dart';

abstract interface class SystemTrashRestoreExecutor {
  Future<SystemTrashRestoreResult> restoreBatch(SystemTrashRestoreBatch batch);
}

class PlatformSystemTrashRestore implements SystemTrashRestoreExecutor {
  PlatformSystemTrashRestore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/system_trash_restore';

  final MethodChannel _channel;

  @override
  Future<SystemTrashRestoreResult> restoreBatch(
    SystemTrashRestoreBatch batch,
  ) async {
    if (batch.requests.isEmpty ||
        batch.requests.length >
            SystemTrashRestorePlanBuilder.maximumBatchSize) {
      throw ArgumentError.value(batch.requests.length, 'batch size');
    }

    try {
      final response = await _channel.invokeMethod<Object?>(
        'restoreSystemTrashBatch',
        {'uris': batch.contentUris.map((uri) => uri.toString()).toList()},
      );
      return SystemTrashRestorePlatformMapper.fromResponse(response);
    } on PlatformException catch (error) {
      return SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.platformFailure,
        message: error.message,
      );
    } on MissingPluginException {
      return const SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.unsupportedPlatform,
      );
    }
  }
}

class SystemTrashRestorePlatformMapper {
  const SystemTrashRestorePlatformMapper._();

  static SystemTrashRestoreResult fromResponse(Object? response) {
    if (response is! Map<Object?, Object?> || response['status'] is! String) {
      return const SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.platformFailure,
      );
    }

    final status = switch (response['status']) {
      'restored' => SystemTrashRestoreStatus.restored,
      'userDeniedOrCancelled' => SystemTrashRestoreStatus.userDeniedOrCancelled,
      'unsupportedPlatform' => SystemTrashRestoreStatus.unsupportedPlatform,
      'staleOrMissingMediaItem' =>
        SystemTrashRestoreStatus.staleOrMissingMediaItem,
      'accessFailure' => SystemTrashRestoreStatus.accessFailure,
      'verificationFailed' => SystemTrashRestoreStatus.verificationFailed,
      'operationInProgress' => SystemTrashRestoreStatus.operationInProgress,
      _ => SystemTrashRestoreStatus.platformFailure,
    };
    return SystemTrashRestoreResult(
      status: status,
      message: response['message'] is String
          ? response['message']! as String
          : null,
      affectedUris: _uris(response['affectedUris']),
      unverifiedUris: _uris(response['unverifiedUris']),
    );
  }

  static List<Uri> _uris(Object? value) {
    if (value is! List<Object?>) return const [];
    return List.unmodifiable(
      value.whereType<String>().map(Uri.tryParse).whereType<Uri>(),
    );
  }
}
