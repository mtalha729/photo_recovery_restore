import '../../recovery/application/deep_recovery/deep_recovery_provider.dart';
import 'production_recovery_scan_page_source.dart';

/// The single production image-recovery pipeline.
///
/// MediaStore inventory/trash, direct shared-storage discovery, existing-media
/// exclusion, classification, duplicate resolution, and result production all
/// remain in the inherited pipeline. The profile only changes scan depth.
class PhotoRecoveryEngine extends ProductionRecoveryScanPageSource {
  PhotoRecoveryEngine({
    super.accessCoordinator,
    super.inventory,
    super.trashDiscovery,
    super.folderMediaDiscovery,
    super.deepStorageProvider,
    super.authorizedFolderScope,
    super.includeDeepStorage = true,
    super.profile = PhotoRecoveryProfile.fastDeep,
  });
}
