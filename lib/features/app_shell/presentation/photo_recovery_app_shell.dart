import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';
import '../../media_access/media_access.dart';
import '../../media_access/presentation/media_access_screen.dart';
import '../../recovery_scan/application/recovery_scan_controller.dart';
import '../../recovery_scan/application/recovery_scan_models.dart';
import '../../recovery_scan/application/photo_recovery_engine.dart';
import '../../recovery/application/deep_recovery/deep_recovery_provider.dart';
import '../../recovery_scan/presentation/recovery_scan_screen.dart';
import '../../restore_ux/application/restore_ux_coordinator.dart';
import '../../restore_ux/presentation/photo_detail_screen.dart';
import '../../recovery/data/restore/platform_system_trash_restore.dart';
import '../../recovery/data/restore/file_copy_restorer.dart';
import '../../recovery/data/recovery_shield_restore/platform_recovery_shield_restorer.dart';
import '../../recovery_shield_management/presentation/recovery_shield_screen.dart';
import '../../recovery_shield_management/recovery_shield_manager.dart';
import '../../settings/app_preferences.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../recovered_photos/application/recovered_photos_store.dart';
import '../../recovered_photos/presentation/recovered_photos_screen.dart';
import '../../smart_cleanup/application/photo_cleanup_engine.dart';
import '../../smart_cleanup/application/photo_cleanup_models.dart';
import '../../smart_cleanup/data/platform_photo_cleanup.dart';
import '../../smart_cleanup/presentation/photo_cleanup_screen.dart';
import '../../recovery/data/current_media_inventory/platform_current_media_inventory.dart';

class PhotoRecoveryAppShell extends StatefulWidget {
  const PhotoRecoveryAppShell({
    this.accessCoordinator,
    this.shieldManager,
    this.preferences,
    this.onReplayOnboarding,
    this.recoveredPhotosStore,
    this.cleanupEngine,
    this.cleanupDeletionExecutor,
    super.key,
  });

  final MediaAccessCoordinator? accessCoordinator;
  final RecoveryShieldManager? shieldManager;
  final AppPreferencesController? preferences;
  final VoidCallback? onReplayOnboarding;
  final RecoveredPhotosStore? recoveredPhotosStore;
  final PhotoCleanupEngine? cleanupEngine;
  final PhotoCleanupDeletionExecutor? cleanupDeletionExecutor;

  @override
  State<PhotoRecoveryAppShell> createState() => _PhotoRecoveryAppShellState();
}

class _PhotoRecoveryAppShellState extends State<PhotoRecoveryAppShell> {
  late final MediaAccessCoordinator _accessCoordinator =
      widget.accessCoordinator ?? PlatformMediaAccessCoordinator();
  late final RecoveryShieldManager _shieldManager =
      widget.shieldManager ?? PlatformRecoveryShieldManager();
  late final AppPreferencesController _preferences =
      widget.preferences ??
      AppPreferencesController(PlatformAppPreferencesStore());
  late final RecoveredPhotosStore _recoveredPhotosStore =
      widget.recoveredPhotosStore ?? PlatformRecoveredPhotosStore();
  late final RestoreUxCoordinator _restoreCoordinator = RestoreUxCoordinator(
    systemTrashExecutor: PlatformSystemTrashRestore(),
    fileCopyRestorer: const PlatformFileCopyRestorer(),
    shieldRestorer: PlatformRecoveryShieldRestorer(),
    historyStore: _recoveredPhotosStore,
  );
  late final PhotoCleanupEngine _cleanupEngine =
      widget.cleanupEngine ??
      PhotoCleanupEngine(
        inventory: PlatformCurrentMediaInventory(),
        digestProvider: PlatformPhotoCleanupDigestProvider(),
      );
  late final PhotoCleanupDeletionExecutor _cleanupDeletionExecutor =
      widget.cleanupDeletionExecutor ?? PlatformPhotoCleanupDeletionExecutor();

  Future<void> _startPhotoRecovery() async {
    final state = await _accessCoordinator.getState();
    if (!mounted) return;
    if (state.canReadImages) {
      // Optional whole-storage traversal never gates the standard MediaStore scan.
      _openPhotoScan();
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaAccessScreen(
          coordinator: _accessCoordinator,
          initialState: state,
          onAccessAvailable: (_) {
            Navigator.of(context).pop();
            _openPhotoScan();
          },
        ),
      ),
    );
  }

  void _openPhotoScan() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecoveryScanScreen(
          controller: RecoveryScanController(
            source: RecoveryScanSource.allPhotos,
            pageSource: PhotoRecoveryEngine(
              accessCoordinator: _accessCoordinator,
              profile: PhotoRecoveryProfile.thorough,
            ),
          ),
          restoreCoordinator: _restoreCoordinator,
          onRestoreReview: (items) => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => RestoreReviewSheet(
              items: items,
              coordinator: _restoreCoordinator,
            ),
          ),
        ),
      ),
    );
  }

  void _openRecoveredPhotos() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecoveredPhotosScreen(store: _recoveredPhotosStore),
      ),
    );
  }

  void _openCleanup(PhotoCleanupCategory category) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PhotoCleanupScreen(
          category: category,
          engine: _cleanupEngine,
          deletionExecutor: _cleanupDeletionExecutor,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          preferences: _preferences,
          mediaAccess: _accessCoordinator,
          shieldManager: _shieldManager,
          onReplayOnboarding: () {
            Navigator.of(context).pop();
            widget.onReplayOnboarding?.call();
          },
        ),
      ),
    );
  }

  void _openShield() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecoveryShieldScreen(manager: _shieldManager),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: HomeScreen(
      onStartPhotoRecovery: _startPhotoRecovery,
      onSettings: _openSettings,
      onManageShield: _openShield,
      onRecoveredPhotos: _openRecoveredPhotos,
      onDuplicatePhotos: () =>
          _openCleanup(PhotoCleanupCategory.duplicatePhotos),
      onOldPhotos: () => _openCleanup(PhotoCleanupCategory.oldPhotos),
      onLargePhotos: () => _openCleanup(PhotoCleanupCategory.largePhotos),
    ),
  );
}
