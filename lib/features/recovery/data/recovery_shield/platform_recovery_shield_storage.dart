import 'package:flutter/services.dart';

import '../../application/recovery_shield/recovery_shield_models.dart';
import '../../application/reliability/keyed_operation_coordinator.dart';
import '../../application/reliability/recovery_operation_failure.dart';
import 'recovery_shield_storage.dart';

class PlatformRecoveryShieldStorage implements RecoveryShieldStorage {
  PlatformRecoveryShieldStorage({KeyedOperationCoordinator? coordinator})
    : _channel = const MethodChannel(_channelName),
      _coordinator = coordinator ?? KeyedOperationCoordinator();

  PlatformRecoveryShieldStorage.withChannel(
    this._channel, {
    KeyedOperationCoordinator? coordinator,
  }) : _coordinator = coordinator ?? KeyedOperationCoordinator();

  static const _channelName =
      'com.photorecoveryrestore.app/recovery_shield';
  final MethodChannel _channel;
  final KeyedOperationCoordinator _coordinator;

  @override
  Future<RecoveryShieldBatchResult> protectBatch(
    Iterable<RecoveryShieldProtectionRequest> requests,
  ) async {
    final results = <RecoveryShieldProtectionResult>[];
    for (final request in requests) {
      results.add(await protect(request));
    }
    return RecoveryShieldBatchResult(List.unmodifiable(results));
  }

  @override
  Future<RecoveryShieldProtectionResult> protect(
    RecoveryShieldProtectionRequest request,
  ) async {
    final coordinated = await _coordinator.run(
      key: 'protect:${request.protectionId}',
      operation: () => _protectOnce(request),
      rememberResult: (result) => result.isSuccessful,
    );
    return switch (coordinated.state) {
      CoordinatedOperationState.executed => coordinated.value!,
      CoordinatedOperationState.replayed => RecoveryShieldProtectionResult(
        protectionId: request.protectionId,
        status: RecoveryShieldProtectionStatus.alreadyProtected,
        record: coordinated.value!.record,
      ),
      CoordinatedOperationState.conflict => RecoveryShieldProtectionResult(
        protectionId: request.protectionId,
        status: RecoveryShieldProtectionStatus.operationInProgress,
        failure: RecoveryOperationFailure(
          kind: RecoveryOperationFailureKind.operationConflict,
          operationId: 'protect:${request.protectionId}',
          itemId: request.protectionId,
          retryable: true,
        ),
      ),
    };
  }

