import '../../recovery/application/deep_recovery/deep_recovery_provider.dart';
import 'production_recovery_scan_page_source.dart';

/// The single production image-recovery pipeline.
///
/// MediaStore inventory supplies existing-photo results and an identity index;
/// trash and possible copies retain separate classifications. Deep storage is
/// attempted after the standard scan only when the
/// platform reports that the user has granted a permitted access mode.
class PhotoRecoveryEngine extends ProductionRecoveryScanPageSource {
  PhotoRecoveryEngine({
    super.accessCoordinator,
    super.inventory,
    super.trashDiscovery,
    super.deepStorageProvider,
    // Capability checks in the page source keep this opt-in traversal from
    // running where scoped storage does not permit it. Keeping it enabled here
    // is essential: callers that select the thorough profile must actually
    // reach the deep provider on supported devices (for example, legacy shared
    // storage or an explicitly granted eligible access mode).
    super.includeDeepStorage = true,
    super.profile = PhotoRecoveryProfile.fastDeep,
  });
}
