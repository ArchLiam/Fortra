MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
    MaintenanceOrderDecompositionService.loadWork('801WC00000knHDLYA2');
Map<Id, OrderItem> patches = MaintenanceOrderDecompositionService.buildCommercialPatchesFromWork(work);
System.debug('patch count=' + patches.size());
for (Id k : patches.keySet()) {
    OrderItem p = patches.get(k);
    System.debug('PATCH ' + k + ' NetUnit=' + p.NetUnitPrice + ' Unit=' + p.UnitPrice + ' Total=' + p.TotalLineAmount);
}
