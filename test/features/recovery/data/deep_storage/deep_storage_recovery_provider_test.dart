import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/deep_recovery/deep_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';

void main() {
  test('maps API 24-29 legacy shared-read capability', () {
    final state = PlatformDeepStorageRecoveryProvider.mapCapabilityResponse({
      'available': true,
      'requiresAllFilesAccess': false,
      'accessMode': 'legacySharedRead',
      'apiLevel': 29,
    });

    expect(state.available, isTrue);
    expect(state.requiresAllFilesAccess, isFalse);
    expect(state.mode, DeepStorageAccessMode.legacySharedRead);
    expect(state.androidApiLevel, 29);
  });

  test('maps API 30+ All Files Access capability separately', () {
    final state = PlatformDeepStorageRecoveryProvider.mapCapabilityResponse({
      'available': true,
      'requiresAllFilesAccess': true,
      'accessMode': 'allFilesAccess',
      'apiLevel': 34,
    });

    expect(state.available, isTrue);
    expect(state.requiresAllFilesAccess, isTrue);
    expect(state.mode, DeepStorageAccessMode.allFilesAccess);
    expect(state.androidApiLevel, 34);
  });

  test(
    'maps extensionless and wrong-extension images from detected content',
    () {
      final result = PlatformDeepStorageRecoveryProvider.mapResponse({
        'status': 'success',
        'items': [
          _item(name: 'extensionless', format: 'jpeg', mime: 'image/jpeg'),
          _item(name: 'photo.txt', format: 'png', mime: 'image/png'),
          _item(name: 'modern.bin', format: 'heif', mime: 'image/heif'),
          _item(name: 'preview.cache', format: 'webp', mime: 'image/webp'),
        ],
        'filesExamined': 7,
        'invalidFilesRejected': 3,
        'unavailableFiles': 0,
        'volumesScanned': ['external_primary', '0123-4567'],
      });

      final page = result as DeepRecoveryProviderPage;
      expect(page.items, hasLength(4));
      expect(page.filesExamined, 7);
      expect(page.invalidFilesRejected, 3);
      expect(page.volumesScanned, {'external_primary', '0123-4567'});
      expect(page.items.map((item) => item.candidate.mimeType), [
        'image/jpeg',
        'image/png',
        'image/heif',
        'image/webp',
      ]);
      expect(
        page.items.every(
          (item) =>
              item.candidate.classification ==
              RecoveryClassification.possibleCopy,
        ),
        isTrue,
      );
    },
  );

  test('thumbnail evidence remains a reduced copy, never deleted', () {
    final result = PlatformDeepStorageRecoveryProvider.mapResponse({
      'status': 'success',
      'items': [
        _item(
          name: 'thumb.data',
          format: 'jpeg',
          mime: 'image/jpeg',
          thumbnail: true,
          width: 240,
          height: 180,
        ),
      ],
    }) as DeepRecoveryProviderPage;

    final candidate = result.items.single.candidate;
    expect(candidate.recoveryQuality, RecoveryQuality.reducedResolutionCopy);
    expect(candidate.classification.isDeletedRecoveryResult, isFalse);
    expect(
      result.items.single.provider,
      DeepRecoveryProviderKind.thumbnailCache,
    );
  });

  test('source mapping is strict and unknown remains unknown', () {
    final result = PlatformDeepStorageRecoveryProvider.mapResponse({
      'status': 'success',
      'items': [
        _item(name: 'a.jpg', source: 'messagingSharedMedia'),
        _item(name: 'b.jpg', source: 'not-a-source'),
      ],
    }) as DeepRecoveryProviderPage;

    expect(
      result.items.first.candidate.source,
      MediaSource.messagingSharedMedia,
    );
    expect(result.items.last.candidate.source, MediaSource.unknown);
  });

  test('unavailable All Files Access is a structured capability result', () {
    final result = PlatformDeepStorageRecoveryProvider.mapResponse({
      'status': 'failure',
      'code': 'accessRequired',
      'message': 'Deep storage access is not enabled.',
    });

    expect(result, isA<DeepRecoveryProviderUnavailable>());
    expect(
      (result as DeepRecoveryProviderUnavailable).availability,
      DeepProviderAvailability.accessRequired,
    );
  });

  test('typed access-required capability is preserved', () {
    final state = PlatformDeepStorageRecoveryProvider.mapCapabilityResponse({
      'status': 'accessRequired',
      'available': false,
      'requiresAllFilesAccess': true,
      'accessMode': 'allFilesAccess',
      'apiLevel': 35,
    });
    expect(state.status, DeepStorageCapabilityStatus.accessRequired);
    expect(state.available, isFalse);
  });

  test('native discovery evidence survives platform mapping', () {
    final value = _item(name: '.hidden.cache')
      ..addAll({
        'isTrashLike': true,
        'isCacheLike': true,
        'isHidden': true,
        'isExtensionMismatch': true,
        'isEmbeddedPayload': true,
        'embeddedOffset': 128,
        'containerPath': '/storage/emulated/0/cache/source.bin',
      });
    final result = PlatformDeepStorageRecoveryProvider.mapResponse({
      'status': 'success',
      'items': [value],
    }) as DeepRecoveryProviderPage;
    final evidence = result.items.single.candidate.discoveryEvidence;
    expect(evidence.isTrashLike, isTrue);
    expect(evidence.isCacheLike, isTrue);
    expect(evidence.isHidden, isTrue);
    expect(evidence.isExtensionMismatch, isTrue);
    expect(evidence.isEmbeddedPayload, isTrue);
    expect(evidence.embeddedOffset, 128);
  });

  test('maps native exhaustion and termination diagnostics', () {
    final result = PlatformDeepStorageRecoveryProvider.mapResponse({
      'status': 'success',
      'items': <Object?>[],
      'nextContinuationToken': null,
      'remainingDirectoryQueue': 0,
      'visitedDirectoryCount': 82,
      'duplicateDirectorySkips': 17,
      'repeatedCursorDetections': 0,
      'providerExhausted': true,
      'completionReason': 'exhausted',
      'entriesExamined': 200,
      'currentFilesSkipped': 175,
      'signatureCacheHits': 21,
      'signatureCacheMisses': 4,
      'nativeTraversalMs': 37,
      'unsupportedFiles': 3,
      'carvedTemporaryBytes': 4096,
      'carvedTempBytesReclaimed': 1024,
    }) as DeepRecoveryProviderPage;

    expect(result.nextContinuationToken, isNull);
    expect(result.providerExhausted, isTrue);
    expect(result.remainingDirectoryQueue, 0);
    expect(result.visitedDirectoryCount, 82);
    expect(result.duplicateDirectorySkips, 17);
    expect(result.completionReason, 'exhausted');
    expect(result.entriesExamined, 200);
    expect(result.currentFilesSkipped, 175);
    expect(result.signatureCacheHits, 21);
    expect(result.signatureCacheMisses, 4);
    expect(result.nativeTraversalMillis, 37);
    expect(result.unsupportedFiles, 3);
    expect(result.carvedTemporaryBytes, 4096);
    expect(result.carvedTempBytesReclaimed, 1024);
  });
}

Map<String, Object?> _item({
  required String name,
  String format = 'jpeg',
  String mime = 'image/jpeg',
  String source = 'cameraGallery',
  bool thumbnail = false,
  int width = 1920,
  int height = 1080,
}) => {
  'filePath': '/storage/emulated/0/DCIM/$name',
  'canonicalPath': '/storage/emulated/0/DCIM/$name',
  'displayName': name,
  'mimeType': mime,
  'detectedFormat': format,
  'byteSize': 1024,
  'width': width,
  'height': height,
  'modifiedMillis': 1000,
  'relativePath': 'DCIM',
  'storageVolumeName': 'external_primary',
  'isRemovableStorage': false,
  'source': source,
  'isTrashLike': false,
  'isThumbnailLike': thumbnail,
  'isCacheLike': thumbnail,
};
