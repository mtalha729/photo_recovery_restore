import 'package:flutter/services.dart';

class ShieldManagedItem {
  const ShieldManagedItem({
    required this.protectionId,
    required this.byteSize,
    required this.integrityVerified,
    this.displayName,
  });

  final String protectionId;
  final String? displayName;
  final int byteSize;
  final bool integrityVerified;
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
      return RecoveryShieldSnapshot(
        List.unmodifiable((raw ?? const []).map(_item).whereType<ShieldManagedItem>()),
      );
    } on PlatformException {
      return const RecoveryShieldSnapshot([]);
    } on MissingPluginException {
      return const RecoveryShieldSnapshot([]);
    }
  }

  ShieldManagedItem? _item(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final id = value['protectionId'];
    final size = value['byteSize'];
    final verified = value['integrityVerified'];
    if (id is! String || id.isEmpty || size is! int || size < 0 || verified is! bool) {
      return null;
    }
    return ShieldManagedItem(
      protectionId: id,
      displayName: value['displayName'] is String ? value['displayName']! as String : null,
      byteSize: size,
      integrityVerified: verified,
    );
  }

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
