import '../../application/deep_recovery/deep_recovery_provider.dart';
import '../../domain/deletion_evidence.dart';
import '../../domain/media_candidate.dart';
import '../../domain/recovery_classification.dart';
import '../../domain/recovery_quality.dart';
import '../../domain/restore_capability.dart';
import 'authorized_folder_media_discovery.dart';

class AuthorizedFolderDeepRecoveryProvider
    implements DeepRecoveryDiscoveryProvider {
  const AuthorizedFolderDeepRecoveryProvider({
    required this.treeUri,
    required this.discovery,
  });

  final Uri treeUri;
  final AuthorizedFolderMediaDiscovery discovery;

  @override
  DeepRecoveryProviderKind get kind =>
      DeepRecoveryProviderKind.authorizedSafTree;

  @override
  Set<DeepStorageAccessCapability> get requiredCapabilities => const {
    DeepStorageAccessCapability.persistedSafTree,
  };

  @override
  Future<DeepRecoveryProviderResult> getPage(
    DeepRecoveryProviderRequest request,
  ) async {
    final result = await discovery.getPage(
      treeUri: treeUri,
      pageSize: request.pageSize,
      continuationToken: request.continuationToken,
    );
    if (result is AuthorizedFolderMediaFailure) {
      return DeepRecoveryProviderUnavailable(
        result.code == AuthorizedFolderMediaFailureCode.permissionGrantLost
            ? DeepProviderAvailability.accessRequired
            : DeepProviderAvailability.failed,
        message: result.message,
      );
    }
    final page = (result as AuthorizedFolderMediaSuccess).page;
    return DeepRecoveryProviderPage(
      items: [
        for (final record in page.items)
          DeepRecoveryDiscoveryRecord(
            provider: kind,
            isAccessibleCurrentMedia: true,
            candidate: MediaCandidate(
              id: 'saf:${record.documentUri}',
              source: request.source,
              documentUri: record.documentUri,
              contentUri: record.documentUri,
              displayName: record.displayName,
              mimeType: record.mimeType,
              byteSize: record.byteSize,
              modifiedAt: record.modifiedAt,
              classification: RecoveryClassification.existingMedia,
              deletionEvidence: DeletionEvidence(),
              restoreCapability: RestoreCapability.notRestorable,
              recoveryQuality: RecoveryQuality.metadataOnly,
            ),
          ),
      ],
      nextContinuationToken: page.nextContinuationToken,
      filesExamined: page.filesExamined,
      invalidFilesRejected: page.invalidFilesRejected,
      unavailableFiles: page.unavailableFiles,
      unsupportedFiles: page.unsupportedFiles,
    );
  }
}
