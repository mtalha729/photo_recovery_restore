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

  tearDown(() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

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

  test('file-copy route is executed only by explicit restore', () async {
    final restorer = _FileRestorer();
    final outcome = await RestoreUxCoordinator(
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
  });
}

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
  int calls = 0;
  @override
  Future<FileCopyRestoreResult> restore(FileCopyRestoreRequest request) async {
    calls++;
    return const FileCopyRestoreResult(FileCopyRestoreStatus.restored);
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
