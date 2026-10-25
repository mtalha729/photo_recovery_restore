import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/restore/file_copy_restorer.dart';
import 'package:photo_recovery_restore/features/recovery/data/restore/platform_system_trash_restore.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/restore_ux/application/restore_ux_coordinator.dart';
import 'package:photo_recovery_restore/features/restore_ux/application/restore_ux_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('file-copy-test');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('platform file-copy restore preserves structured success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'restoreFileCopy');
          expect((call.arguments as Map)['filePath'], '/storage/a.jpg');
          return {
            'status': 'restored',
            'destinationUri': 'content://media/external/images/media/7',
          };
        });
    final result = await const PlatformFileCopyRestorer.withChannel(channel)
        .restore(FileCopyRestoreRequest(candidate: _candidate));
    expect(result.status, FileCopyRestoreStatus.restored);
    expect(
      result.destinationUri.toString(),
      'content://media/external/images/media/7',
    );
  });

  test(
    'SAF document restores send the user-selected content URI only',
    () async {
      final documentUri = Uri.parse(
        'content://provider/tree/primary%3APictures/document/primary%3APictures%2Fcopy.jpg',
      );
      final candidate = MediaCandidate(
        id: 'saf:$documentUri',
        source: MediaSource.unknown,
        documentUri: documentUri,
        displayName: 'copy.jpg',
        mimeType: 'image/jpeg',
        classification: RecoveryClassification.possibleCopy,
        deletionEvidence: DeletionEvidence(),
        restoreCapability: RestoreCapability.unknownQualityCopy,
        recoveryQuality: RecoveryQuality.unknownQualityCopy,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'restoreFileCopy');
            final arguments = call.arguments! as Map;
            expect(arguments['sourceUri'], documentUri.toString());
            expect(arguments.containsKey('filePath'), isFalse);
            return {
              'status': 'restored',
              'destinationUri': 'content://media/external/images/media/8',
            };
          });

      final result = await const PlatformFileCopyRestorer.withChannel(channel)
          .restore(FileCopyRestoreRequest(candidate: candidate));

      expect(result.status, FileCopyRestoreStatus.restored);
      expect(
        result.destinationUri.toString(),
        'content://media/external/images/media/8',
      );
    },
  );

  test(
    'existing MediaStore photo uses its content URI for Save a copy',
    () async {
      final mediaUri = Uri.parse('content://media/external/images/media/42');
      final candidate = MediaCandidate(
        id: 'current:42',
        source: MediaSource.cameraGallery,
        contentUri: mediaUri,
        displayName: 'existing.jpg',
        classification: RecoveryClassification.existingMedia,
        deletionEvidence: DeletionEvidence(),
        restoreCapability: RestoreCapability.alternateFullQualityCopy,
        recoveryQuality: RecoveryQuality.original,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect((call.arguments as Map)['sourceUri'], mediaUri.toString());
            return {
              'status': 'restored',
              'destinationUri': 'content://media/external/images/media/43',
            };
          });

      final result = await const PlatformFileCopyRestorer.withChannel(channel)
          .restore(FileCopyRestoreRequest(candidate: candidate));
      expect(result.status, FileCopyRestoreStatus.restored);
    },
  );

  test('large source copy never sends bounded preview bytes', () async {
    final original = MediaCandidate(
      id: 'large-original',
      source: MediaSource.cameraGallery,
      contentUri: Uri.parse('content://media/external/images/media/88'),
      displayName: 'large.jpg',
      byteSize: 8000000,
      width: 4000,
      height: 3000,
      classification: RecoveryClassification.existingMedia,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.alternateFullQualityCopy,
      recoveryQuality: RecoveryQuality.original,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments! as Map;
          expect(args['sourceUri'], original.contentUri.toString());
          expect(args['expectedSize'], 8000000);
          expect(args.containsKey('bytes'), isFalse);
          expect(args.containsKey('preview'), isFalse);
          return {
            'status': 'restored',
            'destinationUri': 'content://media/external/images/media/89',
          };
        });
    final result = await const PlatformFileCopyRestorer.withChannel(channel)
        .restore(FileCopyRestoreRequest(candidate: original));
    expect(result.status, FileCopyRestoreStatus.restored);
  });

  test('file-copy route is executed only by explicit restore', () async {
    final restorer = _FileRestorer();
    final outcome =
        await RestoreUxCoordinator(
          systemTrashExecutor: _SystemExecutor(),
          fileCopyRestorer: restorer,
        ).restore([
          RestoreReviewItem(
            candidate: _candidate,
            route: RestoreRoute.fileCopy,
            fileCopyRequest: FileCopyRestoreRequest(candidate: _candidate),
          ),
        ]);
    expect(restorer.calls, 1);
    expect(outcome.items.single.status, RestoreOutcomeStatus.restored);
    expect(outcome.items.single.savedKind, RestoreSavedKind.recoverableCopy);
  });

  test('copy success without an output URI is not reported as saved', () async {
    final restorer = _FileRestorer(withoutUri: true);
    final outcome = await RestoreUxCoordinator(
      systemTrashExecutor: _SystemExecutor(),
      fileCopyRestorer: restorer,
    ).restore([_copyItem(_candidate)]);
    expect(
      outcome.items.single.status,
      RestoreOutcomeStatus.verificationFailure,
    );
  });

  test('batch skips duplicate sources and preserves other successes', () async {
    final restorer = _FileRestorer();
    final coordinator = RestoreUxCoordinator(
      systemTrashExecutor: _SystemExecutor(),
      fileCopyRestorer: restorer,
    );
    final missing = MediaCandidate(
      id: 'missing',
      source: MediaSource.unknown,
      classification: RecoveryClassification.possibleCopy,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.unknownQualityCopy,
      recoveryQuality: RecoveryQuality.unknownQualityCopy,
    );
    final outcome = await coordinator.restore([
      _copyItem(_candidate),
      _copyItem(_candidate),
      RestoreReviewItem(candidate: missing, route: RestoreRoute.unavailable),
    ]);
    expect(restorer.calls, 1);
    expect(outcome.count(RestoreOutcomeStatus.restored), 1);
    expect(outcome.count(RestoreOutcomeStatus.skippedDuplicate), 1);
    expect(outcome.count(RestoreOutcomeStatus.notEligible), 1);
  });

  test('batch cancellation stops before the next item', () async {
    final token = RestoreCancellationToken();
    final restorer = _FileRestorer();
    final coordinator = RestoreUxCoordinator(
      systemTrashExecutor: _SystemExecutor(),
      fileCopyRestorer: restorer,
    );
    final outcome = await coordinator.restore(
      [
        _copyItem(_candidate),
        _copyItem(
          MediaCandidate(
            id: 'second',
            source: MediaSource.unknown,
            filePath: '/storage/b.jpg',
            classification: RecoveryClassification.possibleCopy,
            deletionEvidence: DeletionEvidence(),
            restoreCapability: RestoreCapability.unknownQualityCopy,
            recoveryQuality: RecoveryQuality.unknownQualityCopy,
          ),
        ),
      ],
      cancellation: token,
      onProgress: (completed, _) {
        if (completed == 1) token.cancel();
      },
    );
    expect(restorer.calls, 1);
    expect(outcome.count(RestoreOutcomeStatus.restored), 1);
    expect(outcome.count(RestoreOutcomeStatus.cancelled), 1);
  });
}

