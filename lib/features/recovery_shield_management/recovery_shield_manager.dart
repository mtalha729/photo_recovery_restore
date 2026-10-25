import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../recovery/application/recovery_shield/recovery_shield_models.dart';
import '../recovery/domain/media_source.dart';

class ShieldManagedItem {
  const ShieldManagedItem({
    required this.protectionId,
    required this.byteSize,
    required this.integrityVerified,
    this.displayName,
    this.record,
  });

  final String protectionId;
  final String? displayName;
  final int byteSize;
  final bool integrityVerified;
  final ProtectedMediaRecord? record;
}

class RecoveryShieldSnapshot {
  const RecoveryShieldSnapshot(this.items);

  final List<ShieldManagedItem> items;
  int get protectedCount => items.length;
  int get storageBytes => items.fold(0, (total, item) => total + item.byteSize);
}

abstract interface class RecoveryShieldManager {
  Future<RecoveryShieldSnapshot> load();
  Future<int> protectSelectedPhotos();
  Future<bool> unprotect(Iterable<String> protectionIds);
  Future<bool> clear();
}

class PlatformRecoveryShieldManager implements RecoveryShieldManager {
  PlatformRecoveryShieldManager({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'com.photorecoveryrestore.app/recovery_shield_management';
  final MethodChannel _channel;

  @override
  Future<RecoveryShieldSnapshot> load() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('getShieldItems');
      final items = List<ShieldManagedItem>.unmodifiable(
        (raw ?? const []).map(_item).whereType<ShieldManagedItem>(),
      );
      _debugProviderState(
        'completed',
        itemCount: items.length,
        verifiedCount: items.where((item) => item.integrityVerified).length,
        restorableCount: items.where((item) => item.record != null).length,
      );
      return RecoveryShieldSnapshot(items);
    } on PlatformException catch (error) {
      _debugProviderState('failed:${error.code}');
      return const RecoveryShieldSnapshot([]);
    } on MissingPluginException {
      _debugProviderState('unavailable');
      return const RecoveryShieldSnapshot([]);
    }
  }

  void _debugProviderState(
    String state, {
    int? itemCount,
    int? verifiedCount,
    int? restorableCount,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'Recovery Shield provider: state=$state${itemCount == null ? '' : ', items=$itemCount, integrityVerified=$verifiedCount, restoreMetadataAvailable=$restorableCount'}',
    );
  }

  ShieldManagedItem? _item(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final id = value['protectionId'];
    final size = value['byteSize'];
    final verified = value['integrityVerified'];
    if (id is! String || id.isEmpty || size is! int || size < 0 || verified is! bool) {
      return null;
    }
    final displayName = value['displayName'] is String
        ? value['displayName']! as String
        : null;
    final record = _record(value, protectionId: id, displayName: displayName);
    return ShieldManagedItem(
      protectionId: id,
      displayName: displayName,
      byteSize: size,
      integrityVerified: verified,
      record: record,
    );
  }

  ProtectedMediaRecord? _record(
    Map<Object?, Object?> value, {
    required String protectionId,
    required String? displayName,
  }) {
    final source = _source(value['originalSource']);
    final protectedCopyLocation = value['protectedCopyLocation'];
    final digest = value['sha256Digest'];
    final protectedAtMillis = value['protectedAtMillis'];
    final byteSize = value['byteSize'];
    if (source == null ||
        protectedCopyLocation is! String ||
        protectedCopyLocation.isEmpty ||
        digest is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest) ||
        protectedAtMillis is! int ||
        byteSize is! int ||
        byteSize < 0) {
      return null;
    }
    final originalContentUri = _contentUri(value['originalContentUri']);
    return ProtectedMediaRecord(
      protectionId: protectionId,
      originalContentUri: originalContentUri,
      originalSource: source,
      displayName: displayName,
      mimeType: value['mimeType'] is String ? value['mimeType']! as String : null,
      originalLocation: value['originalLocation'] is String
          ? value['originalLocation']! as String
          : null,
      byteSize: byteSize,
      width: _positiveInt(value['width']),
      height: _positiveInt(value['height']),
      createdAt: _date(value['createdAtMillis']),
      modifiedAt: _date(value['modifiedAtMillis']),
      takenAt: _date(value['takenAtMillis']),
      protectedCopyLocation: protectedCopyLocation,
      sha256Digest: digest.toLowerCase(),
      protectedAt: DateTime.fromMillisecondsSinceEpoch(protectedAtMillis),
    );
  }

  MediaSource? _source(Object? value) {
    if (value is! String) return null;
    for (final source in MediaSource.values) {
      if (source.name == value) return source;
    }
    return null;
  }

  Uri? _contentUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'content' ? uri : null;
  }

  DateTime? _date(Object? value) => value is int
      ? DateTime.fromMillisecondsSinceEpoch(value)
      : null;

  int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;

  @override
  Future<int> protectSelectedPhotos() async {
    try {
      return await _channel.invokeMethod<int>('protectSelectedPhotos') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  @override
  Future<bool> unprotect(Iterable<String> protectionIds) =>
      _boolean('unprotectItems', {'protectionIds': protectionIds.toList()});

  @override
  Future<bool> clear() => _boolean('clearShield');

  Future<bool> _boolean(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
