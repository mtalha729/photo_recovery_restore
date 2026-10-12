import '../../domain/media_candidate.dart';
import 'recovery_shield_models.dart';

class RecoveryShieldProtectionPolicy {
  const RecoveryShieldProtectionPolicy();

  RecoveryShieldProtectionRequest? createRequest({
    required String protectionId,
    required MediaCandidate candidate,
  }) {
    final cleanId = protectionId.trim();
    final sourceUri = candidate.contentUri ?? candidate.documentUri;
    final identity = _stableIdentity(candidate);
    if (cleanId.isEmpty || sourceUri == null || identity == null) return null;
    return RecoveryShieldProtectionRequest(
      protectionId: cleanId,
      candidate: candidate,
      sourceUri: sourceUri,
      stableSourceIdentity: identity,
    );
  }

  String? _stableIdentity(MediaCandidate candidate) {
    final contentUri = candidate.contentUri?.toString().trim();
    if (contentUri != null && contentUri.isNotEmpty) return 'uri:$contentUri';
    final documentUri = candidate.documentUri?.toString().trim();
    if (documentUri != null && documentUri.isNotEmpty) {
      return 'document:$documentUri';
    }
    final volume = candidate.storageVolumeName?.trim().toLowerCase();
    final mediaStoreId = candidate.mediaStoreId;
    if (volume != null &&
        volume.isNotEmpty &&
        mediaStoreId != null &&
        mediaStoreId >= 0) {
      return 'media:$volume:$mediaStoreId';
    }
    return null;
  }
}
