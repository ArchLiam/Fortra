// SC-3346 Path B — post-commit verification of the owned-maintenance catalog scale-out. READ-ONLY.
// Invariants are scoped to distinguish CHANGE CORRECTNESS (products this run touched — those carrying a
// OneTime selling model) from PRE-EXISTING reference state (TermDefined-only products). No DML.

Id TERM_ANNUAL_PSM = '0jPWC000000060b2AA';            // "Term Based - Annual" (TermDefined)
Id fortraBook   = [SELECT Id FROM Pricebook2 WHERE Name='Fortra Price Book' AND IsStandard=false LIMIT 1].Id;
Id standardBook = [SELECT Id FROM Pricebook2 WHERE IsStandard=true LIMIT 1].Id;
List<String> out = new List<String>();

// Owned installed New-Maintenance products (renewal-eligible universe).
Set<Id> owned = new Set<Id>();
for (AggregateResult ar : [
    SELECT Product2Id pid FROM Asset
    WHERE Status='Installed' AND Product2.Fortra_Product_Type__c='New Maintenance'
    GROUP BY Product2Id]) {
  owned.add((Id) ar.get('pid'));
}

// Products this run could have TOUCHED = owned products that carry a OneTime selling model
// (new-business products). TermDefined-only products (reference-correct) are NOT touched.
Set<Id> hasOneTimePsmo = new Set<Id>();
Set<Id> hasTdPsmo = new Set<Id>();
Integer oneTimeNotDefault = 0, termAnnualDefaultOnTouched = 0;
for (ProductSellingModelOption o : [
    SELECT Product2Id, IsDefault, ProductSellingModelId, ProductSellingModel.SellingModelType
    FROM ProductSellingModelOption WHERE Product2Id IN :owned]) {
  if (o.ProductSellingModel.SellingModelType=='OneTime') {
    hasOneTimePsmo.add(o.Product2Id);
    if (o.IsDefault!=true) oneTimeNotDefault++;
  }
  if (o.ProductSellingModel.SellingModelType=='TermDefined') hasTdPsmo.add(o.Product2Id);
}
// Re-scan only touched products for a DEFAULT Term-Annual (my inserts must be non-default).
for (ProductSellingModelOption o : [
    SELECT Product2Id FROM ProductSellingModelOption
    WHERE Product2Id IN :hasOneTimePsmo AND ProductSellingModelId=:TERM_ANNUAL_PSM AND IsDefault=true]) {
  termAnnualDefaultOnTouched++;
}

// INV-1: EVERY owned product now carries a TermDefined selling model (can renew as itself).
out.add((hasTdPsmo.size()==owned.size() ? 'PASS' : 'FAIL')
    + ' INV-1 renewability: '+hasTdPsmo.size()+' / '+owned.size()+' owned products have a TermDefined model');

// INV-2: new business unaffected on TOUCHED products — none of my Term-Annual options became default.
out.add((termAnnualDefaultOnTouched==0 ? 'PASS' : 'FAIL')
    + ' INV-2 no default flip: '+termAnnualDefaultOnTouched+' touched products have a DEFAULT Term-Annual (must be 0)'
    + '  [INFO pre-existing: '+oneTimeNotDefault+' owned products have a non-default OneTime option]');

// Gather Term-Annual TermDefined PBEs on all owned products; split correctness by touched vs reference.
Map<Id, Set<String>> oneTimeCcy = new Map<Id, Set<String>>();
for (PricebookEntry p : [
    SELECT Product2Id, CurrencyIsoCode FROM PricebookEntry
    WHERE Product2Id IN :hasOneTimePsmo AND IsActive=true
      AND ProductSellingModel.SellingModelType='OneTime']) {
  if (!oneTimeCcy.containsKey(p.Product2Id)) oneTimeCcy.put(p.Product2Id, new Set<String>());
  oneTimeCcy.get(p.Product2Id).add(p.CurrencyIsoCode);
}
Set<String> tdPresent = new Set<String>();          // product|book|currency (touched products)
Map<String,Integer> tdDup = new Map<String,Integer>();
Integer usdNotDerivedTouched = 0, nonUsdDerivedTouched = 0, usdNotDerivedRef = 0;
for (PricebookEntry p : [
    SELECT Product2Id, Pricebook2Id, CurrencyIsoCode, IsDerived FROM PricebookEntry
    WHERE Product2Id IN :owned AND ProductSellingModelId=:TERM_ANNUAL_PSM AND IsActive=true]) {
  Boolean touched = hasOneTimePsmo.contains(p.Product2Id);
  if (touched) {
    String k = p.Product2Id+'|'+p.Pricebook2Id+'|'+p.CurrencyIsoCode;
    tdPresent.add(k);
    tdDup.put(k, (tdDup.containsKey(k)?tdDup.get(k):0)+1);
    if (p.CurrencyIsoCode=='USD' && p.IsDerived!=true) usdNotDerivedTouched++;
    if (p.CurrencyIsoCode!='USD' && p.IsDerived==true) nonUsdDerivedTouched++;
  } else if (p.CurrencyIsoCode=='USD' && p.IsDerived!=true) {
    usdNotDerivedRef++;                              // pre-existing reference PBE, not created by this run
  }
}

// INV-3: PBE completeness on touched products — every OneTime (product,currency) has TermDefined in BOTH books.
Integer gaps = 0; List<String> gapEx = new List<String>();
for (Id pid : oneTimeCcy.keySet()) {
  for (String c : oneTimeCcy.get(pid)) {
    if (!tdPresent.contains(pid+'|'+standardBook+'|'+c)) { gaps++; if (gapEx.size()<8) gapEx.add(pid+' STD '+c); }
    if (!tdPresent.contains(pid+'|'+fortraBook+'|'+c))   { gaps++; if (gapEx.size()<8) gapEx.add(pid+' FOR '+c); }
  }
}
out.add((gaps==0 ? 'PASS' : 'FAIL')+' INV-3 PBE completeness: '+gaps+' missing TermDefined PBEs on touched products'
    + (gaps>0 ? ' e.g. '+String.join(gapEx,'; ') : ''));

// INV-4: IsDerived pattern correct on TOUCHED products (USD true / non-USD false).
out.add(((usdNotDerivedTouched==0 && nonUsdDerivedTouched==0) ? 'PASS' : 'FAIL')
    + ' INV-4 IsDerived on touched: USD-not-derived='+usdNotDerivedTouched+', nonUSD-derived='+nonUsdDerivedTouched
    + ' (both must be 0)  [INFO pre-existing reference USD-not-derived: '+usdNotDerivedRef+']');

// INV-5: no duplicate active Term-Annual TermDefined PBE per product|book|currency (touched).
Integer dups = 0; for (Integer n : tdDup.values()) if (n>1) dups++;
out.add((dups==0 ? 'PASS' : 'FAIL')+' INV-5 duplicates: '+dups+' (product,book,currency) keys with >1 active TD PBE');

// INV-6: deletion — the two orphan classes are gone; the live service remains.
Integer orphans = [SELECT COUNT() FROM ApexClass WHERE Name IN ('RenewalMaintenanceProvisioner','RenewalMaintenanceProvisionerTest')];
Integer service = [SELECT COUNT() FROM ApexClass WHERE Name='RenewalMaintenanceProvisionService'];
out.add(((orphans==0 && service==1) ? 'PASS' : 'FAIL')+' INV-6 deletion: orphan classes='+orphans+' (want 0), service class='+service+' (want 1)');

System.debug(LoggingLevel.ERROR, '===== SC-3346 Path B scale-out VERIFICATION (scoped) =====\n  '+String.join(out,'\n  ')
   + '\n=================================================');
