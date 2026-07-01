public class PsmoOrphanScanner implements Database.Batchable<sObject>, Database.Stateful {
    public Set<String> existingPsmoKeys = new Set<String>();
    public Set<String> pbeKeysProcessed = new Set<String>();
    public Integer orphanCount = 0;
    public Integer totalPbeProcessed = 0;
    public List<String> sampleOrphans = new List<String>();
    
    public PsmoOrphanScanner() {
        for (ProductSellingModelOption psmo : [
            SELECT Product2Id, ProductSellingModelId 
            FROM ProductSellingModelOption
        ]) {
            existingPsmoKeys.add(psmo.Product2Id + '|' + psmo.ProductSellingModelId);
        }
        System.debug('Pre-loaded PSMO keys: ' + existingPsmoKeys.size());
    }
    
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Product2Id, ProductSellingModelId
            FROM PricebookEntry
            WHERE ProductSellingModelId != null
        ]);
    }
    
    public void execute(Database.BatchableContext ctx, List<PricebookEntry> scope) {
        for (PricebookEntry pbe : scope) {
            totalPbeProcessed++;
            String key = pbe.Product2Id + '|' + pbe.ProductSellingModelId;
            if (pbeKeysProcessed.contains(key)) continue;
            pbeKeysProcessed.add(key);
            
            if (!existingPsmoKeys.contains(key)) {
                orphanCount++;
                if (sampleOrphans.size() < 20) {
                    sampleOrphans.add(key);
                }
            }
        }
    }
    
    public void finish(Database.BatchableContext ctx) {
        System.debug('=== PSMO ORPHAN SCAN COMPLETE ===');
        System.debug('Total PBE rows processed: ' + totalPbeProcessed);
        System.debug('Distinct (Prod,PSM) combos in PBE: ' + pbeKeysProcessed.size());
        System.debug('Combos satisfied by existing PSMO: ' + (pbeKeysProcessed.size() - orphanCount));
        System.debug('Combos with NO matching PSMO (orphan): ' + orphanCount);
        System.debug('Sample orphan keys: ' + JSON.serializePretty(sampleOrphans));
    }
}