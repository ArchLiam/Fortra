/**
 * @description Verifies the RenewalQuoteActionStamp born-net stamp logic: a Type='Renew'
 *   QuoteAction is minted or reused and linked to QuoteAction-less renewal-maintenance lines,
 *   preferring the owned New-Maintenance asset and otherwise falling back to the Perpetual asset.
 *   Exercises the stamp wiring only, not the end-to-end pricing commit which requires the live RLM
 *   engine; test-data construction uses the standard pricebook with plain inserts.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class RenewalQuoteActionStampTest {

    private static final String CATEGORY = 'RQAS Test Category';

    private class Ctx {
        Account acct;
        Quote quote;
        Product2 rrmProduct;
        PricebookEntry rrmPbe;
    }

    /**
     * @description Builds the shared test fixture: an account, opportunity, active legal entity,
     *   renewal quote, a renewal-maintenance product with a $0 standard pricebook entry, and
     *   optionally the owned New-Maintenance and/or Perpetual assets used as stamp sources.
     * @param ownsNewMaint When true, inserts a New Maintenance product and owned asset for the account
     * @param ownsPerpetual When true, inserts a Perpetual product and owned asset for the account
     * @return The populated context holding the account, quote, and renewal-maintenance product/PBE
     */
    private static Ctx baseSetup(Boolean ownsNewMaint, Boolean ownsPerpetual) {
        Ctx c = new Ctx();
        c.acct = new Account(Name = 'RQAS Test Acct');
        insert c.acct;

        Opportunity opp = new Opportunity(Name = 'RQAS Opp', AccountId = c.acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;

        // Production quotes always carry a Legal Entity; the before-save flow
        // (Fortra_Quote_Line_Item_Populate_QL_With_Quote_Values) copies Quote.LegalEntityId
        // onto each QLI on insert — without it the QLI insert fails in test context.
        LegalEntity legalEntity = new LegalEntity(Name = 'RQAS Legal Entity', Status = 'Active');
        insert legalEntity;

        Id stdPb = Test.getStandardPricebookId();
        c.quote = new Quote(Name = 'RQAS Quote', OpportunityId = opp.Id, Pricebook2Id = stdPb,
            Quote_Type__c = 'Renewal', LegalEntityId = legalEntity.Id);
        insert c.quote;

        c.rrmProduct = new Product2(Name = 'RQAS RRM', ProductCode = 'RQAS-RRM', IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance', Solution_Category__c = CATEGORY);
        insert c.rrmProduct;
        c.rrmPbe = new PricebookEntry(Pricebook2Id = stdPb, Product2Id = c.rrmProduct.Id,
            UnitPrice = 0, IsActive = true);
        insert c.rrmPbe;

        List<Asset> assets = new List<Asset>();
        if (ownsNewMaint) {
            Product2 nm = new Product2(Name = 'RQAS RNM', ProductCode = 'RQAS-RNM', IsActive = true,
                Fortra_Product_Type__c = 'New Maintenance', Solution_Category__c = CATEGORY);
            insert nm;
            assets.add(new Asset(Name = 'RQAS RNM Asset', AccountId = c.acct.Id, Product2Id = nm.Id,
                Price = 62.48, Quantity = 1, Status = 'Installed'));
        }
        if (ownsPerpetual) {
            Product2 perp = new Product2(Name = 'RQAS Perp', ProductCode = 'RQAS-PERP', IsActive = true,
                Fortra_Product_Type__c = 'Perpetual', Solution_Category__c = CATEGORY);
            insert perp;
            assets.add(new Asset(Name = 'RQAS Perp Asset', AccountId = c.acct.Id, Product2Id = perp.Id,
                Price = 355, Quantity = 1, Status = 'Installed'));
        }
        if (!assets.isEmpty()) insert assets;
        return c;
    }

    /**
     * @description Inserts a single QuoteAction-less renewal-maintenance quote line item against the
     *   context's quote and renewal-maintenance pricebook entry, mirroring the configurator auto-add.
     * @param c The test context providing the quote and renewal-maintenance pricebook entry
     * @return The inserted renewal-maintenance quote line item
     */
    private static QuoteLineItem insertRenewalMaintLine(Ctx c) {
        QuoteLineItem qli = new QuoteLineItem(QuoteId = c.quote.Id, PricebookEntryId = c.rrmPbe.Id,
            Quantity = 1, UnitPrice = 0); // QA-less, as the configurator auto-adds it
        insert qli;
        return qli;
    }

    /**
     * @description Verifies that when the account owns both a New Maintenance and a Perpetual asset,
     *   the line is stamped with a Type='Renew' QuoteAction sourced from the New Maintenance asset.
     */
    @isTest
    static void stampsRenewQuoteAction_preferNewMaintenance() {
        Ctx c = baseSetup(true, true); // owns both -> prefer RNM
        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [
            SELECT QuoteActionId, QuoteAction.Type,
                   QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c
            FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertNotEquals(null, after.QuoteActionId, 'QuoteAction should be stamped');
        System.assertEquals('Renew', after.QuoteAction.Type, 'QA type should be Renew');
        System.assertEquals('New Maintenance',
            after.QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c,
            'Should prefer the New Maintenance (RNM) asset');
    }

    /**
     * @description Verifies that when the account owns only a Perpetual asset, the line is stamped
     *   with a QuoteAction sourced from that Perpetual asset.
     */
    @isTest
    static void fallsBackToPerpetual_whenNoNewMaint() {
        Ctx c = baseSetup(false, true); // owns only Perpetual
        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [
            SELECT QuoteActionId, QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c
            FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertNotEquals(null, after.QuoteActionId, 'Should stamp using the Perpetual asset');
        System.assertEquals('Perpetual',
            after.QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c);
    }

    /**
     * @description Verifies that when the account owns no eligible asset in the category, the line is
     *   left unstamped (no QuoteAction) for manual review.
     */
    @isTest
    static void noOwnedAsset_noStamp() {
        Ctx c = baseSetup(false, false); // owns nothing in the category
        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [SELECT QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(null, after.QuoteActionId, 'No owned asset -> no stamp (left for review)');
    }

    /**
     * @description Verifies that an existing Type='Renew' QuoteAction for the same quote and source
     *   asset is reused rather than duplicated when a matching renewal-maintenance line is inserted.
     */
    @isTest
    static void reusesExistingRenewQuoteAction() {
        Ctx c = baseSetup(true, false);
        Asset rnm = [SELECT Id FROM Asset WHERE AccountId = :c.acct.Id LIMIT 1];
        QuoteAction existing = new QuoteAction(QuoteId = c.quote.Id, Type = 'Renew', SourceAssetId = rnm.Id);
        insert existing;

        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [SELECT QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(existing.Id, after.QuoteActionId, 'Should reuse the existing Renew QA');
        System.assertEquals(1, [SELECT COUNT() FROM QuoteAction WHERE QuoteId = :c.quote.Id],
            'Should not create a duplicate QA');
    }

    /**
     * @description Verifies that a line whose product is not renewal-maintenance (e.g. Software) is
     *   not stamped with a QuoteAction.
     */
    @isTest
    static void skipsNonRenewalMaintenance() {
        Ctx c = baseSetup(true, false);
        c.rrmProduct.Fortra_Product_Type__c = 'Software';
        update c.rrmProduct;

        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [SELECT QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(null, after.QuoteActionId, 'Non renewal-maintenance line must not be stamped');
    }

    /**
     * @description Verifies that setting the RenewalQuoteActionStamp.bypass flag suppresses stamping
     *   so the inserted line receives no QuoteAction.
     */
    @isTest
    static void bypassFlag_skipsStamp() {
        Ctx c = baseSetup(true, false);
        RenewalQuoteActionStamp.bypass = true;

        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [SELECT QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(null, after.QuoteActionId, 'Bypass should skip stamping');
    }

    /**
     * @description Verifies bulk behavior: inserting 30 renewal-maintenance lines stamps every line
     *   while reusing a single QuoteAction shared across lines with the same quote and source asset.
     */
    @isTest
    static void bulk_stampsManyLinesSharingOneQA() {
        Ctx c = baseSetup(true, false);
        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < 30; i++) {
            qlis.add(new QuoteLineItem(QuoteId = c.quote.Id, PricebookEntryId = c.rrmPbe.Id,
                Quantity = 1, UnitPrice = 0));
        }
        Test.startTest();
        insert qlis;
        Test.stopTest();

        Integer stamped = [SELECT COUNT() FROM QuoteLineItem
                           WHERE QuoteId = :c.quote.Id AND QuoteActionId != null];
        System.assertEquals(30, stamped, 'All 30 lines should be stamped');
        System.assertEquals(1, [SELECT COUNT() FROM QuoteAction WHERE QuoteId = :c.quote.Id],
            'Lines sharing one (quote, asset) should reuse a single QA');
    }
}