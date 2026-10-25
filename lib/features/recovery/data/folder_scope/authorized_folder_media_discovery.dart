import 'package:flutter/services.dart';

class AuthorizedFolderMediaRecord {
  const AuthorizedFolderMediaRecord({
    required this.documentUri,
    this.displayName,
    this.mimeType,
    this.declaredMimeType,
    this.detectedFormat,
    this.relativeLocation,
    this.byteSize,
    this.modifiedAt,
  });

  final Uri documentUri;
  final String? displayName;
  final String? mimeType;
  final String? declaredMimeType;
  final String? detectedFormat;
  final String? relativeLocation;
  final int? byteSize;
  final DateTime? modifiedAt;
}

class AuthorizedFolderMediaPage {
  const AuthorizedFolderMediaPage({
    required this.items,
    this.nextContinuationToken,
    this.filesExamined = 0,
    this.entriesExamined = 0,
    this.skippedNonImages = 0,
    this.invalidFilesRejected = 0,
    this.unavailableFiles = 0,
    this.unavailableDirectories = 0,
    this.unsupportedFiles = 0,
    this.providerExhausted = false,
    this.completionReason,
  });

  final List<AuthorizedFolderMediaRecord> items;
  final String? nextContinuationToken;
  final int filesExamined;
  final int entriesExamined;
  final int skippedNonImages;
  final int invalidFilesRejected;
  final int unavailableFiles;
  final int unavailableDirectories;
  final int unsupportedFiles;
  final bool providerExhausted;
  final String? completionReason;
  bool get mayHaveMore => nextContinuationToken != null;
}

enum AuthorizedFolderMediaFailureCode {
  permissionGrantLost,
  cancelled,
  platformFailure,
  malformedPlatformResponse,
}

sealed class AuthorizedFolderMediaResult {
  const AuthorizedFolderMediaResult();
}

class AuthorizedFolderMediaSuccess extends AuthorizedFolderMediaResult {
  const AuthorizedFolderMediaSuccess(this.page);
  final AuthorizedFolderMediaPage page;
}

class AuthorizedFolderMediaFailure extends AuthorizedFolderMediaResult {
  const AuthorizedFolderMediaFailure(this.code, {this.message});
  final AuthorizedFolderMediaFailureCode code;
  final String? message;
}

abstract interface class AuthorizedFolderMediaDiscovery {
  Future<AuthorizedFolderMediaResult> getPage({
    required Uri treeUri,
    required int pageSize,
    String? continuationToken,
  });

  /// Cancels native cursor/traversal work; unsupported providers may no-op.
  Future<void> cancelScan({String? continuationToken});
}

