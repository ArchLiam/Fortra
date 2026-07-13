// SC-3346 — correct mis-mirrored TermDefined maintenance prices from the earlier owned-product scale-out.
// That scale-out hardcoded TD UnitPrice=$0 instead of mirroring the OneTime PBE, so static-priced
// (IsDerived=false) maintenance SKUs have $0 non-USD TD prices while their OneTime source carries real
// FX prices — a candidate to mis-price non-USD renewals (e.g. the live owned asset RPA-AUT-RNM-AMAONM GBP).
// This aligns each active annual TermDefined PBE's UnitPrice to its OneTime sibling (same product|book|
// currency) wherever they diverge and the OneTime price is non-zero. UnitPrice is updateable; IsDerived is
// NOT touched (the Standard-book USD IsDerived deviation is cosmetic — not the renewal book). Idempotent;
// DRY_RUN default true. READ the debug before committing.

Boolean DRY_RUN = true;                               // <-- flip to false to commit

Id TERM_ANNUAL_PSM = '0jPWC000000060b2AA';            // "Term Based - Annual"
Id ONETIME_PSM     = '0jPWC00000005yz2AA';            // "One Time"

// Scope to owned maintenance products (the scale-out set — where the $0-hardcode bug lives; the batch
// mirrored faithfully). Keeps query rows well under the governor limit.
Set<Id> ownedProds = new Set<Id>();
for (AggregateResult ar : [
        SELECT Product2Id pid FROM Asset
        WHERE Status = 'Installed' AND Product2.Fortra_Product_Type__c = 'New Maintenance'
        GROUP BY Product2Id]) {
    ownedProds.add((Id) ar.get('pid'));
}

// OneTime list price per product|book|currency (the mirror source of truth)
Map<String, Decimal> oneTimePrice = new Map<String, Decimal>();
for (PricebookEntry ot : [
        SELECT Product2Id, Pricebook2Id, CurrencyIsoCode, UnitPrice
        FROM PricebookEntry
        WHERE ProductSellingModelId = :ONETIME_PSM AND IsActive = true
          AND Product2Id IN :ownedProds]) {
    oneTimePrice.put(ot.Product2Id + '|' + ot.Pricebook2Id + '|' + ot.CurrencyIsoCode, ot.UnitPrice);
}

List<PricebookEntry> toFix = new List<PricebookEntry>();
List<String> report = new List<String>();
for (PricebookEntry td : [
        SELECT Id, Product2.ProductCode, Product2Id, Pricebook2Id, CurrencyIsoCode, UnitPrice
        FROM PricebookEntry
        WHERE ProductSellingModelId = :TERM_ANNUAL_PSM AND IsActive = true
          AND IsDerived = false        // a derived PBE's list price must stay $0; only price the static cells
          AND Product2Id IN :ownedProds]) {
    Decimal src = oneTimePrice.get(td.Product2Id + '|' + td.Pricebook2Id + '|' + td.CurrencyIsoCode);
    if (src != null && src > 0 && td.UnitPrice != src) {
        if (report.size() < 25) {
            report.add(td.Product2.ProductCode + ' ' + td.CurrencyIsoCode + ' : ' + td.UnitPrice + ' -> ' + src);
        }
        td.UnitPrice = src;
        toFix.add(td);
    }
}

System.debug(LoggingLevel.ERROR, '===== SC-3346 fix mirror prices (' + (DRY_RUN ? 'DRY-RUN' : 'COMMIT') + ') =====');
System.debug(LoggingLevel.ERROR, 'TermDefined PBE prices to correct: ' + toFix.size());
System.debug(LoggingLevel.ERROR, 'SAMPLE (first 25):\n  ' + String.join(report, '\n  '));

if (!DRY_RUN) {
    if (!toFix.isEmpty()) {
        update toFix;
        System.debug(LoggingLevel.ERROR, 'COMMITTED — ' + toFix.size() + ' TermDefined PBE prices aligned to OneTime.');
    } else {
        System.debug(LoggingLevel.ERROR, 'nothing to correct (already aligned).');
    }
} else {
    System.debug(LoggingLevel.ERROR, 'DRY-RUN only — no DML. Flip DRY_RUN=false to commit.');
}
System.debug(LoggingLevel.ERROR, '=================================================');
