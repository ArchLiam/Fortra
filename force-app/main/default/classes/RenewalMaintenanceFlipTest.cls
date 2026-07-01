/**
 * @description Tests for RenewalMaintenanceFlip (SC-3346/SC-3404 renewal-maintenance fix).
 *   Validates the flip of No-Change owned-maintenance carryover -> Renew + quantity. The end-to-end
 *   67.38 commit is validated by a UAT reprice (the engine isn't exercised in Apex tests).
 *   Setup mirrors COLAUpliftTest (LegalEntity + standard pricebook).
 */
@isTest
private class RenewalMaintenanceFlipTest {

    private static Quote buildRenewalQuote(String quoteType) {
        Account acct = new Account(Name = 'RMF Acct');
        insert acct;
        LegalEntity le = new LegalEntity(Name = 'RMF Legal Entity', Status = 'Active');
        insert le;
        Opportunity opp = new Opportunity(Name = 'RMF Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Quote q = new Quote(Name = 'RMF Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(), Quote_Type__c = quoteType, LegalEntityId = le.Id);
        insert q;
        return q;
    }

    private static QuoteLineItem addCarryoverLine(Quote q, String fortraType, String qaType, Decimal assetQty) {
        Id acctId = [SELECT AccountId FROM Quote WHERE Id = :q.Id].AccountId;
        Product2 prod = new Product2(Name = 'RMF ' + fortraType, ProductCode = 'RMF-' + fortraType.deleteWhitespace(),
            IsActive = true, Fortra_Product_Type__c = fortraType);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id, UnitPrice = 0, IsActive = true);
        insert pbe;
        Asset asset = new Asset(Name = 'RMF Asset', AccountId = acctId, Product2Id = prod.Id,
            Price = 62.48, Quantity = assetQty, Status = 'Installed');
        insert asset;
        QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = qaType, SourceAssetId = asset.Id);
        insert qa;
        // RLM rule: a No-Change line has Quantity=0 + StartQuantity>0 (the flip makes it Renew:
        // Quantity=asset qty, StartQuantity=0).
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Quantity = 0, StartQuantity = 1, UnitPrice = 0, QuoteActionId = qa.Id);
        insert qli;
        return qli;
    }

    @isTest
    static void flipsNoChangeMaintenanceToRenew() {
        Quote q = buildRenewalQuote('Renewal');
        QuoteLineItem qli = addCarryoverLine(q, 'New Maintenance', 'No Change', 3);

        Test.startTest();
        RenewalMaintenanceFlip.flipToRenew(new Set<Id>{ q.Id });
        Test.stopTest();

        QuoteAction afterQa = [SELECT Type FROM QuoteAction WHERE QuoteId = :q.Id LIMIT 1];
        System.assertEquals('Renew', afterQa.Type, 'QuoteAction should be flipped No Change -> Renew');
        QuoteLineItem afterLine = [SELECT StartQuantity, Quantity FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(0, afterLine.StartQuantity, 'A Renew line requires StartQuantity = 0');
        System.assertEquals(3, afterLine.Quantity, 'Renew quantity should be the source asset quantity');
    }

    @isTest
    static void skipsNonRenewalQuote() {
        Quote q = buildRenewalQuote('New'); // not a renewal
        addCarryoverLine(q, 'New Maintenance', 'No Change', 1);

        RenewalMaintenanceFlip.FlipRequest req = new RenewalMaintenanceFlip.FlipRequest();
        req.quoteId = q.Id;
        Test.startTest();
        RenewalMaintenanceFlip.flipInvocable(new List<RenewalMaintenanceFlip.FlipRequest>{ req });
        Test.stopTest();

        QuoteAction afterQa = [SELECT Type FROM QuoteAction WHERE QuoteId = :q.Id LIMIT 1];
        System.assertEquals('No Change', afterQa.Type, 'Non-renewal quote must not be flipped');
    }

    @isTest
    static void leavesAlreadyRenewAndOtherTypesAlone() {
        Quote q = buildRenewalQuote('Renewal');
        addCarryoverLine(q, 'Perpetual', 'No Change', 1); // not New Maintenance -> untouched

        Test.startTest();
        RenewalMaintenanceFlip.flipToRenew(new Set<Id>{ q.Id });
        Test.stopTest();

        QuoteAction afterQa = [SELECT Type FROM QuoteAction WHERE QuoteId = :q.Id LIMIT 1];
        System.assertEquals('No Change', afterQa.Type, 'Non New-Maintenance carryover must not be flipped');
    }

    @isTest
    static void nullAndEmptySafe() {
        RenewalMaintenanceFlip.flipToRenew(null);
        RenewalMaintenanceFlip.flipToRenew(new Set<Id>());
        RenewalMaintenanceFlip.flipInvocable(null);
        RenewalMaintenanceFlip.flipInvocable(new List<RenewalMaintenanceFlip.FlipRequest>());
    }
}