class PlatformAuthorizedFolderMediaDiscovery
    implements AuthorizedFolderMediaDiscovery {
  const PlatformAuthorizedFolderMediaDiscovery()
    : _channel = const MethodChannel(_channelName);

  const PlatformAuthorizedFolderMediaDiscovery.withChannel(this._channel);

  static const _channelName = 'com.photorecoveryrestore.app/folder_scope';
  static const _maximumPageSize = 200;
  final MethodChannel _channel;

  @override
  Future<AuthorizedFolderMediaResult> getPage({
    required Uri treeUri,
    required int pageSize,
    String? continuationToken,
  }) async {
    if (pageSize <= 0 || pageSize > _maximumPageSize) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    try {
      final response = await _channel.invokeMethod<Object?>(
        'getAuthorizedFolderMediaPage',
        {
          'treeUri': treeUri.toString(),
          'pageSize': pageSize,
          'continuationToken': continuationToken,
        },
      );
      return mapResponse(response);
    } on PlatformException catch (error) {
      return AuthorizedFolderMediaFailure(
        AuthorizedFolderMediaFailureCode.platformFailure,
        message: error.message,
      );
    } on MissingPluginException {
      return const AuthorizedFolderMediaFailure(
        AuthorizedFolderMediaFailureCode.platformFailure,
      );
    }
  }

  @override
  Future<void> cancelScan({String? continuationToken}) async {
    try {
      await _channel.invokeMethod<void>('cancelAuthorizedFolderScan', {
        'continuationToken': continuationToken,
      });
    } on PlatformException {
      // The Dart cancellation token remains authoritative if native cancellation
      // is unavailable; this call only closes a live provider cursor promptly.
    } on MissingPluginException {
      // Older platform implementations can still stop between pages.
    }
  }

  static AuthorizedFolderMediaResult mapResponse(Object? response) {
    if (response is! Map<Object?, Object?>) return _malformed();
    if (response['status'] == 'failure') {
      return AuthorizedFolderMediaFailure(
        response['code'] == 'permissionGrantLost'
            ? AuthorizedFolderMediaFailureCode.permissionGrantLost
            : response['code'] == 'cancelled'
            ? AuthorizedFolderMediaFailureCode.cancelled
            : AuthorizedFolderMediaFailureCode.platformFailure,
        message: response['message'] is String
            ? response['message']! as String
            : null,
      );
    }
    final rawItems = response['items'];
    final token = response['nextContinuationToken'];
    if (response['status'] != 'success' ||
        rawItems is! List<Object?> ||
        (token != null && token is! String)) {
      return _malformed();
    }
    final items = <AuthorizedFolderMediaRecord>[];
    for (final raw in rawItems) {
      if (raw is! Map<Object?, Object?>) return _malformed();
      final uriText = raw['documentUri'];
      final uri = uriText is String ? Uri.tryParse(uriText) : null;
      if (uri == null || uri.scheme != 'content' || _isRestrictedUri(uri)) {
        return _malformed();
      }
      items.add(
        AuthorizedFolderMediaRecord(
          documentUri: uri,
          displayName: _text(raw['displayName']),
          mimeType: _text(raw['mimeType']),
          declaredMimeType: _text(raw['declaredMimeType']),
          detectedFormat: _text(raw['detectedFormat']),
          relativeLocation: _text(raw['relativeLocation']),
          byteSize: raw['byteSize'] is int && (raw['byteSize']! as int) >= 0
              ? raw['byteSize']! as int
              : null,
          modifiedAt:
              raw['modifiedMillis'] is int &&
                  (raw['modifiedMillis']! as int) > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  raw['modifiedMillis']! as int,
                  isUtc: true,
                )
              : null,
        ),
      );
    }
    return AuthorizedFolderMediaSuccess(
      AuthorizedFolderMediaPage(
        items: List.unmodifiable(items),
        nextContinuationToken: token as String?,
        filesExamined: _nonNegativeInt(response['filesExamined']),
        entriesExamined: _nonNegativeInt(response['entriesExamined']),
        skippedNonImages: _nonNegativeInt(response['skippedNonImages']),
        invalidFilesRejected: _nonNegativeInt(response['invalidFilesRejected']),
        unavailableFiles: _nonNegativeInt(response['unavailableFiles']),
        unavailableDirectories: _nonNegativeInt(
          response['unavailableDirectories'],
        ),
        unsupportedFiles: _nonNegativeInt(response['unsupportedFiles']),
        providerExhausted: response['providerExhausted'] == true,
        completionReason: _text(response['completionReason']),
      ),
    );
  }

  static bool _isRestrictedUri(Uri uri) {
    final normalized = Uri.decodeComponent(uri.toString())
        .replaceAll('\\', '/')
        .toLowerCase();
    return normalized.contains(':android/data') ||
        normalized.contains('/android/data') ||
        normalized.contains(':android/obb') ||
        normalized.contains('/android/obb');
  }

  static String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static int _nonNegativeInt(Object? value) =>
      value is int && value >= 0 ? value : 0;

  static AuthorizedFolderMediaFailure _malformed() =>
      const AuthorizedFolderMediaFailure(
        AuthorizedFolderMediaFailureCode.malformedPlatformResponse,
      );
}
