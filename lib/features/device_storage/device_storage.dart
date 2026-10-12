import 'package:flutter/services.dart';

class DeviceStorageSnapshot {
  const DeviceStorageSnapshot({
    required this.totalBytes,
    required this.availableBytes,
  });

  final int totalBytes;
  final int availableBytes;

  int get usedBytes => totalBytes - availableBytes;
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;
}

abstract interface class DeviceStorageReader {
  Future<DeviceStorageSnapshot?> read();
}

class PlatformDeviceStorageReader implements DeviceStorageReader {
  PlatformDeviceStorageReader({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/device_storage';
  final MethodChannel _channel;

  @override
  Future<DeviceStorageSnapshot?> read() async {
    try {
      final response = await _channel.invokeMethod<Object?>('getDeviceStorage');
      return DeviceStorageMapper.fromResponse(response);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

abstract final class DeviceStorageMapper {
  static DeviceStorageSnapshot? fromResponse(Object? response) {
    if (response is! Map<Object?, Object?>) return null;
    final total = response['totalBytes'];
    final available = response['availableBytes'];
    if (total is! num || available is! num) return null;
    final totalBytes = total.toInt();
    final availableBytes = available.toInt();
    if (totalBytes <= 0 || availableBytes < 0 || availableBytes > totalBytes) {
      return null;
    }
    return DeviceStorageSnapshot(
      totalBytes: totalBytes,
      availableBytes: availableBytes,
    );
  }
}
