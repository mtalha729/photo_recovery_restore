import 'package:flutter/services.dart';

import '../../application/scoped_storage_recovery/storage_scope_models.dart';
import 'folder_scope_selector.dart';

class PlatformFolderScopeSelector implements FolderScopeSelector {
  const PlatformFolderScopeSelector()
    : _channel = const MethodChannel(_channelName);

  const PlatformFolderScopeSelector.withChannel(this._channel);

  static const _channelName = 'com.photorecoveryrestore.app/folder_scope';
  final MethodChannel _channel;

  @override
  Future<FolderScopeSelectionResult> selectFolder() => _invoke('selectFolder');

  @override
  Future<FolderScopeSelectionResult> checkGrant(AuthorizedFolderScope scope) =>
      _invoke('checkFolderGrant', {'treeUri': scope.treeUri.toString()});

  Future<FolderScopeSelectionResult> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        method,
        arguments,
      );
      if (raw == null) return _failure('Missing platform response.');
      final status = _status(raw['status']);
      if (status != FolderScopeSelectionStatus.selected) {
        return FolderScopeSelectionResult(
          status: status,
          message: raw['message'] is String ? raw['message'] as String : null,
        );
      }
      final treeUri = Uri.tryParse(raw['treeUri'] as String? ?? '');
      if (treeUri == null || !treeUri.hasScheme) {
        return _failure('Invalid folder tree URI.');
      }
      final volumeName = _clean(raw['volumeName']);
      final removable = raw['isRemovable'];
      return FolderScopeSelectionResult(
        status: status,
        scope: AuthorizedFolderScope(
          treeUri: treeUri,
          documentId: _clean(raw['documentId']),
          relativePathPrefix: _clean(raw['relativePath']),
          volume: volumeName == null || removable is! bool
              ? null
              : StorageVolumeIdentity(
                  mediaStoreVolumeName: volumeName,
                  isRemovable: removable,
                ),
          grantState: FolderGrantState.active,
        ),
      );
    } on PlatformException catch (error) {
      return _failure(error.message);
    } on MissingPluginException {
      return _failure('Folder selection is unavailable.');
    }
  }

  FolderScopeSelectionStatus _status(Object? raw) => switch (raw) {
    'selected' => FolderScopeSelectionStatus.selected,
    'cancelled' => FolderScopeSelectionStatus.cancelled,
    'restrictedLocation' => FolderScopeSelectionStatus.restrictedLocation,
    'permissionGrantLost' => FolderScopeSelectionStatus.permissionGrantLost,
    'accessUnavailable' => FolderScopeSelectionStatus.accessUnavailable,
    'operationInProgress' => FolderScopeSelectionStatus.operationInProgress,
    _ => FolderScopeSelectionStatus.platformFailure,
  };

  FolderScopeSelectionResult _failure(String? message) =>
      FolderScopeSelectionResult(
        status: FolderScopeSelectionStatus.platformFailure,
        message: message,
      );

  String? _clean(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
