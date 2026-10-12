import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/device_storage/device_storage.dart';

void main() {
  test('maps valid device storage values without inventing capacity', () {
    final storage = DeviceStorageMapper.fromResponse({
      'totalBytes': 128000,
      'availableBytes': 48000,
    });

    expect(storage, isNotNull);
    expect(storage!.usedBytes, 80000);
    expect(storage.usedFraction, closeTo(.625, .0001));
  });

  test('rejects malformed or impossible storage responses', () {
    expect(DeviceStorageMapper.fromResponse(null), isNull);
    expect(
      DeviceStorageMapper.fromResponse({
        'totalBytes': 10,
        'availableBytes': 11,
      }),
      isNull,
    );
    expect(
      DeviceStorageMapper.fromResponse({'totalBytes': 0, 'availableBytes': 0}),
      isNull,
    );
  });
}
