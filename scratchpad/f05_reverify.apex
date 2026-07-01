Set<Id> assetIds = new Set<Id>{
    '02iWC000007RVDNYA4','02iWC000007RVDOYA4','02iWC000007RVDPYA4','02iWC000007RVDQYA4'
};
List<AssetContractQueryHelper.AssetContractData> res = AssetContractQueryHelper.queryAssetContracts(assetIds);
System.debug('F05_RESULT_COUNT=' + res.size());
Set<Id> covered = new Set<Id>();
for (AssetContractQueryHelper.AssetContractData d : res) {
    covered.add(d.assetId);
    System.debug('WRAPPER assetId=' + d.assetId + ' contractId=' + d.contractId + ' pct=' + d.colaOverridePercent);
}
System.debug('F05_DISTINCT_ASSETS_COVERED=' + covered.size());
Set<Id> missing = new Set<Id>(assetIds);
missing.removeAll(covered);
System.debug('F05_MISSING_ASSETS=' + missing);
