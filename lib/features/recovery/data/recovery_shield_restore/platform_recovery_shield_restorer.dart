import 'package:flutter/services.dart';

import '../../application/recovery_shield_restore/recovery_shield_restore_models.dart';
import '../../application/reliability/keyed_operation_coordinator.dart';
import '../../application/reliability/recovery_operation_failure.dart';
import 'recovery_shield_restorer.dart';

class PlatformRecoveryShieldRestorer implements RecoveryShieldRestorer {
  PlatformRecoveryShieldRestorer({KeyedOperationCoordinator? coordinator})
    : _channel = const MethodChannel(_channelName),
      _coordinator = coordinator ?? KeyedOperationCoordinator();

  PlatformRecoveryShieldRestorer.withChannel(
    this._channel, {
    KeyedOperationCoordinator? coordinator,
  }) : _coordinator = coordinator ?? KeyedOperationCoordinator();

  static const _channelName =
      'com.photorecoveryrestore.app/recovery_shield_restore';
  final MethodChannel _channel;
  final KeyedOperationCoordinator _coordinator;

  @override
  Future<RecoveryShieldRestoreBatchResult> restoreBatch(
    Iterable<RecoveryShieldRestorePreparation> preparations,
  ) async {
    final results = <RecoveryShieldRestoreResult>[];
    for (final preparation in preparations) {
      final rejection = preparation.rejection;
      if (rejection != null) {
        results.add(rejection);
      } else {
        results.add(await restore(preparation.request!));
      }
    }
    return RecoveryShieldRestoreBatchResult(List.unmodifiable(results));
  }

  @override
  Future<RecoveryShieldRestoreResult> restore(
    RecoveryShieldRestoreRequest request,
  ) async {
    final id = request.record.protectionId;
    final coordinated = await _coordinator.run(
      key: 'restore:$id',
      operation: () => _restoreOnce(request),
      rememberResult: (result) => result.isSuccessful,
    );
    return switch (coordinated.state) {
      CoordinatedOperationState.executed => coordinated.value!,
      CoordinatedOperationState.replayed => RecoveryShieldRestoreResult(
        protectionId: id,
        status: RecoveryShieldRestoreStatus.alreadyPresent,
        restoredContentUri: coordinated.value!.restoredContentUri,
      ),
      CoordinatedOperationState.conflict => RecoveryShieldRestoreResult(
        protectionId: id,
        status: RecoveryShieldRestoreStatus.operationInProgress,
        failure: RecoveryOperationFailure(
          kind: RecoveryOperationFailureKind.operationConflict,
          operationId: 'restore:$id',
          itemId: id,
          retryable: true,
        ),
      ),
    };
  }

