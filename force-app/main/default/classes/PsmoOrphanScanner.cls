/**
 * @description Stateful batch job that scans PricebookEntry rows for
 *              (Product2, ProductSellingModel) combinations that lack a matching
 *              ProductSellingModelOption, reporting the count and sample of such orphans.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public class PsmoOrphanScanner implements Database.Batchable<sObject>, Database.Stateful {
    public Set<String> existingPsmoKeys = new Set<String>();
    public Set<String> pbeKeysProcessed = new Set<String>();
    public Integer orphanCount = 0;
    public Integer totalPbeProcessed = 0;
    public List<String> sampleOrphans = new List<String>();
    
    /**
     * @description Pre-loads all existing ProductSellingModelOption records into a set of
     *              Product2Id|ProductSellingModelId keys used to detect orphaned combinations.
     */
    public PsmoOrphanScanner() {
        for (ProductSellingModelOption psmo : [
            SELECT Product2Id, ProductSellingModelId 
            FROM ProductSellingModelOption
        ]) {
            existingPsmoKeys.add(psmo.Product2Id + '|' + psmo.ProductSellingModelId);
        }
        System.debug('Pre-loaded PSMO keys: ' + existingPsmoKeys.size());
    }
    
    /**
     * @description Returns the query locator selecting all PricebookEntry rows that carry a
     *              ProductSellingModelId, forming the scope of the scan.
     * @param ctx the batch execution context
     * @return a query locator over PricebookEntry rows with a non-null ProductSellingModelId
     */
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Product2Id, ProductSellingModelId
            FROM PricebookEntry
            WHERE ProductSellingModelId != null
        ]);
    }
    
    /**
     * @description Processes a batch of PricebookEntry rows, tracking distinct
     *              Product2Id|ProductSellingModelId keys and counting those with no matching
     *              ProductSellingModelOption while retaining up to 20 sample orphan keys.
     * @param ctx the batch execution context
     * @param scope the current batch of PricebookEntry records to evaluate
     */
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
    
    /**
     * @description Emits debug logs summarizing the scan: total PBE rows processed, distinct
     *              combinations, combos satisfied by existing PSMO, orphan count, and sample keys.
     * @param ctx the batch execution context
     */
    public void finish(Database.BatchableContext ctx) {
        System.debug('=== PSMO ORPHAN SCAN COMPLETE ===');
        System.debug('Total PBE rows processed: ' + totalPbeProcessed);
        System.debug('Distinct (Prod,PSM) combos in PBE: ' + pbeKeysProcessed.size());
        System.debug('Combos satisfied by existing PSMO: ' + (pbeKeysProcessed.size() - orphanCount));
        System.debug('Combos with NO matching PSMO (orphan): ' + orphanCount);
        System.debug('Sample orphan keys: ' + JSON.serializePretty(sampleOrphans));
    }
}