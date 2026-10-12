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
