// SC-3513 R-4 backfill — stamp Asset.Description on the 16 changed assets blank before the flow existed.
// Fill-only (never overwrites a non-blank value). Mirrors the flow's resolution: AssetActionSource
// ReferenceEntityItemId -> OrderItem directly, or via OrderItemDetail.OrderItemId parent; first non-blank wins.
Set<Id> assetIds = new Set<Id>();
for (Asset a : [SELECT Id, Description FROM Asset WHERE Id IN (
        SELECT AssetId FROM AssetAction
        WHERE CategoryEnum IN ('Upsells','Renewals','Downsells','Upgrades','Downgrades','Swaps','Cross-Sells')
        AND AssetId != null)]) {
    if (String.isBlank(a.Description)) {
        assetIds.add(a.Id);
    }
}
System.debug('BACKFILL| target blank assets: ' + assetIds.size());

// Collect all source reference ids per asset (via the asset's AssetActions).
Map<Id, List<Id>> assetToRefIds = new Map<Id, List<Id>>();
Set<Id> allRefIds = new Set<Id>();
for (AssetActionSource src : [
        SELECT ReferenceEntityItemId, AssetAction.AssetId
        FROM AssetActionSource
        WHERE AssetAction.AssetId IN :assetIds AND ReferenceEntityItemId != null]) {
    Id aId = src.AssetAction.AssetId;
    if (!assetToRefIds.containsKey(aId)) {
        assetToRefIds.put(aId, new List<Id>());
    }
    assetToRefIds.get(aId).add(src.ReferenceEntityItemId);
    allRefIds.add(src.ReferenceEntityItemId);
}

// Bulk resolve OrderItem descriptions (direct) and via OrderItemDetail parent.
Map<Id, String> oiDesc = new Map<Id, String>();
for (OrderItem oi : [SELECT Id, Description FROM OrderItem WHERE Id IN :allRefIds AND Description != null]) {
    oiDesc.put(oi.Id, oi.Description);
}
Map<Id, Id> oidToParent = new Map<Id, Id>();
Set<Id> parentIds = new Set<Id>();
for (OrderItemDetail oid : [SELECT Id, OrderItemId FROM OrderItemDetail WHERE Id IN :allRefIds]) {
    oidToParent.put(oid.Id, oid.OrderItemId);
    parentIds.add(oid.OrderItemId);
}
for (OrderItem oi : [SELECT Id, Description FROM OrderItem WHERE Id IN :parentIds AND Description != null]) {
    oiDesc.put(oi.Id, oi.Description);
}

// Build fill-only updates.
List<Asset> updates = new List<Asset>();
for (Id aId : assetToRefIds.keySet()) {
    String lineDesc = null;
    for (Id refId : assetToRefIds.get(aId)) {
        if (oiDesc.containsKey(refId)) { lineDesc = oiDesc.get(refId); break; }
        Id parent = oidToParent.get(refId);
        if (parent != null && oiDesc.containsKey(parent)) { lineDesc = oiDesc.get(parent); break; }
    }
    if (String.isNotBlank(lineDesc)) {
        updates.add(new Asset(Id = aId, Description = lineDesc));
    }
}
System.debug('BACKFILL| resolvable updates: ' + updates.size() + ' of ' + assetIds.size());
// DRY RUN by default — set DO_UPDATE=true to commit.
Boolean DO_UPDATE = false;
if (DO_UPDATE && !updates.isEmpty()) {
    update updates;
    System.debug('BACKFILL| committed ' + updates.size() + ' asset descriptions');
} else {
    System.debug('BACKFILL| DRY RUN (no DML). Set DO_UPDATE=true to commit.');
    for (Asset a : updates) System.debug('BACKFILL|   ' + a.Id + ' <- ' + a.Description);
}
