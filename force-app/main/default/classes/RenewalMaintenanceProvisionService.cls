/**
 * @description Renews maintenance as itself: on a renewal quote, replaces each owned OneTime maintenance
 *              carryover line with the same product on a TermDefined selling model, born a Renew node
 *              sourcing that exact asset, so the pricing engine commits the uplifted net. Data-driven —
 *              works for any maintenance product that has a TermDefined PricebookEntry in the line's book
 *              and currency; requires no product-to-product mapping.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalMaintenanceProvisionService {

    public static Boolean bypass = false;

    private static final String FPT_NEW_MAINTENANCE = 'New Maintenance';
    private static final String SM_ONETIME          = 'OneTime';
    private static final String SM_TERMDEFINED      = 'TermDefined';
    private static final String TERM_UNIT_ANNUAL    = 'Annual';
    private static final String QA_RENEW            = 'Renew';

    // SC-3346 anti-false-green telemetry (Stage 0): cap the Warning detail well under the LongTextArea limit.
    @TestVisible
    private static final Integer MESSAGE_MAX = 30000;

    /**
     * @description Replaces OneTime maintenance carryover lines on the given quotes with same-product
     *              TermDefined Renew lines (born-net), then deletes the carryovers. Idempotent: once a
     *              carryover is replaced there is nothing left to act on, so a re-run is a no-op.
     * @param quoteIds The renewal quotes to provision.
     */
    public static void provision(Set<Id> quoteIds) {
        if (bypass || quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> carryovers = [
            SELECT Id, QuoteId, Quantity, StartDate, Product2Id, CurrencyIsoCode,
                   PricebookEntry.Pricebook2Id, QuoteAction.SourceAssetId,
                   Prior_Partner_Discount__c, Prior_Discretionary_Discount__c
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
              AND Product2.Fortra_Product_Type__c = :FPT_NEW_MAINTENANCE
              AND PricebookEntry.ProductSellingModel.SellingModelType = :SM_ONETIME
              AND QuoteActionId != NULL
              AND QuoteAction.SourceAssetId != NULL
        ];
        if (carryovers.isEmpty()) {
            return;
        }

        Map<String, Id> termDefinedPbeByKey = resolveTermDefinedPbes(carryovers);

        // Skip any carryover whose quote already carries a same-product/book/currency TermDefined line
        // (a prior partial run, or an RRM line). A second same-key line collides a product-keyed date map
        // in the pricing engine (NPE), and a re-run would otherwise duplicate the Renew line.
        Set<String> seenTermDefinedKeys = existingTermDefinedKeys(quoteIds);

        List<QuoteAction> quoteActionsToInsert = new List<QuoteAction>();
        List<QuoteLineItem> carryoversForAction = new List<QuoteLineItem>();
        List<QuoteLineItem> carryoversToDelete = new List<QuoteLineItem>();
        Set<String> missingTermDefinedPbeKeys = new Set<String>();
        for (QuoteLineItem carryover : carryovers) {
            String scopedKey = quoteScopedKey(
                carryover.QuoteId, carryover.Product2Id, carryover.PricebookEntry.Pricebook2Id, carryover.CurrencyIsoCode);
            Id termDefinedPbeId = termDefinedPbeByKey.get(
                pbeKey(carryover.Product2Id, carryover.PricebookEntry.Pricebook2Id, carryover.CurrencyIsoCode));
            if (termDefinedPbeId == null) {
                // SC-3346 anti-false-green: no active Annual TermDefined PricebookEntry for this
                // product|book|currency, so the maintenance line cannot become a renewable priced node
                // and would freeze at $0. Record it and surface it loudly after the loop instead of the
                // previous silent `continue` that hid the coverage/catalog gap ($0-mirror PBEs).
                missingTermDefinedPbeKeys.add(
                    pbeKey(carryover.Product2Id, carryover.PricebookEntry.Pricebook2Id, carryover.CurrencyIsoCode));
                continue;
            }
            if (seenTermDefinedKeys.contains(scopedKey)) {
                continue; // a same-key TermDefined line already exists/planned (benign; not a failure)
            }
            seenTermDefinedKeys.add(scopedKey); // dedup within this batch, too
            quoteActionsToInsert.add(new QuoteAction(
                QuoteId = carryover.QuoteId, Type = QA_RENEW, SourceAssetId = carryover.QuoteAction.SourceAssetId));
            carryoversForAction.add(carryover);
            carryoversToDelete.add(carryover);
        }
        if (!missingTermDefinedPbeKeys.isEmpty()) {
            publishMissingTermDefinedPbeWarning(missingTermDefinedPbeKeys);
        }
        if (quoteActionsToInsert.isEmpty()) {
            return;
        }

        bypass = true; // suppress this service on the re-fired trigger while it inserts/deletes
        try {
            insert quoteActionsToInsert;
            List<QuoteLineItem> termDefinedLines = new List<QuoteLineItem>();
            for (Integer i = 0; i < quoteActionsToInsert.size(); i++) {
                QuoteLineItem carryover = carryoversForAction[i];
                Id termDefinedPbeId = termDefinedPbeByKey.get(
                    pbeKey(carryover.Product2Id, carryover.PricebookEntry.Pricebook2Id, carryover.CurrencyIsoCode));
                Date startDate = carryover.StartDate != null ? carryover.StartDate : Date.today();
                termDefinedLines.add(new QuoteLineItem(
                    QuoteId          = carryover.QuoteId,
                    PricebookEntryId = termDefinedPbeId,
                    Product2Id       = carryover.Product2Id,
                    Quantity         = carryover.Quantity != null && carryover.Quantity > 0 ? carryover.Quantity : 1,
                    QuoteActionId    = quoteActionsToInsert[i].Id,
                    StartDate        = startDate,
                    // Carry the prior-year discount dollars so the COLA committer nets them off the
                    // gross asset base for the born first-renewal maintenance line (SC-3346 three-component).
                    Prior_Partner_Discount__c       = carryover.Prior_Partner_Discount__c,
                    Prior_Discretionary_Discount__c = carryover.Prior_Discretionary_Discount__c,
                    SubscriptionTerm = 1)); // EndDate/PricingTermCount are engine-derived, not writeable here
            }
            insert termDefinedLines;
            delete carryoversToDelete;
        } finally {
            bypass = false;
        }
    }

    /**
     * @description Resolves the TermDefined PricebookEntry for each carryover's product in the same
     *              pricebook and currency, keyed by product|book|currency.
     * @param carryovers The OneTime maintenance carryover lines being replaced.
     * @return A map of product|book|currency to the matching TermDefined PricebookEntry id.
     */
    private static Map<String, Id> resolveTermDefinedPbes(List<QuoteLineItem> carryovers) {
        Set<Id> productIds = new Set<Id>();
        Set<Id> bookIds = new Set<Id>();
        Set<String> currencies = new Set<String>();
        for (QuoteLineItem carryover : carryovers) {
            productIds.add(carryover.Product2Id);
            if (carryover.PricebookEntry.Pricebook2Id != null) bookIds.add(carryover.PricebookEntry.Pricebook2Id);
            if (carryover.CurrencyIsoCode != null) currencies.add(carryover.CurrencyIsoCode);
        }
        Map<String, Id> pbeByKey = new Map<String, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Product2Id IN :productIds AND Pricebook2Id IN :bookIds AND CurrencyIsoCode IN :currencies
              AND ProductSellingModel.SellingModelType = :SM_TERMDEFINED
              AND ProductSellingModel.PricingTermUnit = :TERM_UNIT_ANNUAL
              AND IsActive = true
        ]) {
            // Pin to the annual term so a same-key sub-annual PBE (Monthly/Quarterly) can never be picked
            // arbitrarily by the map's last-write-wins. Take the first annual PBE per key.
            String key = pbeKey(pbe.Product2Id, pbe.Pricebook2Id, pbe.CurrencyIsoCode);
            if (!pbeByKey.containsKey(key)) {
                pbeByKey.put(key, pbe.Id);
            }
        }
        return pbeByKey;
    }

    /**
     * @description Collects the product|book|currency keys of TermDefined lines already present on the
     *              given quotes, so the service never creates a duplicate Renew line for the same cell.
     * @param quoteIds The renewal quotes being provisioned.
     * @return The set of quote-scoped keys that already carry a TermDefined line.
     */
    private static Set<String> existingTermDefinedKeys(Set<Id> quoteIds) {
        Set<String> keys = new Set<String>();
        for (QuoteLineItem line : [
            SELECT QuoteId, Product2Id, CurrencyIsoCode, PricebookEntry.Pricebook2Id
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
              AND PricebookEntry.ProductSellingModel.SellingModelType = :SM_TERMDEFINED
        ]) {
            keys.add(quoteScopedKey(line.QuoteId, line.Product2Id, line.PricebookEntry.Pricebook2Id, line.CurrencyIsoCode));
        }
        return keys;
    }

    /**
     * @description Quote-scoped dedup key (quote|product|book|currency).
     * @param quoteId The quote.
     * @param productId The maintenance product.
     * @param bookId The pricebook.
     * @param currencyIsoCode The currency.
     * @return The composite key.
     */
    private static String quoteScopedKey(Id quoteId, Id productId, Id bookId, String currencyIsoCode) {
        return quoteId + '|' + pbeKey(productId, bookId, currencyIsoCode);
    }

    /**
     * @description Builds the composite key that includes currency (multi-currency correctness).
     * @param productId The maintenance product.
     * @param bookId The pricebook.
     * @param currencyIsoCode The currency.
     * @return The product|book|currency key.
     */
    private static String pbeKey(Id productId, Id bookId, String currencyIsoCode) {
        return productId + '|' + bookId + '|' + currencyIsoCode;
    }

    /**
     * @description SC-3346 anti-false-green telemetry (Stage 0). A maintenance carryover had no active
     *              Annual TermDefined PricebookEntry in its book+currency, so it cannot become a renewable
     *              priced node and would otherwise freeze at $0 silently. Publishes a Warning naming the
     *              affected product|book|currency cells so the coverage/catalog gap is visible and fixable
     *              (via the Pricing_Exception__e -> Exception_Log__c pipeline). Never throws.
     * @param missingKeys The product|book|currency keys with no matching active Annual TermDefined PBE.
     */
    @TestVisible
    private static void publishMissingTermDefinedPbeWarning(Set<String> missingKeys) {
        List<String> keys = new List<String>(missingKeys);
        String detail = String.join(keys, '; ');
        if (detail.length() > MESSAGE_MAX) {
            detail = detail.substring(0, MESSAGE_MAX);
        }
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c         = 'RenewalMaintenanceProvisionService',
            Severity__c       = 'Warning',
            Exception_Type__c = 'MissingTermDefinedPbe',
            Hook_Phase__c     = 'renewal-maint-provision',
            Message__c        = 'SC-3346: renewal maintenance cannot become a renewable priced node: no active '
                + 'Annual TermDefined PricebookEntry for ' + keys.size()
                + ' product|book|currency cell(s) -> ' + detail,
            Occurred_At__c    = System.now()
        ));
    }
}