  Future<RecoveryShieldRestoreResult> _restoreOnce(
    RecoveryShieldRestoreRequest request,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'restoreProtectedCopy',
        _arguments(request),
      );
      if (raw == null) return _failure(request, 'Missing platform response.');
      final status = _status(raw['status']);
      final uriText = raw['restoredContentUri'];
      final uri = uriText is String ? Uri.tryParse(uriText) : null;
      if (status == RecoveryShieldRestoreStatus.restored &&
          (uri == null || uri.scheme != 'content')) {
        return _failure(request, 'Missing restored content URI.');
      }
      return RecoveryShieldRestoreResult(
        protectionId: request.record.protectionId,
        status: status,
        restoredContentUri: uri,
        message: raw['message'] is String ? raw['message'] as String : null,
        usedPendingPublish: raw['usedPendingPublish'] == true,
        failure: _normalizedFailure(status, request.record.protectionId),
      );
    } on PlatformException catch (error) {
      return _failure(
        request,
        error.message,
        RecoveryOperationFailureKind.platformFailure,
      );
    } on MissingPluginException {
      return _failure(
        request,
        'Recovery Shield restore is unavailable.',
        RecoveryOperationFailureKind.unsupportedCapability,
      );
    }
  }

  Map<String, Object?> _arguments(RecoveryShieldRestoreRequest request) {
    final record = request.record;
    final scope = request.authorizedDestinationScope;
    return {
      'protectionId': record.protectionId,
      'protectedCopyLocation': record.protectedCopyLocation,
      'sha256Digest': record.sha256Digest,
      'expectedByteSize': record.byteSize,
      'originalContentUri': record.originalContentUri?.toString(),
      'displayName': record.displayName,
      'mimeType': record.mimeType,
      'dateTakenMillis': record.takenAt?.millisecondsSinceEpoch,
      'dateModifiedMillis': record.modifiedAt?.millisecondsSinceEpoch,
      'relativeDestination': request.relativeDestination,
      'destinationTreeUri': scope?.treeUri.toString(),
    };
  }

  RecoveryShieldRestoreStatus _status(Object? value) => switch (value) {
    'restored' => RecoveryShieldRestoreStatus.restored,
    'alreadyPresent' => RecoveryShieldRestoreStatus.alreadyPresent,
    'notEligible' => RecoveryShieldRestoreStatus.notEligible,
    'protectedCopyMissing' => RecoveryShieldRestoreStatus.protectedCopyMissing,
    'integrityFailure' => RecoveryShieldRestoreStatus.integrityFailure,
    'destinationRequired' => RecoveryShieldRestoreStatus.destinationRequired,
    'accessRequired' => RecoveryShieldRestoreStatus.accessRequired,
    'insufficientStorage' => RecoveryShieldRestoreStatus.insufficientStorage,
    'writeFailure' => RecoveryShieldRestoreStatus.writeFailure,
    'verificationFailure' => RecoveryShieldRestoreStatus.verificationFailure,
    'operationInProgress' => RecoveryShieldRestoreStatus.operationInProgress,
    _ => RecoveryShieldRestoreStatus.platformFailure,
  };

  RecoveryShieldRestoreResult _failure(
    RecoveryShieldRestoreRequest request,
    String? message, [
    RecoveryOperationFailureKind kind =
        RecoveryOperationFailureKind.malformedResponse,
  ]) => RecoveryShieldRestoreResult(
    protectionId: request.record.protectionId,
    status: RecoveryShieldRestoreStatus.platformFailure,
    message: message,
    failure: RecoveryOperationFailure(
      kind: kind,
      operationId: 'restore:${request.record.protectionId}',
      itemId: request.record.protectionId,
      message: message,
    ),
  );

  RecoveryOperationFailure? _normalizedFailure(
    RecoveryShieldRestoreStatus status,
    String itemId,
  ) {
    if (status == RecoveryShieldRestoreStatus.restored ||
        status == RecoveryShieldRestoreStatus.alreadyPresent) {
      return null;
    }
    final kind = switch (status) {
      RecoveryShieldRestoreStatus.protectedCopyMissing =>
        RecoveryOperationFailureKind.staleSource,
      RecoveryShieldRestoreStatus.destinationRequired =>
        RecoveryOperationFailureKind.storageUnavailable,
      RecoveryShieldRestoreStatus.accessRequired =>
        RecoveryOperationFailureKind.accessRevoked,
      RecoveryShieldRestoreStatus.insufficientStorage =>
        RecoveryOperationFailureKind.insufficientStorage,
      RecoveryShieldRestoreStatus.writeFailure =>
        RecoveryOperationFailureKind.writeFailure,
      RecoveryShieldRestoreStatus.integrityFailure ||
      RecoveryShieldRestoreStatus.verificationFailure =>
        RecoveryOperationFailureKind.verificationFailure,
      RecoveryShieldRestoreStatus.operationInProgress =>
        RecoveryOperationFailureKind.operationConflict,
      _ => RecoveryOperationFailureKind.platformFailure,
    };
    return RecoveryOperationFailure(
      kind: kind,
      operationId: 'restore:$itemId',
      itemId: itemId,
      retryable: kind != RecoveryOperationFailureKind.verificationFailure,
    );
  }
}
