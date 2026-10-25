import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_evidence_classifier/recovery_classification_decision.dart';
import 'package:photo_recovery_restore/features/recovery/application/restore/system_trash_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/scan_runtime/recovery_image_memory_policy.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
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
  testWidgets('leaving an active scan cancels it', (tester) async {
    final source = _PendingSource();
    final controller = _controller(source);
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(controller.state.status, RecoveryScanViewStatus.running);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.state.status, RecoveryScanViewStatus.cancelling);
    source.complete(_success(const []));
    await tester.pump();
  });

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

  testWidgets('published candidates remain visible while later pages scan', (
    tester,
  ) async {
    final source = _TwoPageSource();
    await tester.pumpWidget(
      _app(
        RecoveryScanController(
          source: RecoveryScanSource.allPhotos,
          pageSource: source,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Scanning photos'), findsOneWidget);
    expect(find.text('Deleted Photos'), findsWidgets);

    source.complete(_success(const []));
    await tester.pumpAndSettle();
  });

  testWidgets('open category receives later scan pages and retains selection', (
    tester,
  ) async {
    final source = _TwoPageSource();
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: source,
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Camera & Gallery').last);
    await tester.pumpAndSettle();
    expect(find.text('Photos  1'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('Review selected (1)'), findsOneWidget);

    source.complete(
      _success([
        _item(_candidate('second', source: MediaSource.cameraGallery)),
      ], source: MediaSource.cameraGallery),
    );
    await tester.pump();
    expect(find.text('Photos  2'), findsOneWidget);
    expect(find.text('Review selected (1)'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('Review selected (2)'), findsOneWidget);
    await tester.tap(find.text('Deselect all'));
    await tester.pump();
    expect(find.text('Review selected (2)'), findsNothing);
    await tester.pageBack();
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

  testWidgets('individual grid selection reaches batch review', (tester) async {
    List<MediaCandidate>? selected;
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: _ImmediateSource(_success([_item(_candidate('one'))])),
    );
    await tester.pumpWidget(
      _app(controller, onRestore: (items) => selected = items),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera & Gallery').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Review selected (1)'), findsOneWidget);
    await tester.tap(find.text('Review selected (1)'));
    expect(selected?.single.id, 'one');
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
    expect(find.text('Photos  2'), findsOneWidget);
  });

  testWidgets('ordinary existing media is never shown in recovery results', (
    tester,
  ) async {
    final existing = MediaCandidate(
      id: 'current:1',
      source: MediaSource.cameraGallery,
      contentUri: Uri.parse('content://media/external/images/media/1'),
      displayName: 'camera.jpg',
      classification: RecoveryClassification.existingMedia,
      deletionEvidence: DeletionEvidence(),
      restoreCapability: RestoreCapability.alternateFullQualityCopy,
      recoveryQuality: RecoveryQuality.original,
    );
    final controller = RecoveryScanController(
      source: RecoveryScanSource.allPhotos,
      pageSource: _CurrentPhotosSource(existing),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(controller.state.existingPhotos, isEmpty);
    expect(controller.state.status, RecoveryScanViewStatus.empty);
    expect(find.text('All Photos  1'), findsNothing);
    expect(find.text('Existing Photos  1'), findsNothing);
    expect(find.bySemanticsLabel('Camera & Gallery, 1 photos'), findsNothing);
    expect(find.text('No recoverable photos found'), findsOneWidget);
  });

  testWidgets(
    'possible copies use a readable category without being labelled deleted',
    (tester) async {
      final copy = MediaCandidate(
        id: 'hidden-copy',
        source: MediaSource.unknown,
        displayName: 'cached.jpg',
        relativeLocation: 'Android/media/example/.Statuses',
        classification: RecoveryClassification.possibleCopy,
        deletionEvidence: DeletionEvidence(),
        restoreCapability: RestoreCapability.unknownQualityCopy,
        recoveryQuality: RecoveryQuality.unknownQualityCopy,
      );
      final controller = RecoveryScanController(
        source: RecoveryScanSource.allPhotos,
        pageSource: _ImmediateSource(_success(const [])),
        possibleCopies: [copy],
      );
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('Verified Deleted  0'), findsOneWidget);
      expect(find.text('Recoverable Copies  1'), findsOneWidget);
      expect(find.text('Hidden Images'), findsOneWidget);
      await tester.tap(find.text('Hidden Images'));
      await tester.pumpAndSettle();
      expect(find.text('Photos  1'), findsOneWidget);
      expect(find.text('Verified Deleted  1'), findsNothing);
    },
  );

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
      find.text('WhatsApp & Messaging'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('WhatsApp & Messaging'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Other Recovery Images'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Other Recovery Images'), findsOneWidget);
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

  testWidgets('automatic scan hides folder selection after an empty result', (
    tester,
  ) async {
    final controller = RecoveryScanController(
      source: RecoveryScanSource.messaging,
      pageSource: _OptionalDeepUnavailableSource(),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('No recoverable photos found'), findsOneWidget);
    expect(find.text('Scan a folder you choose'), findsNothing);
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

class _CurrentPhotosSource
    implements RecoveryScanPageSource, CurrentPhotosAwarePageSource {
  _CurrentPhotosSource(this.photo);
  final MediaCandidate photo;
  void Function(List<MediaCandidate>)? _progress;

  @override
  List<MediaCandidate> get currentPhotos => [photo];

  @override
  set onCurrentPhotosProgress(void Function(List<MediaCandidate>)? callback) =>
      _progress = callback;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async {
    _progress?.call([photo]);
    return _success(const [], source: source.mediaSource);
  }
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

class _TwoPageSource implements RecoveryScanPageSource {
  final _completer = Completer<VerifiedSourceRecoveryResult>();

  void complete(VerifiedSourceRecoveryResult result) =>
      _completer.complete(result);

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) {
    if (request.continuationToken == null) {
      return Future<VerifiedSourceRecoveryResult>.value(
        _success(
          [_item(_candidate('first', source: MediaSource.cameraGallery))],
          source: MediaSource.cameraGallery,
          continuationToken: 'second-page',
        ),
      );
    }
    return _completer.future;
  }
}

class _OptionalDeepUnavailableSource
    implements RecoveryScanPageSource, DeepScanCapabilityAwarePageSource {
  @override
  DeepStorageCapabilityStatus get deepCapabilityStatus =>
      DeepStorageCapabilityStatus.unavailable;

  @override
  String? get deepCapabilityMessage => 'Optional deep scan is unavailable.';

  @override
  bool get canRequestDeepStorageAccess => false;

  @override
  Future<void> openDeepScanSettings() async {}

  @override
  Future<bool> refreshDeepScanCapability() async => false;

  @override
  Future<VerifiedSourceRecoveryResult> loadPage(
    RecoveryScanSource source,
    TrashDiscoveryPageRequest request,
  ) async => _success(const [], source: source.mediaSource);
}

VerifiedSourceRecoverySuccess _success(
  List<VerifiedSourceRecoveryItem> items, {
  MediaSource source = MediaSource.cameraGallery,
  String? continuationToken,
}) => VerifiedSourceRecoverySuccess(
  source: source,
  items: items,
  diagnostics: VerifiedSourceRecoveryDiagnostics(
    examinedCount: items.length,
    excludedExistingCount: 0,
    filteredOtherSourceCount: 0,
    filteredIneligibleCount: 0,
  ),
  nextContinuationToken: continuationToken,
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
