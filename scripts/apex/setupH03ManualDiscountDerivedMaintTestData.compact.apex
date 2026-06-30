// H-03 Manual discount on derived maintenance line (V21 "Manual Discount - Derived Maintenance" group).
// Clones the standing BoKS derived-pricing demo quote 0Q0WC000003FKRJ0A4 (license PIA-PIA-NRPS-PIAP 355
// + derived New-Maint PIA-PIA-RNM-PIAMBK net 71 = 0.20x355) into a fresh throwaway quote, then sets a
// manual percent Discount on the derived maintenance line. QLIAs are added via REST afterward (managed sObject).
// Expected after reprice: license net stays 355 (contributor base intact); maintenance net = 71 x (1 - Discount/100).
Savepoint sp = Database.setSavepoint();
try {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.AllowSave = true;
    dml.DuplicateRuleHeader.RunAsCurrentUser = true;

    String TAG = Datetime.now().format('yyyy-MM-dd HH:mm') + '-' + String.valueOf(Crypto.getRandomInteger()).right(4);
    Decimal DISC = 20; // manual percent discount on the derived maintenance line

    Quote src = [SELECT Id, OpportunityId, Pricebook2Id, CurrencyIsoCode, BillingName, BillingStreet,
                        BillingCity, BillingState, BillingPostalCode, BillingCountry, ContactId
                 FROM Quote WHERE Id = '0Q0WC000003FKRJ0A4' LIMIT 1];

    Quote q = new Quote(
        Name = 'H-03 ManualDisc Derived Maint ' + TAG,
        OpportunityId = src.OpportunityId,
        Pricebook2Id = src.Pricebook2Id,
        CurrencyIsoCode = src.CurrencyIsoCode,
        ContactId = src.ContactId,
        ExpirationDate = Date.today().addDays(30),
        Status = 'Draft'
    );
    q.setOptions(dml);
    insert q;

    List<QuoteLineItem> srcLines = [SELECT Id, Product2Id, PricebookEntryId, Quantity, UnitPrice,
                                           Fortra_Product_Type__c, Product2.ProductCode
                                    FROM QuoteLineItem WHERE QuoteId = :src.Id ORDER BY Product2.ProductCode];

    List<QuoteLineItem> newLines = new List<QuoteLineItem>();
    QuoteLineItem qli;
    for (QuoteLineItem s : srcLines) {
        qli = new QuoteLineItem(
            QuoteId = q.Id,
            Product2Id = s.Product2Id,
            PricebookEntryId = s.PricebookEntryId,
            Quantity = s.Quantity,
            UnitPrice = s.UnitPrice
        );
        // manual percent discount ONLY on the derived maintenance line
        if (s.Fortra_Product_Type__c == 'New Maintenance') {
            qli.Discount = DISC;
        }
        qli.setOptions(dml);
        newLines.add(qli);
    }
    insert newLines;

    // marker: scenario id + new quote URL + the two new QLI ids (license, maintenance) for the REST QLIA step
    String lic = '';
    String mnt = '';
    for (Integer i = 0; i < srcLines.size(); i++) {
        if (srcLines[i].Fortra_Product_Type__c == 'New Maintenance') { mnt = newLines[i].Id; }
        else { lic = newLines[i].Id; }
    }
    System.debug(LoggingLevel.ERROR, 'H-03_FIXTURE quote=https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/'
        + q.Id + '/view licenseQLI=' + lic + ' maintQLI=' + mnt + ' disc=' + DISC);
} catch (Exception e) {
    Database.rollback(sp);
    throw e;
}
