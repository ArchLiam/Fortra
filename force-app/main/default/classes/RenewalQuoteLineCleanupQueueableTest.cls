@IsTest
private class RenewalQuoteLineCleanupQueueableTest {

    @IsTest
    static void queueableExecute_noOpOnEmptyQuoteIds() {
        Test.startTest();
        System.enqueueJob(new RenewalQuoteLineCleanupQueueable(new Set<Id>()));
        Test.stopTest();
        System.assert(true, 'Empty quote set should complete without error');
    }

    @IsTest
    static void queueableRemovesCarryoverWhenRenewalMaintenanceExists() {
        Account account = new Account(Name = 'Queueable Cleanup Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Queueable Cleanup Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Queueable Cleanup Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;

        Product2 newMaintProduct = new Product2(
            Name = 'RNM-Q',
            ProductCode = 'RNM-Q-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = RenewalQuoteLineHandler.PRODUCT_TYPE_NEW_MAINTENANCE
        );
        Product2 renewalProduct = new Product2(
            Name = 'RRM-Q',
            ProductCode = 'RRM-Q-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE
        );
        insert new List<Product2>{ newMaintProduct, renewalProduct };

        PricebookEntry newMaintPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = newMaintProduct.Id,
            UnitPrice = 71,
            IsActive = true
        );
        PricebookEntry renewalPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = renewalProduct.Id,
            UnitPrice = 71,
            IsActive = true
        );
        insert new List<PricebookEntry>{ newMaintPbe, renewalPbe };

        insert new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = renewalPbe.Id,
                Product2Id = renewalProduct.Id,
                Quantity = 1,
                UnitPrice = 71
            ),
            new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = newMaintPbe.Id,
                Product2Id = newMaintProduct.Id,
                Quantity = 1,
                UnitPrice = 71
            )
        };

        Test.startTest();
        System.enqueueJob(new RenewalQuoteLineCleanupQueueable(new Set<Id>{ quote.Id }));
        Test.stopTest();

        List<QuoteLineItem> remaining = [
            SELECT Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId = :quote.Id
        ];
        System.assertEquals(1, remaining.size());
        System.assertEquals(
            RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE,
            remaining[0].Product2.Fortra_Product_Type__c
        );
    }
}