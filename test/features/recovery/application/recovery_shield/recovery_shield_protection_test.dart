import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_protection_policy.dart';
import 'package:photo_recovery_restore/features/recovery/data/recovery_shield/platform_recovery_shield_storage.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery/domain/verified_content_digest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const policy = RecoveryShieldProtectionPolicy();
  const channel = MethodChannel('test/recovery-shield');
  PlatformRecoveryShieldStorage storage() =>
      PlatformRecoveryShieldStorage.withChannel(channel);

  MediaCandidate candidate({
    String id = 'candidate-1',
    MediaSource source = MediaSource.cameraGallery,
    Uri? uri,
    String? name = 'photo.jpg',
    int? byteSize = 4,
    VerifiedContentDigest? digest,
  }) => MediaCandidate(
    id: id,
    source: source,
    contentUri: uri ?? Uri.parse('content://media/external/images/media/1'),
    displayName: name,
    mimeType: 'image/jpeg',
    relativeLocation: 'DCIM/Camera/',
    byteSize: byteSize,
    width: 100,
    height: 80,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    verifiedContentDigest: digest,
    classification: RecoveryClassification.existingMedia,
    deletionEvidence: DeletionEvidence(),
    restoreCapability: RestoreCapability.originalFullQuality,
    recoveryQuality: RecoveryQuality.original,
  );

  RecoveryShieldProtectionRequest request({MediaCandidate? value}) =>
      policy.createRequest(
        protectionId: 'shield-1',
        candidate: value ?? candidate(),
      )!;

  Map<String, Object?> success(String status) => {
    'status': status,
    'protectedCopyLocation': '/private/recovery_shield/item.bin',
    'sha256Digest': 'abcd',
    'byteSize': 4,
    'protectedAtMillis': 2000,
  };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('successful protection returns verified protected record', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => success('protected'));
    final result = await storage().protect(request());
    expect(result.status, RecoveryShieldProtectionStatus.protected);
    expect(result.isSuccessful, isTrue);
    expect(result.record?.sha256Digest, 'abcd');
    expect(result.record?.byteSize, 4);
  });

  test('exact-byte and digest fields are required for success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'protected', 'byteSize': 4},
        );
    final result = await storage().protect(request());
    expect(result.status, RecoveryShieldProtectionStatus.platformFailure);
    expect(result.record, isNull);
  });

  test('existing media remains existing after protection', () async {
    final original = candidate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => success('protected'));
    await storage().protect(request(value: original));
    expect(original.classification, RecoveryClassification.existingMedia);
  });

  test('protection alone never creates deletion evidence', () async {
    final original = candidate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => success('protected'));
    await storage().protect(request(value: original));
    expect(original.deletionEvidence.isEmpty, isTrue);
    expect(original.isDeletedRecoveryResult, isFalse);
  });

  test(
    'already-protected state does not create another logical record',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => success('alreadyProtected'),
          );
      final result = await storage().protect(request());
      expect(result.status, RecoveryShieldProtectionStatus.alreadyProtected);
      expect(result.record?.protectionId, 'shield-1');
    },
  );

  test('failed update preserves previous valid record', () {
    final old = ProtectedMediaRecord(
      protectionId: 'shield-1',
      originalSource: MediaSource.cameraGallery,
      protectedCopyLocation: '/private/old.bin',
      sha256Digest: 'old',
      protectedAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      byteSize: 10,
    );
    final state = RecoveryShieldProtectionState(records: [old]);
    state.apply(
      const RecoveryShieldProtectionResult(
        protectionId: 'shield-1',
        status: RecoveryShieldProtectionStatus.integrityFailure,
      ),
    );
    expect(state.recordFor('shield-1'), same(old));
  });

  test('verified update replaces state only after success', () {
    final state = RecoveryShieldProtectionState();
    final updated = ProtectedMediaRecord(
      protectionId: 'shield-1',
      originalSource: MediaSource.cameraGallery,
      protectedCopyLocation: '/private/new.bin',
      sha256Digest: 'new',
      protectedAt: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
      byteSize: 20,
    );
    state.apply(
      RecoveryShieldProtectionResult(
        protectionId: 'shield-1',
        status: RecoveryShieldProtectionStatus.updated,
        record: updated,
      ),
    );
    expect(state.recordFor('shield-1'), same(updated));
  });

  test('integrity failure is structured and has no published record', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'integrityFailure'},
        );
    final result = await storage().protect(request());
    expect(result.status, RecoveryShieldProtectionStatus.integrityFailure);
    expect(result.record, isNull);
  });

  test('insufficient storage is structured', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'insufficientStorage'},
        );
    expect(
      (await storage().protect(request())).status,
      RecoveryShieldProtectionStatus.insufficientStorage,
    );
  });

  test('source and access failures remain distinct', () async {
    var status = 'sourceUnavailable';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {'status': status});
    expect(
      (await storage().protect(request())).status,
      RecoveryShieldProtectionStatus.sourceUnavailable,
    );
    status = 'accessFailure';
    expect(
      (await storage().protect(request())).status,
      RecoveryShieldProtectionStatus.accessFailure,
    );
  });

  test('batch is sequential and preserves individual results', () async {
    var active = 0;
    var maximumActive = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          active++;
          maximumActive = active > maximumActive ? active : maximumActive;
          await Future<void>.delayed(Duration.zero);
          active--;
          final id = (call.arguments as Map)['protectionId'];
          return id == 'shield-1'
              ? success('protected')
              : {'status': 'sourceUnavailable'};
        });
    final second = policy.createRequest(
      protectionId: 'shield-2',
      candidate: candidate(id: 'candidate-2'),
    )!;
    final result = await storage().protectBatch([request(), second]);
    expect(maximumActive, 1);
    expect(result.items.map((item) => item.status), [
      RecoveryShieldProtectionStatus.protected,
      RecoveryShieldProtectionStatus.sourceUnavailable,
    ]);
  });

  test('source domain is preserved in metadata', () async {
    final original = candidate(source: MediaSource.messagingSharedMedia);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect((call.arguments as Map)['source'], 'messagingSharedMedia');
          return success('protected');
        });
    final result = await storage().protect(request(value: original));
    expect(result.record?.originalSource, MediaSource.messagingSharedMedia);
    expect(original.source, MediaSource.messagingSharedMedia);
  });

  test('filename alone cannot establish stable protection identity', () {
    final weak = MediaCandidate(
      id: 'weak',
      source: MediaSource.cameraGallery,
      displayName: 'same.jpg',
      classification: RecoveryClassification.existingMedia,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.originalFullQuality,
      recoveryQuality: RecoveryQuality.original,
    );
    expect(
      policy.createRequest(protectionId: 'shield', candidate: weak),
      isNull,
    );
  });

  test('SHA-256 expectation is passed only when explicitly verified', () async {
    final original = candidate(
      digest: VerifiedContentDigest(algorithm: 'sha-256', value: 'ABCD'),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect((call.arguments as Map)['expectedSha256'], 'abcd');
          return success('protected');
        });
    await storage().protect(request(value: original));
  });

  test(
    'deterministic request contains no bitmap or recompression payload',
    () async {
      final first = request();
      final second = request();
      expect(first.stableSourceIdentity, second.stableSourceIdentity);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final arguments = call.arguments as Map;
            expect(arguments.keys, isNot(contains('bitmap')));
            expect(arguments.keys, isNot(contains('thumbnail')));
            expect(arguments.keys, isNot(contains('imageBytes')));
            return success('protected');
          });
      await storage().protect(first);
    },
  );
}
