/**
 * @description Go-forward catalog completion for "renew maintenance as itself": for every active
 *              New-Maintenance product that has no TermDefined selling model, adds a NON-DEFAULT
 *              annual TermDefined selling-model option plus TermDefined PricebookEntries that mirror
 *              the product's active OneTime entries (same book, currency, price, and derived flag).
 *              New business is unaffected (the option is non-default). Additive and idempotent: a
 *              re-run inserts nothing, and it touches only Product2 / ProductSellingModelOption /
 *              PricebookEntry — never Quote / Order / Asset — so it cannot hit the transaction lock
 *              or desync downstream records. Runs in scopes small enough to stay well under the DML
 *              row limit; construct with dryRun=true to project counts without writing.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalMaintenanceCatalogProvisionBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final String FPT_NEW_MAINTENANCE = 'New Maintenance';
    private static final String SM_ONETIME          = 'OneTime';
    private static final String SM_TERMDEFINED      = 'TermDefined';
    private static final String TERM_UNIT_ANNUAL    = 'Annual';

    private final Boolean dryRun;
    private final Id termAnnualPsmId;
    private final Id standardBookId;

    public Integer productsProcessed = 0;
    public Integer psmosStaged = 0;
    public Integer pbesStaged = 0;

    /**
     * @description Constructs the batch.
     * @param dryRun When true, projects counts into the stateful tallies and performs NO DML.
     */
    public RenewalMaintenanceCatalogProvisionBatch(Boolean dryRun) {
        this.dryRun = dryRun == true;
        this.termAnnualPsmId = [
            SELECT Id FROM ProductSellingModel
            WHERE SellingModelType = :SM_TERMDEFINED AND PricingTerm = 1
              AND PricingTermUnit = :TERM_UNIT_ANNUAL AND Status = 'Active'
            LIMIT 1
        ].Id;
        this.standardBookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }

    /**
     * @description Selects active New-Maintenance products that carry no TermDefined selling model.
     * @param ctx The batch context.
     * @return A locator over the target products.
     */
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Product2
            WHERE Fortra_Product_Type__c = :FPT_NEW_MAINTENANCE AND IsActive = true
              AND Id NOT IN (
                  SELECT Product2Id FROM ProductSellingModelOption
                  WHERE ProductSellingModel.SellingModelType = :SM_TERMDEFINED)
        ]);
    }

    /**
     * @description For each product with active OneTime entries, stages a non-default annual TermDefined
     *              option and mirror PricebookEntries, idempotently. Standard-book entries are inserted
     *              before custom-book entries (platform ordering).
     * @param ctx The batch context.
     * @param scope The product chunk.
     */
    public void execute(Database.BatchableContext ctx, List<Product2> scope) {
        Set<Id> productIds = (new Map<Id, Product2>(scope)).keySet();

        Set<Id> psmoPresent = new Set<Id>();
        for (ProductSellingModelOption o : [
                SELECT Product2Id FROM ProductSellingModelOption
                WHERE Product2Id IN :productIds AND ProductSellingModelId = :termAnnualPsmId]) {
            psmoPresent.add(o.Product2Id);
        }

        Set<String> pbePresent = new Set<String>();
        for (PricebookEntry pbe : [
                SELECT Product2Id, Pricebook2Id, CurrencyIsoCode FROM PricebookEntry
                WHERE Product2Id IN :productIds AND ProductSellingModelId = :termAnnualPsmId]) {
            pbePresent.add(cellKey(pbe.Product2Id, pbe.Pricebook2Id, pbe.CurrencyIsoCode));
        }

        List<PricebookEntry> oneTimePbes = [
            SELECT Product2Id, Pricebook2Id, CurrencyIsoCode, UnitPrice, IsDerived
            FROM PricebookEntry
            WHERE Product2Id IN :productIds AND IsActive = true
              AND ProductSellingModel.SellingModelType = :SM_ONETIME
        ];

        Set<Id> productsWithPbes = new Set<Id>();
        for (PricebookEntry ot : oneTimePbes) {
            productsWithPbes.add(ot.Product2Id);
        }

        List<ProductSellingModelOption> psmoInserts = new List<ProductSellingModelOption>();
        for (Id pid : productsWithPbes) {
            if (!psmoPresent.contains(pid)) {
                psmoInserts.add(new ProductSellingModelOption(
                    Product2Id = pid, ProductSellingModelId = termAnnualPsmId, IsDefault = false));
            }
        }

        List<PricebookEntry> standardInserts = new List<PricebookEntry>();
        List<PricebookEntry> customInserts = new List<PricebookEntry>();
        for (PricebookEntry ot : oneTimePbes) {
            if (pbePresent.contains(cellKey(ot.Product2Id, ot.Pricebook2Id, ot.CurrencyIsoCode))) {
                continue;
            }
            PricebookEntry mirror = new PricebookEntry(
                Product2Id = ot.Product2Id, Pricebook2Id = ot.Pricebook2Id,
                ProductSellingModelId = termAnnualPsmId, CurrencyIsoCode = ot.CurrencyIsoCode,
                UnitPrice = ot.UnitPrice, IsDerived = ot.IsDerived, IsActive = true);
            if (ot.Pricebook2Id == standardBookId) {
                standardInserts.add(mirror);
            } else {
                customInserts.add(mirror);
            }
        }

        productsProcessed += productsWithPbes.size();
        psmosStaged += psmoInserts.size();
        pbesStaged += standardInserts.size() + customInserts.size();

        if (dryRun) {
            return;
        }
        if (!psmoInserts.isEmpty())     { insert psmoInserts; }
        if (!standardInserts.isEmpty()) { insert standardInserts; }   // standard book before custom book
        if (!customInserts.isEmpty())   { insert customInserts; }
    }

    /**
     * @description Logs the run tallies.
     * @param ctx The batch context.
     */
    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.ERROR, '===== RenewalMaintenanceCatalogProvisionBatch ('
            + (dryRun ? 'DRY-RUN' : 'COMMIT') + ') =====\n'
            + '  products processed: ' + productsProcessed + '\n'
            + '  PSMOs ' + (dryRun ? 'projected' : 'inserted') + ': ' + psmosStaged + '\n'
            + '  PBEs ' + (dryRun ? 'projected' : 'inserted') + ': ' + pbesStaged
            + '\n==================================================');
    }

    private static String cellKey(Id productId, Id bookId, String currencyIsoCode) {
        return productId + '|' + bookId + '|' + currencyIsoCode;
    }
}
