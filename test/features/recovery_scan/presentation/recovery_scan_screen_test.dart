import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/recovery_image_memory_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_controller.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_models.dart';
import 'package:photo_recovery_restore/features/recovery_scan/application/recovery_scan_page_source.dart';
import 'package:photo_recovery_restore/features/recovery_scan/presentation/recovery_scan_screen.dart';
import 'package:photo_recovery_restore/features/recovery_scan/presentation/recovery_thumbnail.dart';
import 'package:photo_recovery_restore/features/restore_ux/application/restore_ux_models.dart';

void main() {
  testWidgets('scan shows real counters without a percentage', (tester) async {
    final source = _PendingSource();
    await tester.pumpWidget(_app(_controller(source)));
    await tester.pump();
    expect(find.text('Scanning your photos'), findsOneWidget);
    expect(find.text('Camera & Gallery'), findsWidgets);
    expect(find.text('0 photos checked'), findsOneWidget);
    expect(find.text('0 possible recoveries'), findsOneWidget);
    expect(find.text('0 verified deleted'), findsOneWidget);
    expect(find.textContaining('MediaStore'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    source.complete(_success(const []));
    await tester.pumpAndSettle();
  });

  testWidgets('verified results support accessible multi-selection only', (
    tester,
  ) async {
    var restoreCalls = 0;
    final candidates = [_candidate('one'), _candidate('two')];
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: _ImmediateSource(_success(candidates.map(_item).toList())),
    );
    await tester.pumpWidget(_app(controller, onRestore: (_) => restoreCalls++));
    await tester.pumpAndSettle();

    expect(find.text('Verified Deleted  2'), findsOneWidget);
    expect(restoreCalls, 0);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('Restore selected (2)'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Restore selected (2)'), findsNothing);
    expect(restoreCalls, 0);
  });

  testWidgets('selected items open restore review without restoring', (
    tester,
  ) async {
    List<RestoreReviewItem>? reviewItems;
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: _ImmediateSource(_success([_item(_candidate('one'))])),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RecoveryScanScreen(
          controller: controller,
          onRestoreReview: (items) => reviewItems = items,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.tap(find.text('Restore selected (1)'));
    expect(reviewItems, hasLength(1));
    expect(reviewItems!.single.route, RestoreRoute.systemTrash);
  });

  testWidgets('possible copies remain separately counted and labelled', (
    tester,
  ) async {
    final possible = MediaCandidate(
      id: 'copy',
      source: MediaSource.cameraGallery,
      displayName: 'alternate.jpg',
      classification: RecoveryClassification.possibleCopy,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.lowerResolutionCopy,
      recoveryQuality: RecoveryQuality.reducedResolutionCopy,
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: _ImmediateSource(_success([_item(_candidate('one'))])),
      possibleCopies: [possible],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Verified Deleted  1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Recoverable Copies'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Recoverable Copies'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Camera & Gallery, 2 photos'));
    await tester.pumpAndSettle();
    expect(find.text('Possible copies  1'), findsOneWidget);
    expect(find.text('Verified Deleted  2'), findsNothing);
  });

  testWidgets('results group each source once and hide empty source sections', (
    tester,
  ) async {
    final copy = MediaCandidate(
      id: 'unknown-copy',
      source: MediaSource.unknown,
      displayName: 'unknown.jpg',
      classification: RecoveryClassification.possibleCopy,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.lowerResolutionCopy,
      recoveryQuality: RecoveryQuality.reducedResolutionCopy,
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: _ImmediateSource(
        _success([
          _item(_candidate('camera', source: MediaSource.cameraGallery)),
          _item(
            _candidate('message', source: MediaSource.messagingSharedMedia),
          ),
        ]),
      ),
      possibleCopies: [copy],
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('Verified Deleted  2'), findsOneWidget);
    expect(find.textContaining('Recoverable Copies'), findsOneWidget);
    expect(find.text('Camera & Gallery'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Messaging'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Messaging'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Unknown'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('empty and access states render truthfully', (tester) async {
    await tester.pumpWidget(
      _app(
        RecoveryScanController(
          source: RecoveryScanSource.messaging,
          pageSource: _ImmediateSource(
            _success(const [], source: MediaSource.messagingSharedMedia),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No recoverable photos found'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        RecoveryScanController(
          source: RecoveryScanSource.messaging,
          pageSource: _ImmediateSource(
            const VerifiedSourceRecoveryFailure(
              source: MediaSource.messagingSharedMedia,
              code: VerifiedSourceRecoveryFailureCode.accessUnavailable,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Media access required'), findsOneWidget);
  });

  testWidgets('result grid adapts between narrow and wide layouts', (
    tester,
  ) async {
    Future<void> pumpAt(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _app(
          RecoveryScanController(
            source: RecoveryScanSource.cameraGallery,
            pageSource: _ImmediateSource(
              _success([
                _item(_candidate('one')),
                _item(_candidate('two')),
                _item(_candidate('three')),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpAt(const Size(360, 800));
    await tester.tap(find.text('Camera & Gallery').last);
    await tester.pumpAndSettle();
    final narrow = tester.getSize(find.byType(RecoveryThumbnail).first).width;
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpAt(const Size(1100, 800));
    await tester.tap(find.text('Camera & Gallery').last);
    await tester.pumpAndSettle();
    final wide = tester.getSize(find.byType(RecoveryThumbnail).first).width;
    expect(narrow, greaterThan(0));
    expect(wide, greaterThan(0));
  });

  testWidgets('large text and dark theme render without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: RecoveryScanScreen(
          controller: RecoveryScanController(
            source: RecoveryScanSource.cameraGallery,
            pageSource: _ImmediateSource(_success([_item(_candidate('one'))])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('thumbnail requests are capped by the existing memory policy', () {
    const thumbnail = RecoveryThumbnail(semanticLabel: 'Photo');
    expect(
      thumbnail.requestedDimension,
      lessThanOrEqualTo(RecoveryImageMemoryPolicy.maximumThumbnailDimension),
    );
  });
}

Widget _app(
  RecoveryScanController controller, {
  ValueChanged<List<MediaCandidate>>? onRestore,
}) => MaterialApp(
  theme: AppTheme.light,
  home: RecoveryScanScreen(controller: controller, onRestoreIntent: onRestore),
);

RecoveryScanController _controller(RecoveryScanPageSource source) =>
    RecoveryScanController(
      source: RecoveryScanSource.cameraGallery,
      pageSource: source,
    );

class _ImmediateSource implements RecoveryScanPageSource {
  const _ImmediateSource(this.result);
  final VerifiedSourceRecoveryResult result;
  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => result;
}

class _PendingSource implements RecoveryScanPageSource {
  final _completer = Completer<VerifiedSourceRecoveryResult>();
  void complete(VerifiedSourceRecoveryResult result) =>
      _completer.complete(result);
  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) => _completer.future;
}

VerifiedSourceRecoverySuccess _success(
  List<VerifiedSourceRecoveryItem> items, {
  MediaSource source = MediaSource.cameraGallery,
}) => VerifiedSourceRecoverySuccess(
  source: source,
  items: items,
  diagnostics: VerifiedSourceRecoveryDiagnostics(
    examinedCount: items.length,
    excludedExistingCount: 0,
    filteredOtherSourceCount: 0,
    filteredIneligibleCount: 0,
  ),
);

VerifiedSourceRecoveryItem _item(MediaCandidate candidate) =>
    VerifiedSourceRecoveryItem(
      candidate: candidate,
      classificationDecision: RecoveryClassificationDecision(
        classification: candidate.classification,
        reason: RecoveryClassificationReason.verifiedSystemTrashEvidence,
      ),
      restoreEligibility: const SystemTrashRestoreEligibility(
        reason: SystemTrashRestoreEligibilityReason.eligible,
      ),
    );

MediaCandidate _candidate(
  String id, {
  MediaSource source = MediaSource.cameraGallery,
}) => MediaCandidate(
  id: id,
  source: source,
  displayName: '$id.jpg',
  classification: RecoveryClassification.verifiedDeleted,
  deletionEvidence: DeletionEvidence(
    reasons: const [DeletionEvidenceReason.systemTrashRecord],
  ),
  restoreCapability: RestoreCapability.originalFullQuality,
  recoveryQuality: RecoveryQuality.original,
);
