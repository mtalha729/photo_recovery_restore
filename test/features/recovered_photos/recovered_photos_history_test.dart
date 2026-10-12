import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovered_photos/application/recovered_photos_store.dart';
import 'package:photo_recovery_restore/features/recovered_photos/presentation/recovered_photos_screen.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
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
  test('confirmed system-trash URI is recorded once and survives reload', () async {
    final store = _Store();
    final candidate = _candidate();
    final outcome = await RestoreUxCoordinator(
      systemTrashExecutor: _SystemExecutor(candidate.contentUri!),
      historyStore: store,
      clock: () => DateTime.fromMillisecondsSinceEpoch(100),
    ).restore([_systemItem(candidate)]);

    expect(outcome.items.single.restoredContentUri, candidate.contentUri);
    expect((await store.load()).single.contentUri, candidate.contentUri);

    await RestoreUxCoordinator(
      systemTrashExecutor: _SystemExecutor(candidate.contentUri!),
      historyStore: store,
      clock: () => DateTime.fromMillisecondsSinceEpoch(200),
    ).restore([_systemItem(candidate)]);
    final reloaded = await store.load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.restoredAt.millisecondsSinceEpoch, 200);
  });

  test('unconfirmed, cancelled, and failed restore results create no history', () async {
    final store = _Store();
    final candidate = _candidate();
    for (final result in [
      const SystemTrashRestoreResult(status: SystemTrashRestoreStatus.userDeniedOrCancelled),
      const SystemTrashRestoreResult(status: SystemTrashRestoreStatus.accessFailure),
      const SystemTrashRestoreResult(status: SystemTrashRestoreStatus.restored),
    ]) {
      final outcome = await RestoreUxCoordinator(
        systemTrashExecutor: _ResultExecutor(result),
        historyStore: store,
      ).restore([_systemItem(candidate)]);
      expect(outcome.items.single.status, isNot(RestoreOutcomeStatus.restored));
    }
    expect(await store.load(), isEmpty);
  });

  testWidgets('history screen has a safe empty state and handles stored URI', (tester) async {
    final store = _Store();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: RecoveredPhotosScreen(key: UniqueKey(), store: store)));
    await tester.pumpAndSettle();
    expect(find.text('No restored photos yet'), findsOneWidget);

    await store.upsert(RecoveredPhotoRecord.fromCandidate(
      contentUri: Uri.parse('content://media/restored/1'), candidate: _candidate(), restoredAt: DateTime.now(),
    ));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: RecoveredPhotosScreen(key: UniqueKey(), store: store)));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Store implements RecoveredPhotosStore {
  final Map<String, RecoveredPhotoRecord> _records = {};
  @override Future<List<RecoveredPhotoRecord>> load() async => _records.values.toList();
  @override Future<void> upsert(RecoveredPhotoRecord record) async => _records[record.contentUri.toString()] = record;
}
class _SystemExecutor implements SystemTrashRestoreExecutor { _SystemExecutor(this.uri); final Uri uri; @override Future<SystemTrashRestoreResult> restoreBatch(SystemTrashRestoreBatch batch) async => SystemTrashRestoreResult(status: SystemTrashRestoreStatus.restored, affectedUris: [uri]); }
class _ResultExecutor implements SystemTrashRestoreExecutor { _ResultExecutor(this.result); final SystemTrashRestoreResult result; @override Future<SystemTrashRestoreResult> restoreBatch(SystemTrashRestoreBatch batch) async => result; }
RestoreReviewItem _systemItem(MediaCandidate candidate) => RestoreReviewItem(candidate: candidate, route: RestoreRoute.systemTrash, systemRequest: SystemTrashRestoreRequest(requestId: candidate.id, candidate: candidate, classificationDecision: RecoveryClassificationDecision(classification: candidate.classification, reason: RecoveryClassificationReason.verifiedSystemTrashEvidence, deletionEvidence: const [DeletionEvidenceReason.systemTrashRecord])));
MediaCandidate _candidate() => MediaCandidate(id: 'photo', source: MediaSource.cameraGallery, contentUri: Uri.parse('content://media/restored/1'), displayName: 'photo.jpg', mimeType: 'image/jpeg', classification: RecoveryClassification.verifiedDeleted, deletionEvidence: DeletionEvidence(reasons: const [DeletionEvidenceReason.systemTrashRecord]), restoreCapability: RestoreCapability.originalFullQuality, recoveryQuality: RecoveryQuality.original);