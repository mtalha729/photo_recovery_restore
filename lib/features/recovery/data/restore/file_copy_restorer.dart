import 'package:flutter/services.dart';

import '../../domain/media_candidate.dart';

enum FileCopyRestoreStatus {
  restored,
  sourceUnavailable,
  accessRequired,
  invalidImage,
  insufficientStorage,
  writeFailure,
  verificationFailure,
  platformFailure,
}

class FileCopyRestoreRequest {
  const FileCopyRestoreRequest({required this.candidate});
  final MediaCandidate candidate;
}

class FileCopyRestoreResult {
  const FileCopyRestoreResult(this.status, {this.destinationUri});
  final FileCopyRestoreStatus status;
  final Uri? destinationUri;
}

abstract interface class FileCopyRestorer {
  Future<FileCopyRestoreResult> restore(FileCopyRestoreRequest request);
}

class PlatformFileCopyRestorer implements FileCopyRestorer {
  const PlatformFileCopyRestorer()
    : _channel = const MethodChannel(_channelName);
  const PlatformFileCopyRestorer.withChannel(this._channel);

  static const _channelName = 'com.photorecoveryrestore.app/file_copy_restore';
  final MethodChannel _channel;

  @override
  Future<FileCopyRestoreResult> restore(FileCopyRestoreRequest request) async {
    final candidate = request.candidate;
    final sourceUri = candidate.documentUri ?? candidate.contentUri;
    final filePath = candidate.filePath;
    if ((sourceUri == null || sourceUri.scheme != 'content') &&
        (filePath == null || filePath.trim().isEmpty)) {
      return const FileCopyRestoreResult(
        FileCopyRestoreStatus.sourceUnavailable,
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('restoreFileCopy', {
        if (sourceUri != null && sourceUri.scheme == 'content')
          'sourceUri': sourceUri.toString()
        else
          'filePath': filePath,
        'displayName': candidate.displayName,
        'mimeType': candidate.mimeType,
        'expectedSize': candidate.byteSize,
        if (candidate.discoveryEvidence.isEmbeddedPayload) ...{
          'containerPath': candidate.discoveryEvidence.containerPath,
          'embeddedOffset': candidate.discoveryEvidence.embeddedOffset,
          'detectedFormat': candidate.discoveryEvidence.detectedFormat,
        },
      });
      if (raw is! Map<Object?, Object?>) {
        return const FileCopyRestoreResult(
          FileCopyRestoreStatus.platformFailure,
        );
      }
      final status = switch (raw['status']) {
        'restored' => FileCopyRestoreStatus.restored,
        'sourceUnavailable' => FileCopyRestoreStatus.sourceUnavailable,
        'accessRequired' => FileCopyRestoreStatus.accessRequired,
        'invalidImage' => FileCopyRestoreStatus.invalidImage,
        'insufficientStorage' => FileCopyRestoreStatus.insufficientStorage,
        'writeFailure' => FileCopyRestoreStatus.writeFailure,
        'verificationFailure' => FileCopyRestoreStatus.verificationFailure,
        _ => FileCopyRestoreStatus.platformFailure,
      };
      final uri = raw['destinationUri'];
      return FileCopyRestoreResult(
        status,
        destinationUri: uri is String ? Uri.tryParse(uri) : null,
      );
    } on PlatformException {
      return const FileCopyRestoreResult(FileCopyRestoreStatus.platformFailure);
    } on MissingPluginException {
      return const FileCopyRestoreResult(FileCopyRestoreStatus.platformFailure);
    }
  }
}
