import '../../domain/media_candidate.dart';
import '../../domain/media_source.dart';
import '../existing_media_exclusion/existing_media_exclusion_engine.dart';
import '../existing_media_exclusion/existing_media_exclusion_models.dart';
import '../existing_media_exclusion/existing_media_index.dart';
import '../recovery_shield/recovery_shield_models.dart';
import '../scoped_storage_recovery/storage_scope_models.dart';
import 'recovery_shield_restore_models.dart';

class RecoveryShieldRestorePolicy {
  const RecoveryShieldRestorePolicy({
    this.exclusionEngine = const ExistingMediaExclusionEngine(),
  });

  final ExistingMediaExclusionEngine exclusionEngine;

  RecoveryShieldRestorePreparation prepare({
    required ProtectedMediaRecord record,
    required MediaCandidate originalCandidate,
    required ExistingMediaIndex existingMediaIndex,
    AuthorizedFolderScope? authorizedDestinationScope,
  }) {
    if (record.protectionId.trim().isEmpty ||
        record.sha256Digest.trim().isEmpty ||
        record.byteSize < 0 ||
        record.originalSource != originalCandidate.source) {
      return RecoveryShieldRestorePreparation.rejected(
        RecoveryShieldRestoreResult(
          protectionId: record.protectionId,
          status: RecoveryShieldRestoreStatus.notEligible,
        ),
      );
    }

    final existing = exclusionEngine.evaluate(
      originalCandidate,
      existingMediaIndex,
    );
    if (existing.type == ExistingMediaDecisionType.definitelyExisting) {
      return RecoveryShieldRestorePreparation.rejected(
        RecoveryShieldRestoreResult(
          protectionId: record.protectionId,
          status: RecoveryShieldRestoreStatus.alreadyPresent,
        ),
      );
    }

    if (_requiresScope(record.originalSource)) {
      if (authorizedDestinationScope == null ||
          authorizedDestinationScope.grantState != FolderGrantState.active) {
        return RecoveryShieldRestorePreparation.rejected(
          RecoveryShieldRestoreResult(
            protectionId: record.protectionId,
            status: RecoveryShieldRestoreStatus.destinationRequired,
          ),
        );
      }
      return RecoveryShieldRestorePreparation.eligible(
        RecoveryShieldRestoreRequest(
          record: record,
          originalCandidate: originalCandidate,
          authorizedDestinationScope: authorizedDestinationScope,
        ),
      );
    }

    return RecoveryShieldRestorePreparation.eligible(
      RecoveryShieldRestoreRequest(
        record: record,
        originalCandidate: originalCandidate,
        relativeDestination: _destination(record),
      ),
    );
  }

  bool _requiresScope(MediaSource source) => source == MediaSource.sdCard;

  String _destination(ProtectedMediaRecord record) {
    final safeOriginal = _safeRelativePath(record.originalLocation);
    return switch (record.originalSource) {
      MediaSource.cameraGallery => safeOriginal ?? 'DCIM/Camera',
      MediaSource.screenshots => safeOriginal ?? 'Pictures/Screenshots',
      MediaSource.downloadsSavedMedia => safeOriginal ?? 'Download',
      MediaSource.messagingSharedMedia =>
        safeOriginal ?? 'Pictures/Photo Recovery & Restore',
      MediaSource.recoveryShield ||
      MediaSource.unknown => 'Pictures/Photo Recovery & Restore',
      MediaSource.sdCard => throw StateError(
        'Scoped destinations are handled separately.',
      ),
    };
  }

  String? _safeRelativePath(String? value) {
    final normalized = value?.trim().replaceAll('\\', '/');
    if (normalized == null ||
        normalized.isEmpty ||
        normalized.startsWith('/')) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (normalized.split('/').contains('..') ||
        lower == 'android' ||
        lower.startsWith('android/')) {
      return null;
    }
    return normalized.replaceAll(RegExp(r'/+$'), '');
  }
}
