import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/restore/platform_system_trash_restore.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/presentation/recovery_thumbnail.dart';
import 'package:photo_recovery_restore/features/restore_ux/application/restore_ux_coordinator.dart';
import 'package:photo_recovery_restore/features/restore_ux/application/restore_ux_models.dart';
import 'package:photo_recovery_restore/features/restore_ux/presentation/photo_detail_screen.dart';

void main() {
  testWidgets('photo detail prioritizes the image and Restore Photo action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PhotoDetailScreen(
          item: _item(
            _candidate(
              relativeLocation: 'DCIM/Camera',
              width: 3000,
              height: 2000,
              byteSize: 2048,
            ),
          ),
          coordinator: RestoreUxCoordinator(systemTrashExecutor: _Executor()),
        ),
      ),
    );

    expect(find.byType(RecoveryThumbnail), findsOneWidget);
    expect(find.bySemanticsLabel('Preview of photo.jpg'), findsOneWidget);
    expect(find.text('Restore Photo'), findsOneWidget);
    expect(find.text('DCIM/Camera'), findsOneWidget);
    expect(
      find.text('Camera & Gallery · 3000 × 2000 · 2.0 KB'),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Verified deleted photo'), findsOneWidget);
    expect(find.text('Review restore'), findsNothing);
  });

  testWidgets('restore button disables while restoration is in progress', (
    tester,
  ) async {
    final pending = Completer<SystemTrashRestoreResult>();
    await tester.pumpWidget(
      _app(
        PhotoDetailScreen(
          item: _item(_candidate()),
          coordinator: RestoreUxCoordinator(
            systemTrashExecutor: _Executor(pending: pending),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Restore Photo'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(
      const SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.accessFailure,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('successful restore shows a message and pops to origin', (
    tester,
  ) async {
    await tester.pumpWidget(_routeApp(_Executor()));
    await tester.tap(find.text('Open Camera & Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Open Camera & Gallery'), findsOneWidget);
    expect(find.byType(PhotoDetailScreen), findsNothing);
    expect(find.text('Photo restored successfully.'), findsOneWidget);
  });

  testWidgets('restore failure stays on detail and does not claim success', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PhotoDetailScreen(
          item: _item(_candidate()),
          coordinator: RestoreUxCoordinator(
            systemTrashExecutor: _Executor(
              result: const SystemTrashRestoreResult(
                status: SystemTrashRestoreStatus.accessFailure,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Restore Photo'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoDetailScreen), findsOneWidget);
    expect(
      find.text('Storage access is needed to save this copy.'),
      findsOneWidget,
    );
    expect(find.text('Photo restored successfully.'), findsNothing);
    expect(find.text('Restore Photo'), findsOneWidget);
  });

  testWidgets('rapid restore taps create only one restore request', (
    tester,
  ) async {
    final pending = Completer<SystemTrashRestoreResult>();
    final executor = _Executor(pending: pending);
    await tester.pumpWidget(
      _app(
        PhotoDetailScreen(
          item: _item(_candidate()),
          coordinator: RestoreUxCoordinator(systemTrashExecutor: executor),
        ),
      ),
    );

    await tester.tap(find.text('Restore Photo'));
    await tester.tap(find.text('Restore Photo'));
    await tester.pump();
    expect(executor.calls, 1);

    pending.complete(
      const SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.accessFailure,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'restore review confirmation is wired to the restore coordinator',
    (tester) async {
      final executor = _Executor();
      await tester.pumpWidget(
        _app(
          RestoreReviewSheet(
            items: [_item(_candidate())],
            coordinator: RestoreUxCoordinator(systemTrashExecutor: executor),
          ),
        ),
      );

      await tester.tap(find.text('Confirm restore'));
      await tester.pumpAndSettle();

      expect(executor.calls, 1);
      expect(find.text('1 selected · 1 restored from trash'), findsOneWidget);
    },
  );

  testWidgets('detail remains safe at narrow and wide layouts', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(360, 800), const Size(1100, 800)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _app(
          PhotoDetailScreen(
            item: _item(_candidate(width: 3000, height: 2000)),
            coordinator: RestoreUxCoordinator(systemTrashExecutor: _Executor()),
          ),
          dark: size.width > 1000,
          textScale: size.width < 400 ? 1.6 : 1,
        ),
      );
      expect(tester.takeException(), isNull);
      final thumbnail = tester.widget<RecoveryThumbnail>(
        find.byType(RecoveryThumbnail),
      );
      expect(thumbnail.requestedDimension, lessThanOrEqualTo(512));
    }
  });

  test('one stale trash item does not block the next item', () async {
    final executor = _Executor(staleFirst: true);
    final result = await RestoreUxCoordinator(systemTrashExecutor: executor)
        .restore([_item(_candidate()), _item(_candidate(id: 'second'))]);
    expect(executor.calls, 2);
    expect(result.count(RestoreOutcomeStatus.staleOrMissing), 1);
    expect(result.count(RestoreOutcomeStatus.restored), 1);
  });
}

class _Executor implements SystemTrashRestoreExecutor {
  _Executor({this.result, this.pending, this.staleFirst = false});

  final SystemTrashRestoreResult? result;
  final Completer<SystemTrashRestoreResult>? pending;
  final bool staleFirst;
  int calls = 0;

  @override
  Future<SystemTrashRestoreResult> restoreBatch(
    SystemTrashRestoreBatch batch,
  ) async {
    calls++;
    if (staleFirst && calls == 1) {
      return const SystemTrashRestoreResult(
        status: SystemTrashRestoreStatus.staleOrMissingMediaItem,
      );
    }
    return pending?.future ??
        result ??
        SystemTrashRestoreResult(
          status: SystemTrashRestoreStatus.restored,
          affectedUris: batch.contentUris,
        );
  }
}

Widget _routeApp(_Executor executor) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => PhotoDetailScreen(
                item: _item(_candidate()),
                coordinator: RestoreUxCoordinator(
                  systemTrashExecutor: executor,
                ),
              ),
            ),
          ),
          child: const Text('Open Camera & Gallery'),
        ),
      ),
    ),
  ),
);

Widget _app(Widget home, {bool dark = false, double textScale = 1}) =>
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

RestoreReviewItem _item(MediaCandidate candidate) => RestoreReviewItem(
  candidate: candidate,
  route: RestoreRoute.systemTrash,
  systemRequest: SystemTrashRestoreRequest(
    requestId: candidate.id,
    candidate: candidate,
    classificationDecision: RecoveryClassificationDecision(
      classification: candidate.classification,
      reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
      deletionEvidence: const [DeletionEvidenceReason.systemTrashRecord],
    ),
  ),
);

MediaCandidate _candidate({
  String id = 'photo',
  String? relativeLocation,
  int? width,
  int? height,
  int? byteSize,
}) => MediaCandidate(
  id: id,
  source: MediaSource.cameraGallery,
  contentUri: Uri.parse('content://media/$id'),
  displayName: 'photo.jpg',
  relativeLocation: relativeLocation,
  width: width,
  height: height,
  byteSize: byteSize,
  classification: RecoveryClassification.verifiedDeleted,
  deletionEvidence: DeletionEvidence(
    reasons: const [DeletionEvidenceReason.systemTrashRecord],
  ),
  restoreCapability: RestoreCapability.originalFullQuality,
  recoveryQuality: RecoveryQuality.original,
);
