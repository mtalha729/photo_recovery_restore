import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield_restore/recovery_shield_restore_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/current_media_inventory/current_media_inventory_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/recovery_shield_restore/platform_recovery_shield_restorer.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const policy = RecoveryShieldRestorePolicy();
  const channel = MethodChannel('test/shield-restore');
  PlatformRecoveryShieldRestorer restorer() =>
      PlatformRecoveryShieldRestorer.withChannel(channel);
  final emptyIndex = ExistingMediaIndex.build(records: const []);

  MediaCandidate candidate({
    MediaSource source = MediaSource.cameraGallery,
    Uri? uri,
    RecoveryClassification classification =
        RecoveryClassification.existingMedia,
  }) => MediaCandidate(
    id: 'original',
    source: source,
    contentUri: uri ?? Uri.parse('content://media/external/images/media/1'),
    displayName: 'photo.jpg',
    classification: classification,
    deletionEvidence: DeletionEvidence(),
    restoreCapability: RestoreCapability.originalFullQuality,
    recoveryQuality: RecoveryQuality.original,
  );

  ProtectedMediaRecord record({
    MediaSource source = MediaSource.cameraGallery,
    String? location,
    String digest = 'abcd',
  }) => ProtectedMediaRecord(
    protectionId: 'shield-1',
    originalSource: source,
    originalContentUri: Uri.parse('content://media/external/images/media/1'),
    displayName: 'photo.jpg',
    mimeType: 'image/jpeg',
    originalLocation: location,
    byteSize: 4,
    protectedCopyLocation: '/private/recovery_shield/copy.bin',
    sha256Digest: digest,
    protectedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  );

  RecoveryShieldRestorePreparation prepare({
    MediaSource source = MediaSource.cameraGallery,
    String? location,
    ExistingMediaIndex? index,
    AuthorizedFolderScope? scope,
    RecoveryClassification classification =
        RecoveryClassification.existingMedia,
  }) => policy.prepare(
    record: record(source: source, location: location),
    originalCandidate: candidate(
      source: source,
      classification: classification,
    ),
    existingMediaIndex: index ?? emptyIndex,
    authorizedDestinationScope: scope,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('valid protected copy restores', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'restored',
            'restoredContentUri': 'content://media/external/images/media/9',
            'usedPendingPublish': true,
          },
        );
    final result = await restorer().restore(prepare().request!);
    expect(result.status, RecoveryShieldRestoreStatus.restored);
    expect(result.restoredContentUri, isNotNull);
  });

  test('stored exact-byte size and digest are sent for verification', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map;
          expect(arguments['expectedByteSize'], 4);
          expect(arguments['sha256Digest'], 'abcd');
          return {
            'status': 'restored',
            'restoredContentUri': 'content://media/item/9',
          };
        });
    await restorer().restore(prepare().request!);
  });

  test('existing original blocks duplicate restore', () {
    final uri = Uri.parse('content://media/external/images/media/1');
    final index = ExistingMediaIndex.build(
      records: [CurrentMediaRecord(mediaStoreId: 1, contentUri: uri)],
    );
    final result = prepare(index: index);
    expect(result.isEligible, isFalse);
    expect(
      result.rejection?.status,
      RecoveryShieldRestoreStatus.alreadyPresent,
    );
  });

  test('missing current match alone does not mean deleted', () {
    final original = candidate(
      classification: RecoveryClassification.unclassified,
    );
    final result = policy.prepare(
      record: record(),
      originalCandidate: original,
      existingMediaIndex: emptyIndex,
    );
    expect(result.isEligible, isTrue);
    expect(original.classification, RecoveryClassification.unclassified);
    expect(original.deletionEvidence.isEmpty, isTrue);
  });

  test('corrupted protected copy fails with integrity state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'integrityFailure'},
        );
    final result = await restorer().restore(prepare().request!);
    expect(result.status, RecoveryShieldRestoreStatus.integrityFailure);
    expect(result.isSuccessful, isFalse);
  });

  test('missing protected copy is structured', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'protectedCopyMissing'},
        );
    expect(
      (await restorer().restore(prepare().request!)).status,
      RecoveryShieldRestoreStatus.protectedCopyMissing,
    );
  });

  test('failed write cleanup never maps to success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'writeFailure',
            'partialDestinationRemoved': true,
          },
        );
    final result = await restorer().restore(prepare().request!);
    expect(result.status, RecoveryShieldRestoreStatus.writeFailure);
    expect(result.restoredContentUri, isNull);
  });

  test('verification failure is not success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'verificationFailure'},
        );
    expect(
      (await restorer().restore(prepare().request!)).isSuccessful,
      isFalse,
    );
  });

  test('API 24-28 missing write access is structured', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'accessRequired'},
        );
    expect(
      (await restorer().restore(prepare().request!)).status,
      RecoveryShieldRestoreStatus.accessRequired,
    );
  });

  test('API 29+ pending publish flow is represented', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'restored',
            'restoredContentUri': 'content://media/item/10',
            'usedPendingPublish': true,
          },
        );
    expect(
      (await restorer().restore(prepare().request!)).usedPendingPublish,
      isTrue,
    );
  });

  test('source-appropriate fallback destinations are selected', () {
    expect(prepare().request?.relativeDestination, 'DCIM/Camera');
    expect(
      prepare(source: MediaSource.screenshots).request?.relativeDestination,
      'Pictures/Screenshots',
    );
    expect(
      prepare(source: MediaSource.downloadsSavedMedia)
          .request
          ?.relativeDestination,
      'Download',
    );
    expect(
      prepare(source: MediaSource.messagingSharedMedia)
          .request
          ?.relativeDestination,
      'Pictures/Photo Recovery & Restore',
    );
  });

  test('safe original path is preferred and unsafe path is rejected', () {
    expect(
      prepare(location: 'DCIM/Vacation/').request?.relativeDestination,
      'DCIM/Vacation',
    );
    expect(
      prepare(location: 'Android/data/private').request?.relativeDestination,
      'DCIM/Camera',
    );
  });

  test('SD and custom sources require an active destination scope', () {
    expect(
      prepare(source: MediaSource.sdCard).rejection?.status,
      RecoveryShieldRestoreStatus.destinationRequired,
    );
    expect(
      prepare(source: MediaSource.customFolder).rejection?.status,
      RecoveryShieldRestoreStatus.destinationRequired,
    );
    final scope = AuthorizedFolderScope(
      treeUri: Uri.parse('content://provider/tree/folder'),
      grantState: FolderGrantState.active,
    );
    expect(
      prepare(
        source: MediaSource.sdCard,
        scope: scope,
      ).request?.authorizedDestinationScope,
      same(scope),
    );
  });

  test('source domain and classification never change', () async {
    final original = candidate(
      source: MediaSource.messagingSharedMedia,
      classification: RecoveryClassification.possibleCopy,
    );
    final preparation = policy.prepare(
      record: record(source: MediaSource.messagingSharedMedia),
      originalCandidate: original,
      existingMediaIndex: emptyIndex,
    );
    expect(preparation.isEligible, isTrue);
    expect(original.source, MediaSource.messagingSharedMedia);
    expect(original.classification, RecoveryClassification.possibleCopy);
  });

  test(
    'batch is sequential and prevents duplicate same-item restore',
    () async {
      var active = 0;
      var maxActive = 0;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            active++;
            maxActive = active > maxActive ? active : maxActive;
            await Future<void>.delayed(Duration.zero);
            active--;
            calls++;
            return calls == 1
                ? {
                    'status': 'restored',
                    'restoredContentUri': 'content://media/item/1',
                  }
                : {'status': 'writeFailure'};
          });
      final result = await restorer().restoreBatch([prepare(), prepare()]);
      expect(maxActive, 1);
      expect(result.items.map((item) => item.status), [
        RecoveryShieldRestoreStatus.restored,
        RecoveryShieldRestoreStatus.alreadyPresent,
      ]);
    },
  );

  test('rejected batch item does not affect another restore', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'restored',
            'restoredContentUri': 'content://media/item/2',
          },
        );
    final rejected = RecoveryShieldRestorePreparation.rejected(
      const RecoveryShieldRestoreResult(
        protectionId: 'blocked',
        status: RecoveryShieldRestoreStatus.alreadyPresent,
      ),
    );
    final result = await restorer().restoreBatch([rejected, prepare()]);
    expect(result.items.map((item) => item.status), [
      RecoveryShieldRestoreStatus.alreadyPresent,
      RecoveryShieldRestoreStatus.restored,
    ]);
  });

  test('restore channel contains no bitmap or recompression payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final keys = (call.arguments as Map).keys;
          expect(keys, isNot(contains('bitmap')));
          expect(keys, isNot(contains('imageBytes')));
          expect(keys, isNot(contains('thumbnail')));
          return {
            'status': 'restored',
            'restoredContentUri': 'content://media/item/3',
          };
        });
    await restorer().restore(prepare().request!);
  });
}
