/**
 * @description Tests for RenewalQuoteActionStamp (SC-3346/SC-3404 born-net Fix Path A).
 *   Validates the STAMP logic (a Type='Renew' QuoteAction is minted/reused and linked to QA-less
 *   renewal-maintenance lines, preferring the owned New-Maintenance asset, else Perpetual).
 *
 *   NOTE: this validates the stamp wiring, NOT the end-to-end 67.38 commit — that requires the live
 *   RLM pricing engine and is the UAT acceptance test in the README. Test-data construction mirrors
 *   COLAUpliftTest (standard pricebook + plain inserts). If the after-insert async Queueables
 *   (RenewalAssetQuantityHandler / RenewalQuoteLineHandler) interfere in your org's test context,
 *   align setup with the existing renewal TestDataFactory or bypass those handlers.
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

    private static QuoteLineItem insertRenewalMaintLine(Ctx c) {
        QuoteLineItem qli = new QuoteLineItem(QuoteId = c.quote.Id, PricebookEntryId = c.rrmPbe.Id,
            Quantity = 1, UnitPrice = 0); // QA-less, as the configurator auto-adds it
        insert qli;
        return qli;
    }

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

    @isTest
    static void noOwnedAsset_noStamp() {
        Ctx c = baseSetup(false, false); // owns nothing in the category
        Test.startTest();
        QuoteLineItem qli = insertRenewalMaintLine(c);
        Test.stopTest();

        QuoteLineItem after = [SELECT QuoteActionId FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(null, after.QuoteActionId, 'No owned asset -> no stamp (left for review)');
    }

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
