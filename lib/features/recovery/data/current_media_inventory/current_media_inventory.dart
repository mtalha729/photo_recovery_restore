import 'current_media_inventory_models.dart';

abstract interface class CurrentMediaInventory {
  Future<CurrentMediaInventoryResult> getCurrentMediaPage(
    CurrentMediaPageRequest request,
  );
}
