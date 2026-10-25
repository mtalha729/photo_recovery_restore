import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/current_photo_discovery/current_photo_candidate_mapper.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';

void main() {
  const mapper = CurrentPhotoCandidateMapper();

  test(
    'messaging stickers remain existing photos with genuine source metadata',
    () {
      final photo = mapper.map(
        CurrentMediaRecord(
          mediaStoreId: 9,
          contentUri: Uri.parse('content://media/external/images/media/9'),
          bucketName: 'WhatsApp Stickers',
          displayName: 'sticker.webp',
          mimeType: 'image/webp',
        ),
      )!;
      expect(photo.source, MediaSource.messagingSharedMedia);
      expect(photo.classification, RecoveryClassification.existingMedia);
      expect(photo.bucketName, 'WhatsApp Stickers');
      expect(photo.mimeType, 'image/webp');
    },
  );

  test(
    'volume-qualified MediaStore records preserve removable storage identity',
    () {
      final photo = mapper.map(
        CurrentMediaRecord(
          mediaStoreId: 10,
          contentUri: Uri.parse('content://media/1234-5678/images/media/10'),
          storageVolumeName: '1234-5678',
          relativePath: 'Pictures/',
        ),
      )!;
      expect(photo.source, MediaSource.sdCard);
      expect(photo.isRemovableStorage, isTrue);
      expect(photo.storageVolumeName, '1234-5678');
    },
  );

  test(
    'record without a readable content URI is not offered for Save Copy',
    () {
      expect(mapper.map(const CurrentMediaRecord(mediaStoreId: 11)), isNull);
    },
  );

  test('indexed hidden thumbnails retain their actual evidence', () {
    final photo = mapper.map(
      CurrentMediaRecord(
        mediaStoreId: 12,
        contentUri: Uri.parse('content://media/external/images/media/12'),
        relativePath: 'Pictures/.thumbnails/',
      ),
    )!;
    expect(photo.discoveryEvidence.isHidden, isTrue);
    expect(photo.discoveryEvidence.isThumbnailLike, isTrue);
    expect(photo.discoveryEvidence.isCacheLike, isTrue);
    expect(photo.classification, RecoveryClassification.existingMedia);
  });
}
