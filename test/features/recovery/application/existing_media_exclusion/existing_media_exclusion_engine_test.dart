import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_engine.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_exclusion_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/media_metadata/current_media_metadata.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_discovery_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  const engine = ExistingMediaExclusionEngine();

  CurrentMediaRecord record(int id, {String? name, Uri? uri}) {
    return CurrentMediaRecord(
      mediaStoreId: id,
      contentUri: uri ?? Uri.parse('content://media/external/images/media/$id'),
      displayName: name,
      mimeType: 'image/jpeg',
    );
  }

  CurrentMediaMetadata metadata(
    int id, {
    String name = 'photo.jpg',
    int size = 4096,
    int width = 1200,
    int height = 800,
    String? relativePath = 'DCIM/Camera/',
    String? bucketName = 'Camera',
    String? volume = 'external_primary',
    DateTime? dateTaken,
  }) {
    return CurrentMediaMetadata(
      mediaStoreId: id,
      displayName: name,
      mimeType: 'image/jpeg',
      byteSize: size,
      width: width,
      height: height,
      relativePath: relativePath,
      bucketName: bucketName,
      storageVolumeName: volume,
      dateTaken: dateTaken,
    );
  }

  MediaCandidate candidate({
    Uri? uri,
    Uri? documentUri,
    int? mediaStoreId,
    String? volume,
    String? name,
    String? mimeType,
    int? size,
    int? width,
    int? height,
    String? relativeLocation,
    String? bucketName,
    DateTime? takenAt,
    RecoveryClassification classification = RecoveryClassification.unavailable,
  }) {
    return MediaCandidate(
      id: 'candidate',
      source: MediaSource.unknown,
      contentUri: uri,
      documentUri: documentUri,
      mediaStoreId: mediaStoreId,
      storageVolumeName: volume,
      displayName: name,
      mimeType: mimeType,
      byteSize: size,
      width: width,
      height: height,
      relativeLocation: relativeLocation,
      bucketName: bucketName,
      takenAt: takenAt,
      classification: classification,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.notRestorable,
      recoveryQuality: RecoveryQuality.unavailable,
    );
  }

  test('exact current-media URI is definitely existing and excluded', () {
    final current = record(1);
    final index = ExistingMediaIndex.build(records: [current]);

    final decision = engine.evaluate(candidate(uri: current.contentUri), index);

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
    expect(decision.excludesFromDeletedResults, isTrue);
    expect(decision.match?.record.mediaStoreId, 1);
  });

  test('exact SAF document URI is excluded when indexed as current media', () {
    final documentUri = Uri.parse(
      'content://provider/tree/primary%3APictures/document/primary%3APictures%2Fphoto.jpg',
    );
    final index = ExistingMediaIndex.build(
      records: [record(101, uri: documentUri)],
    );

    final decision = engine.evaluate(
      candidate(documentUri: documentUri),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
    expect(decision.excludesFromDeletedResults, isTrue);
  });

  test('same MediaStore ID and volume is definitely existing', () {
    final index = ExistingMediaIndex.build(
      records: [record(2)],
      metadata: [metadata(2)],
    );

    final decision = engine.evaluate(
      candidate(mediaStoreId: 2, volume: 'external_primary'),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
  });

  test('inventory fields exclude an exact current file without enrichment', () {
    const current = CurrentMediaRecord(
      mediaStoreId: 21,
      storageVolumeName: 'external_primary',
      displayName: 'current.jpg',
      mimeType: 'image/jpeg',
      byteSize: 4096,
      width: 1200,
      height: 800,
      relativePath: 'DCIM/Camera/',
    );
    final index = ExistingMediaIndex.build(records: [current]);

    final decision = engine.evaluate(
      candidate(
        volume: 'external_primary',
        relativeLocation: 'DCIM/Camera',
        name: 'current.jpg',
        size: 4096,
      ),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
  });

  test(
    'validated indexed cache is eligible but an uninspected cache is not',
    () {
      const cached = CurrentMediaRecord(
        mediaStoreId: 23,
        storageVolumeName: 'external_primary',
        relativePath: 'Pictures/.cache/',
        displayName: 'preview.jpg',
        byteSize: 1024,
      );
      final index = ExistingMediaIndex.build(records: [cached]);
      MediaCandidate cacheCandidate(RecoveryDiscoveryEvidence evidence) =>
          MediaCandidate(
            id: 'cache',
            source: MediaSource.cameraGallery,
            filePath: '/storage/emulated/0/Pictures/.cache/preview.jpg',
            displayName: 'preview.jpg',
            relativeLocation: 'Pictures/.cache/',
            storageVolumeName: 'external_primary',
            byteSize: 1024,
            classification: RecoveryClassification.possibleCopy,
            deletionEvidence: DeletionEvidence(),
            discoveryEvidence: evidence,
            restoreCapability: RestoreCapability.unknownQualityCopy,
            recoveryQuality: RecoveryQuality.unknownQualityCopy,
          );

      expect(
        index.storageLocationKeys,
        contains('external_primary|pictures/.cache|preview.jpg|1024'),
      );
      expect(index.ordinaryStorageLocationKeys, isEmpty);
      expect(
        engine
            .evaluate(
              cacheCandidate(
                const RecoveryDiscoveryEvidence(
                  isCacheLike: true,
                  detectedFormat: 'jpeg',
                ),
              ),
              index,
            )
            .type,
        ExistingMediaDecisionType.noExistingMatch,
      );
      expect(
        engine
            .evaluate(
              cacheCandidate(
                const RecoveryDiscoveryEvidence(isCacheLike: true),
              ),
              index,
            )
            .type,
        ExistingMediaDecisionType.definitelyExisting,
      );
    },
  );

  test(
    'current file path keys match the native case-insensitive prefilter',
    () {
      const current = CurrentMediaRecord(
        mediaStoreId: 42,
        storageVolumeName: 'external_primary',
        displayName: 'Current.JPG',
        byteSize: 4096,
        relativePath: 'DCIM/Camera/',
      );
      final index = ExistingMediaIndex.build(records: [current]);

      expect(
        index.storageLocationKeys,
        contains('external_primary|dcim/camera|current.jpg|4096'),
      );
      expect(
        engine
            .evaluate(
              candidate(
                volume: 'EXTERNAL_PRIMARY',
                relativeLocation: 'dcim/camera',
                name: 'current.jpg',
                size: 4096,
              ),
              index,
            )
            .type,
        ExistingMediaDecisionType.definitelyExisting,
      );
    },
  );

  test('same numeric ID metadata from another volume is not borrowed', () {
    const current = CurrentMediaRecord(
      mediaStoreId: 30,
      storageVolumeName: 'external_primary',
      displayName: 'primary.jpg',
    );
    final index = ExistingMediaIndex.build(
      records: [current],
      metadata: [metadata(30, name: 'removable.jpg', volume: '1234-5678')],
    );

    final decision = engine.evaluate(
      candidate(
        volume: '1234-5678',
        relativeLocation: 'DCIM/Camera',
        name: 'removable.jpg',
        size: 4096,
      ),
      index,
    );

    expect(decision.type, isNot(ExistingMediaDecisionType.definitelyExisting));
  });

  test('exact volume path name and size excludes a direct-file discovery', () {
    final index = ExistingMediaIndex.build(
      records: [record(22, name: 'photo.jpg')],
      metadata: [metadata(22)],
    );

    final decision = engine.evaluate(
      candidate(
        volume: 'external_primary',
        relativeLocation: r'DCIM\Camera\',
        name: 'PHOTO.JPG',
        size: 4096,
      ),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
    expect(decision.excludesFromDeletedResults, isTrue);
  });

  test('same filename alone is uncertain and not excluded', () {
    final index = ExistingMediaIndex.build(
      records: [record(3)],
      metadata: [metadata(3, name: 'same.jpg')],
    );

    final decision = engine.evaluate(candidate(name: 'same.jpg'), index);

    expect(decision.type, ExistingMediaDecisionType.uncertainIdentity);
    expect(decision.excludesFromDeletedResults, isFalse);
  });

  test('same dimensions alone are uncertain and not excluded', () {
    final index = ExistingMediaIndex.build(
      records: [record(4)],
      metadata: [metadata(4, width: 640, height: 480)],
    );

    final decision = engine.evaluate(candidate(width: 640, height: 480), index);

    expect(decision.type, ExistingMediaDecisionType.uncertainIdentity);
    expect(decision.excludesFromDeletedResults, isFalse);
  });

  test('same date alone is uncertain and not excluded', () {
    final time = DateTime.utc(2025, 1, 2);
    final index = ExistingMediaIndex.build(
      records: [record(5)],
      metadata: [metadata(5, dateTaken: time)],
    );

    final decision = engine.evaluate(candidate(takenAt: time), index);

    expect(decision.type, ExistingMediaDecisionType.uncertainIdentity);
  });

  test('strong composite metadata identifies an existing item', () {
    final index = ExistingMediaIndex.build(
      records: [record(6)],
      metadata: [metadata(6)],
    );

    final decision = engine.evaluate(
      candidate(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 4096,
        width: 1200,
        height: 800,
        relativeLocation: 'DCIM/Camera/',
      ),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
  });

  test('matching metadata on another volume does not hide an SD-card copy', () {
    final index = ExistingMediaIndex.build(
      records: [record(60)],
      metadata: [metadata(60, volume: 'external_primary')],
    );

    final decision = engine.evaluate(
      candidate(
        volume: '1234-5678',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 4096,
        width: 1200,
        height: 800,
        relativeLocation: 'DCIM/Camera/',
        classification: RecoveryClassification.possibleCopy,
      ),
      index,
    );

    expect(decision.excludesFromDeletedResults, isFalse);
    expect(decision.type, isNot(ExistingMediaDecisionType.definitelyExisting));
  });

  test(
    'separate thumbnail location is not excluded by its existing original',
    () {
      final index = ExistingMediaIndex.build(
        records: [record(61, name: 'photo.jpg')],
        metadata: [metadata(61)],
      );
      final decision = engine.evaluate(
        candidate(
          volume: 'external_primary',
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          size: 1024,
          width: 256,
          height: 170,
          relativeLocation: 'DCIM/.thumbnails/',
          classification: RecoveryClassification.possibleCopy,
        ),
        index,
      );

      expect(decision.excludesFromDeletedResults, isFalse);
      expect(
        decision.type,
        isNot(ExistingMediaDecisionType.definitelyExisting),
      );
    },
  );

  test('separate same-size copy is not mistaken for the original file', () {
    final index = ExistingMediaIndex.build(
      records: [record(62, name: 'photo.jpg')],
      metadata: [metadata(62)],
    );
    final decision = engine.evaluate(
      candidate(
        volume: 'external_primary',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 4096,
        width: 1200,
        height: 800,
        relativeLocation: 'Pictures/Recovered/',
        classification: RecoveryClassification.possibleCopy,
      ),
      index,
    );

    expect(decision.excludesFromDeletedResults, isFalse);
    expect(decision.type, isNot(ExistingMediaDecisionType.definitelyExisting));
  });

  test('ambiguous strong composite identity remains uncertain', () {
    final index = ExistingMediaIndex.build(
      records: [record(7), record(8)],
      metadata: [metadata(7), metadata(8)],
    );

    final decision = engine.evaluate(
      candidate(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 4096,
        width: 1200,
        height: 800,
        relativeLocation: 'DCIM/Camera/',
      ),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.uncertainIdentity);
    expect(decision.excludesFromDeletedResults, isFalse);
  });

  test('no inventory match does not change candidate into deleted media', () {
    final recoveryCandidate = candidate();
    final index = ExistingMediaIndex.build(records: const []);

    final decision = engine.evaluate(recoveryCandidate, index);

    expect(decision.type, ExistingMediaDecisionType.noExistingMatch);
    expect(
      recoveryCandidate.classification,
      RecoveryClassification.unavailable,
    );
  });

  test('verified trash evidence cannot bypass an exact existing match', () {
    final current = record(9);
    final index = ExistingMediaIndex.build(records: [current]);

    final decision = engine.evaluate(
      candidate(
        uri: current.contentUri,
        classification: RecoveryClassification.verifiedDeleted,
      ),
      index,
    );

    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
    expect(decision.excludesFromDeletedResults, isTrue);
  });

  test('possible-copy classification remains separate', () {
    final possibleCopy = candidate(
      classification: RecoveryClassification.possibleCopy,
    );

    final decision = engine.evaluate(
      possibleCopy,
      ExistingMediaIndex.build(records: const []),
    );

    expect(decision.type, ExistingMediaDecisionType.noExistingMatch);
    expect(possibleCopy.classification, RecoveryClassification.possibleCopy);
  });

  test('unknown metadata is handled safely', () {
    final decision = engine.evaluate(
      candidate(),
      ExistingMediaIndex.build(records: [record(10)]),
    );

    expect(decision.type, ExistingMediaDecisionType.noExistingMatch);
  });

  test(
    'older Android bucket metadata supports conservative composite matching',
    () {
      final index = ExistingMediaIndex.build(
        records: [record(11)],
        metadata: [
          metadata(11, relativePath: null, volume: null, bucketName: 'Camera'),
        ],
      );

      final decision = engine.evaluate(
        candidate(
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          size: 4096,
          width: 1200,
          height: 800,
          bucketName: 'Camera',
        ),
        index,
      );

      expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
    },
  );

  test('large inventory uses reusable indexed lookups', () {
    final records = List.generate(5000, (index) => record(index));
    final index = ExistingMediaIndex.build(records: records);

    final decision = engine.evaluate(
      candidate(uri: records.last.contentUri),
      index,
    );

    expect(index.indexedRecordCount, 5000);
    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
  });

  test('duplicate current inventory records produce one stable identity', () {
    final duplicate = record(12);
    final index = ExistingMediaIndex.build(records: [duplicate, duplicate]);

    final decision = engine.evaluate(
      candidate(uri: duplicate.contentUri),
      index,
    );

    expect(index.indexedRecordCount, 1);
    expect(decision.type, ExistingMediaDecisionType.definitelyExisting);
  });

  test('same MediaStore IDs on different volumes remain distinct', () {
    final index = ExistingMediaIndex.build(
      records: const [
        CurrentMediaRecord(
          mediaStoreId: 12,
          storageVolumeName: 'external_primary',
        ),
        CurrentMediaRecord(mediaStoreId: 12, storageVolumeName: '1234-5678'),
      ],
    );

    expect(index.indexedRecordCount, 2);
    final primary = engine.evaluate(
      candidate(mediaStoreId: 12, volume: 'external_primary'),
      index,
    );
    final removable = engine.evaluate(
      candidate(mediaStoreId: 12, volume: '1234-5678'),
      index,
    );
    expect(primary.type, ExistingMediaDecisionType.definitelyExisting);
    expect(removable.type, ExistingMediaDecisionType.definitelyExisting);
    expect(primary.match?.record.storageVolumeName, 'external_primary');
    expect(removable.match?.record.storageVolumeName, '1234-5678');
  });
}
