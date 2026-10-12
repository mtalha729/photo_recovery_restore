import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/platform_trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';

void main() {
  Map<Object?, Object?> trashedItem({int id = 42}) => {
    'mediaStoreId': id,
    'contentUri': 'content://media/external/images/media/$id',
    'displayName': 'trashed.jpg',
    'mimeType': 'image/jpeg',
    'isTrashed': true,
  };

  test('verified platform trash maps to verified deletion evidence', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [trashedItem()],
      'nextAfterMediaStoreId': null,
    });

    final item = (result as TrashDiscoverySuccess).page.items.single;
    expect(item.classification, RecoveryClassification.verifiedDeleted);
    expect(
      item.deletionEvidence.reasons,
      contains(DeletionEvidenceReason.systemTrashRecord),
    );
  });

  test('current normal media cannot map to verified trash', () {
    final item = trashedItem()..['isTrashed'] = false;
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [item],
      'nextAfterMediaStoreId': null,
    });

    expect(result, isA<TrashDiscoveryFailureResult>());
  });

  test('Android API 24 through 29 is explicitly unsupported', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'unsupported',
      'androidApiLevel': 29,
    });

    expect(result, isA<TrashDiscoveryUnsupported>());
    expect((result as TrashDiscoveryUnsupported).androidApiLevel, 29);
  });

  test('empty trash is a valid successful page', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': <Object?>[],
      'nextAfterMediaStoreId': null,
    });

    final page = (result as TrashDiscoverySuccess).page;
    expect(page.items, isEmpty);
    expect(page.mayHaveMore, isFalse);
  });

  test('access failure is safe and structured', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'failure',
      'code': 'securityDenied',
      'message': 'Media trash access is unavailable.',
    });

    expect(
      (result as TrashDiscoveryFailureResult).failure.code,
      TrashDiscoveryFailureCode.securityDenied,
    );
  });

  test('malformed optional metadata remains unknown', () {
    final item = trashedItem()
      ..['displayName'] = ['invalid']
      ..['byteSize'] = -1
      ..['width'] = 'wide';
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [item],
      'nextAfterMediaStoreId': null,
    });

    final metadata =
        (result as TrashDiscoverySuccess).page.items.single.metadata;
    expect(metadata.displayName, isNull);
    expect(metadata.byteSize, isNull);
    expect(metadata.width, isNull);
  });

  test('unavailable or absent media is not deletion proof', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'failure',
      'code': 'mediaAccessUnavailable',
    });

    expect(result, isA<TrashDiscoveryFailureResult>());
  });

  test('possible copies remain separate from verified trash', () {
    expect(RecoveryClassification.possibleCopy.isVerifiedDeleted, isFalse);
  });

  test('pagination continuation is preserved', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [trashedItem(id: 10)],
      'nextAfterMediaStoreId': 10,
    });

    final page = (result as TrashDiscoverySuccess).page;
    expect(page.mayHaveMore, isTrue);
    expect(page.nextAfterMediaStoreId, 10);
  });

  test('trash proof remains categorical without a confidence score', () {
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [trashedItem()],
      'nextAfterMediaStoreId': null,
    });

    final item = (result as TrashDiscoverySuccess).page.items.single;
    expect(item.deletionEvidence.reasons, hasLength(1));
    expect(item.classification, RecoveryClassification.verifiedDeleted);
  });

  test('verified trash preserves volume identity and opaque continuation', () {
    final item = trashedItem()..['storageVolumeName'] = '1234-5678';
    final result = TrashDiscoveryPlatformMapper.fromResponse({
      'status': 'success',
      'items': [item],
      'nextContinuationToken': 'mv1:1:42',
      'scannedVolumeName': '1234-5678',
    });

    final page = (result as TrashDiscoverySuccess).page;
    expect(page.items.single.metadata.storageVolumeName, '1234-5678');
    expect(page.nextContinuationToken, 'mv1:1:42');
    expect(page.scannedVolumeName, '1234-5678');
  });
}
