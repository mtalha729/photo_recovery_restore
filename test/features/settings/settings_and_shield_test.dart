import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/media_access/media_access.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield/recovery_shield_models.dart';
import 'package:photo_recovery_restore/features/recovery/application/recovery_shield_restore/recovery_shield_restore_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/recovery_shield_restore/recovery_shield_restorer.dart';
import 'package:photo_recovery_restore/features/recovered_photos/application/recovered_photos_store.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery_shield_management/presentation/recovery_shield_screen.dart';
import 'package:photo_recovery_restore/features/recovery_shield_management/recovery_shield_manager.dart';
import 'package:photo_recovery_restore/features/settings/app_preferences.dart';
import 'package:photo_recovery_restore/features/settings/presentation/settings_screen.dart';

void main() {
  testWidgets('Shield displays only real count, usage, and integrity state', (
    tester,
  ) async {
    final record = ProtectedMediaRecord(
      protectionId: 'one',
      originalSource: MediaSource.cameraGallery,
      protectedCopyLocation: '/private/shield/family.bin',
      sha256Digest: List.filled(64, 'a').join(),
      protectedAt: DateTime.utc(2025),
      byteSize: 2048,
      displayName: 'family.jpg',
      mimeType: 'image/jpeg',
    );
    final manager = _ShieldManager([
      ShieldManagedItem(
        protectionId: 'one',
        displayName: 'family.jpg',
        byteSize: 2048,
        integrityVerified: true,
        record: record,
      ),
    ]);
    await tester.pumpWidget(_app(RecoveryShieldScreen(manager: manager)));
    await tester.pumpAndSettle();
    expect(find.text('1 protected photo'), findsOneWidget);
    expect(find.text('Private storage used: 2.0 KB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Integrity verified'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Integrity verified'), findsOneWidget);
    expect(find.textContaining('2,846'), findsNothing);
  });

  testWidgets(
    'Shield restore creates an explicit copy, not deletion evidence',
    (tester) async {
      final record = ProtectedMediaRecord(
        protectionId: 'backup-1',
        originalSource: MediaSource.cameraGallery,
        protectedCopyLocation: '/private/shield/backup.bin',
        sha256Digest: List.filled(64, 'a').join(),
        protectedAt: DateTime.utc(2025),
        byteSize: 128,
        displayName: 'photo.jpg',
        mimeType: 'image/jpeg',
        originalContentUri: Uri.parse(
          'content://media/external/images/media/4',
        ),
      );
      final manager = _ShieldManager([
        ShieldManagedItem(
          protectionId: 'backup-1',
          displayName: 'photo.jpg',
          byteSize: 128,
          integrityVerified: true,
          record: record,
        ),
      ]);
      final restorer = _RecordingShieldRestorer();
      final history = _RecoveredPhotosHistory();
      await tester.pumpWidget(
        _app(
          RecoveryShieldScreen(
            manager: manager,
            restorer: restorer,
            recoveredPhotosStore: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Restore protected copy'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.byTooltip('Restore protected copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Restore protected copy'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not mean the original was deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save a copy'));
      await tester.pumpAndSettle();

      expect(restorer.request, isNotNull);
      expect(
        restorer.request!.originalCandidate.classification,
        RecoveryClassification.protectedCopy,
      );
      expect(
        restorer.request!.originalCandidate.deletionEvidence.isEmpty,
        isTrue,
      );
      expect(
        restorer
            .request!
            .originalCandidate
            .discoveryEvidence
            .isRecoveryShieldBackup,
        isTrue,
      );
      expect(history.records, hasLength(1));
      expect(history.records.single.contentUri.scheme, 'content');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shield does not report success without a restored output', (
    tester,
  ) async {
    final record = ProtectedMediaRecord(
      protectionId: 'missing-output',
      originalSource: MediaSource.cameraGallery,
      protectedCopyLocation: '/private/shield/photo.bin',
      sha256Digest: List.filled(64, 'a').join(),
      protectedAt: DateTime.utc(2025),
      byteSize: 128,
      displayName: 'photo.jpg',
      mimeType: 'image/jpeg',
    );
    final history = _RecoveredPhotosHistory();
    await tester.pumpWidget(
      _app(
        RecoveryShieldScreen(
          manager: _ShieldManager([
            ShieldManagedItem(
              protectionId: record.protectionId,
              byteSize: record.byteSize,
              integrityVerified: true,
              record: record,
            ),
          ]),
          restorer: _RecordingShieldRestorer(includeRestoredContentUri: false),
          recoveredPhotosStore: history,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Restore protected copy'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byTooltip('Restore protected copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restore protected copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save a copy'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to verify the restored copy.'), findsOneWidget);
    expect(history.records, isEmpty);
  });

  testWidgets('protect and unprotect actions emit explicit intents', (
    tester,
  ) async {
    final manager = _ShieldManager([
      const ShieldManagedItem(
        protectionId: 'one',
        byteSize: 20,
        integrityVerified: true,
      ),
    ]);
    await tester.pumpWidget(_app(RecoveryShieldScreen(manager: manager)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protect selected photos'));
    await tester.pumpAndSettle();
    expect(manager.protectCalls, 1);
    await tester.scrollUntilVisible(
      find.byTooltip('Remove protected copy'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('Remove protected copy'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('original photo is not deleted'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove copy'));
    await tester.pumpAndSettle();
    expect(manager.unprotectedIds, ['one']);
  });

  for (final entry in {
    MediaAccessStatus.fullAccess: 'Full',
    MediaAccessStatus.limitedSelectedAccess: 'Limited',
    MediaAccessStatus.denied: 'Denied',
  }.entries) {
    testWidgets('privacy dashboard labels ${entry.value} access truthfully', (
      tester,
    ) async {
      final access = _Access(entry.key);
      await tester.pumpWidget(
        _app(
          SettingsScreen(
            preferences: AppPreferencesController(_PreferencesStore()),
            mediaAccess: access,
            shieldManager: _ShieldManager(const []),
            onReplayOnboarding: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(access.requestCalls, 0);
    });
  }

  testWidgets('privacy policy opens in-app with local-processing disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SettingsScreen(
          preferences: AppPreferencesController(_PreferencesStore()),
          mediaAccess: _Access(MediaAccessStatus.denied),
          shieldManager: _ShieldManager(const []),
          onReplayOnboarding: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Privacy policy'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.textContaining('processed on this device'), findsOneWidget);
    expect(find.text('Information accessed and why'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme selection persists and reduced motion is saved', (
    tester,
  ) async {
    final store = _PreferencesStore();
    final controller = AppPreferencesController(store);
    await tester.pumpWidget(
      _app(
        SettingsScreen(
          preferences: controller,
          mediaAccess: _Access(MediaAccessStatus.denied),
          shieldManager: _ShieldManager(const []),
          onReplayOnboarding: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(store.saved.themeMode, ThemeMode.dark);
    expect(find.byType(Switch), findsNothing);
    expect(store.saved.reduceMotion, isFalse);
  });

  testWidgets('onboarding replay and clear Shield are explicit', (
    tester,
  ) async {
    final manager = _ShieldManager([
      const ShieldManagedItem(
        protectionId: 'one',
        byteSize: 20,
        integrityVerified: true,
      ),
    ]);
    var replayed = false;
    await tester.pumpWidget(
      _app(
        SettingsScreen(
          preferences: AppPreferencesController(_PreferencesStore()),
          mediaAccess: _Access(MediaAccessStatus.denied),
          shieldManager: manager,
          onReplayOnboarding: () => replayed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recovery Shield'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear protected copies'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Original photos are never deleted'),
      findsOneWidget,
    );
    expect(manager.clearCalls, 0);
    await tester.tap(find.text('Clear protected copies'));
    await tester.pumpAndSettle();
    expect(manager.clearCalls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay onboarding'));
    expect(replayed, isTrue);
  });

  testWidgets('settings remains usable at narrow width and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(340, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: _app(
          SettingsScreen(
            preferences: AppPreferencesController(_PreferencesStore()),
            mediaAccess: _Access(MediaAccessStatus.limitedSelectedAccess),
            shieldManager: _ShieldManager(const []),
            onReplayOnboarding: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Recovery & privacy'), findsOneWidget);
  });
}

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

class _ShieldManager implements RecoveryShieldManager {
  _ShieldManager(List<ShieldManagedItem> items) : items = List.of(items);
  List<ShieldManagedItem> items;
  int protectCalls = 0;
  int clearCalls = 0;
  final List<String> unprotectedIds = [];

  @override
  Future<RecoveryShieldSnapshot> load() async => RecoveryShieldSnapshot(items);

  @override
  Future<int> protectSelectedPhotos() async {
    protectCalls++;
    return 0;
  }

  @override
  Future<bool> unprotect(Iterable<String> protectionIds) async {
    unprotectedIds.addAll(protectionIds);
    items.removeWhere((item) => protectionIds.contains(item.protectionId));
    return true;
  }

  @override
  Future<bool> clear() async {
    clearCalls++;
    items.clear();
    return true;
  }
}

class _RecordingShieldRestorer implements RecoveryShieldRestorer {
  _RecordingShieldRestorer({this.includeRestoredContentUri = true});

  final bool includeRestoredContentUri;
  RecoveryShieldRestoreRequest? request;

  @override
  Future<RecoveryShieldRestoreResult> restore(
    RecoveryShieldRestoreRequest value,
  ) async {
    request = value;
    return RecoveryShieldRestoreResult(
      protectionId: value.record.protectionId,
      status: RecoveryShieldRestoreStatus.restored,
      restoredContentUri: includeRestoredContentUri
          ? Uri.parse('content://media/external/images/media/99')
          : null,
    );
  }

  @override
  Future<RecoveryShieldRestoreBatchResult> restoreBatch(
    Iterable<RecoveryShieldRestorePreparation> preparations,
  ) async => RecoveryShieldRestoreBatchResult([
    for (final preparation in preparations)
      preparation.rejection ?? await restore(preparation.request!),
  ]);
}

class _RecoveredPhotosHistory implements RecoveredPhotosStore {
  final List<RecoveredPhotoRecord> records = [];

  @override
  Future<List<RecoveredPhotoRecord>> load() async => List.unmodifiable(records);

  @override
  Future<void> upsert(RecoveredPhotoRecord record) async {
    records.removeWhere((value) => value.id == record.id);
    records.add(record);
  }
}

class _Access implements MediaAccessCoordinator {
  _Access(MediaAccessStatus status)
    : state = MediaAccessState(status: status, androidApiLevel: 34);
  final MediaAccessState state;
  int requestCalls = 0;

  @override
  Future<MediaAccessState> getState() async => state;

  @override
  Future<void> openSettings() async {}

  @override
  Future<MediaAccessState> requestAccess({
    MediaAccessRequestIntent intent = MediaAccessRequestIntent.initial,
  }) async {
    requestCalls++;
    return state;
  }
}

class _PreferencesStore implements AppPreferencesStore {
  AppPreferenceState saved = const AppPreferenceState();

  @override
  Future<List<String>> authorizedFolders() async => const ['content://folder'];

  @override
  Future<String> appVersion() async => '1.0.0';

  @override
  Future<AppPreferenceState> load() async => saved;

  @override
  Future<void> save(AppPreferenceState state) async => saved = state;
}