  Future<RecoveryShieldProtectionResult> _protectOnce(
    RecoveryShieldProtectionRequest request,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'protectItem',
        _arguments(request),
      );
      if (raw == null) return _failure(request, 'Missing platform response.');
      final status = _status(raw['status']);
      final record = _record(raw, request);
      if (_isSuccess(status) && record == null) {
        return _failure(request, 'Protection verification was incomplete.');
      }
      return RecoveryShieldProtectionResult(
        protectionId: request.protectionId,
        status: status,
        record: record,
        message: raw['message'] is String ? raw['message'] as String : null,
        failure: _normalizedFailure(status, request.protectionId),
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
        'Recovery Shield storage is unavailable.',
        RecoveryOperationFailureKind.unsupportedCapability,
      );
    }
  }

  Map<String, Object?> _arguments(RecoveryShieldProtectionRequest request) {
    final candidate = request.candidate;
    return {
      'protectionId': request.protectionId,
      'sourceUri': request.sourceUri.toString(),
      'stableSourceIdentity': request.stableSourceIdentity,
      'source': candidate.source.name,
      'originalContentUri': candidate.contentUri?.toString(),
      'displayName': candidate.displayName,
      'mimeType': candidate.mimeType,
      'originalLocation': candidate.relativeLocation,
      'expectedByteSize': candidate.byteSize,
      'width': candidate.width,
      'height': candidate.height,
      'createdAtMillis': candidate.createdAt?.millisecondsSinceEpoch,
      'modifiedAtMillis': candidate.modifiedAt?.millisecondsSinceEpoch,
      'takenAtMillis': candidate.takenAt?.millisecondsSinceEpoch,
      'expectedSha256':
          candidate.verifiedContentDigest?.algorithm.trim().toLowerCase() ==
              'sha-256'
          ? candidate.verifiedContentDigest?.value.trim().toLowerCase()
          : null,
    };
  }

  ProtectedMediaRecord? _record(
    Map<String, Object?> raw,
    RecoveryShieldProtectionRequest request,
  ) {
    final location = raw['protectedCopyLocation'];
    final digest = raw['sha256Digest'];
    final byteSize = raw['byteSize'];
    final protectedAt = raw['protectedAtMillis'];
    if (location is! String ||
        location.isEmpty ||
        digest is! String ||
        digest.isEmpty ||
        byteSize is! int ||
        byteSize < 0 ||
        protectedAt is! int) {
      return null;
    }
    final candidate = request.candidate;
    return ProtectedMediaRecord(
      protectionId: request.protectionId,
      originalContentUri: candidate.contentUri,
      originalSource: candidate.source,
      displayName: candidate.displayName,
      mimeType: candidate.mimeType,
      originalLocation: candidate.relativeLocation,
      byteSize: byteSize,
      width: candidate.width,
      height: candidate.height,
      createdAt: candidate.createdAt,
      modifiedAt: candidate.modifiedAt,
      takenAt: candidate.takenAt,
      protectedCopyLocation: location,
      sha256Digest: digest,
      protectedAt: DateTime.fromMillisecondsSinceEpoch(
        protectedAt,
        isUtc: true,
      ),
    );
  }

  RecoveryShieldProtectionStatus _status(Object? value) => switch (value) {
    'protected' => RecoveryShieldProtectionStatus.protected,
    'alreadyProtected' => RecoveryShieldProtectionStatus.alreadyProtected,
    'updated' => RecoveryShieldProtectionStatus.updated,
    'sourceUnavailable' => RecoveryShieldProtectionStatus.sourceUnavailable,
    'accessFailure' => RecoveryShieldProtectionStatus.accessFailure,
    'insufficientStorage' => RecoveryShieldProtectionStatus.insufficientStorage,
    'integrityFailure' => RecoveryShieldProtectionStatus.integrityFailure,
    'cancelled' => RecoveryShieldProtectionStatus.cancelled,
    'operationInProgress' => RecoveryShieldProtectionStatus.operationInProgress,
    _ => RecoveryShieldProtectionStatus.platformFailure,
  };

  bool _isSuccess(RecoveryShieldProtectionStatus status) =>
      status == RecoveryShieldProtectionStatus.protected ||
      status == RecoveryShieldProtectionStatus.alreadyProtected ||
      status == RecoveryShieldProtectionStatus.updated;

  RecoveryShieldProtectionResult _failure(
    RecoveryShieldProtectionRequest request,
    String? message, [
    RecoveryOperationFailureKind kind =
        RecoveryOperationFailureKind.malformedResponse,
  ]) => RecoveryShieldProtectionResult(
    protectionId: request.protectionId,
    status: RecoveryShieldProtectionStatus.platformFailure,
    message: message,
    failure: RecoveryOperationFailure(
      kind: kind,
      operationId: 'protect:${request.protectionId}',
      itemId: request.protectionId,
      message: message,
    ),
  );

  RecoveryOperationFailure? _normalizedFailure(
    RecoveryShieldProtectionStatus status,
    String itemId,
  ) {
    if (_isSuccess(status)) return null;
    final kind = switch (status) {
      RecoveryShieldProtectionStatus.sourceUnavailable =>
        RecoveryOperationFailureKind.staleSource,
      RecoveryShieldProtectionStatus.accessFailure =>
        RecoveryOperationFailureKind.accessRevoked,
      RecoveryShieldProtectionStatus.insufficientStorage =>
        RecoveryOperationFailureKind.insufficientStorage,
      RecoveryShieldProtectionStatus.integrityFailure =>
        RecoveryOperationFailureKind.verificationFailure,
      RecoveryShieldProtectionStatus.cancelled =>
        RecoveryOperationFailureKind.cancelled,
      RecoveryShieldProtectionStatus.operationInProgress =>
        RecoveryOperationFailureKind.operationConflict,
      _ => RecoveryOperationFailureKind.platformFailure,
    };
    return RecoveryOperationFailure(
      kind: kind,
      operationId: 'protect:$itemId',
      itemId: itemId,
      retryable: kind != RecoveryOperationFailureKind.verificationFailure,
    );
  }
}
