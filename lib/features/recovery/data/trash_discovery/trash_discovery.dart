import 'trash_discovery_models.dart';

abstract interface class TrashDiscovery {
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  );
}