RestoreReviewItem _copyItem(MediaCandidate candidate) => RestoreReviewItem(
  candidate: candidate,
  route: RestoreRoute.fileCopy,
  fileCopyRequest: FileCopyRestoreRequest(candidate: candidate),
);

final _candidate = MediaCandidate(
  id: 'file:/storage/a.jpg',
  source: MediaSource.unknown,
  filePath: '/storage/a.jpg',
  displayName: 'a.jpg',
  mimeType: 'image/jpeg',
  byteSize: 3,
  classification: RecoveryClassification.possibleCopy,
  deletionEvidence: DeletionEvidence(),
  restoreCapability: RestoreCapability.alternateFullQualityCopy,
  recoveryQuality: RecoveryQuality.completeCopy,
);

class _FileRestorer implements FileCopyRestorer {
  _FileRestorer({this.withoutUri = false});
  final bool withoutUri;
  int calls = 0;
  @override
  Future<FileCopyRestoreResult> restore(FileCopyRestoreRequest request) async {
    calls++;
    return FileCopyRestoreResult(
      FileCopyRestoreStatus.restored,
      destinationUri: withoutUri
          ? null
          : Uri.parse('content://media/external/images/media/$calls'),
    );
  }
}

class _SystemExecutor implements SystemTrashRestoreExecutor {
  @override
  Future<SystemTrashRestoreResult> restoreBatch(
    SystemTrashRestoreBatch batch,
  ) async => const SystemTrashRestoreResult(
    status: SystemTrashRestoreStatus.platformFailure,
  );
}
