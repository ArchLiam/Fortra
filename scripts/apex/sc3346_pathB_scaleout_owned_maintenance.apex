// SC-3346 Path B — catalog scale-out: make owned OneTime maintenance renewable AS ITSELF.
//
// For every New-Maintenance product that is OWNED as an installed Asset, this ensures a NON-DEFAULT
// "Term Based - Annual" selling-model option plus TermDefined
// PriceBookEntries that mirror the product's active OneTime PBEs (both books, every currency the
// product already sells in; IsDerived=true for USD, false otherwise; UnitPrice=0; IsActive=true).
//
// New business stays OneTime (the added selling model is non-default). This only makes each product
// ABLE to renew as a TermDefined node — the native RLM exact-Product2Id happy path that
// RenewalMaintenanceProvisionService relies on. Generalizes the proven BoKS pilot
// (PIA-PIA-RNM-PIAMBK) and mirrors the already-correct template DP-DLP-RNM-DGSNM.
//
// Scope = owned installed New-Maintenance products only (a customer can only renew what it owns).
// The ~1,540 unowned OneTime maintenance products have no live renewal defect and are a separate
// go-forward Batch pass (too many DML rows for one anonymous transaction).
//
//   DRY_RUN = true   -> reports exactly what WOULD change; performs NO DML.
//   DRY_RUN = false  -> performs the idempotent inserts (skips anything already present).
//
// Standard-book PBEs are inserted before Fortra-book PBEs (platform requires the standard-book entry
// before the custom-book entry for the same product/model/currency). Re-runnable: idempotent on both
// the selling-model option and each product|book|currency PBE. READ the debug output before trusting it.

Boolean DRY_RUN = true;                               // <-- flip to false to commit

Id TERM_ANNUAL_PSM = '0jPWC000000060b2AA';            // "Term Based - Annual" (TermDefined)
Id fortraBook   = [SELECT Id FROM Pricebook2 WHERE Name='Fortra Price Book' AND IsStandard=false LIMIT 1].Id;
Id standardBook = [SELECT Id FROM Pricebook2 WHERE IsStandard=true LIMIT 1].Id;

// 1) Owned installed New-Maintenance products.
Set<Id> ownedProductIds = new Set<Id>();
for (AggregateResult ar : [
    SELECT Product2Id pid
    FROM Asset
    WHERE Status = 'Installed' AND Product2.Fortra_Product_Type__c = 'New Maintenance'
    GROUP BY Product2Id]) {
  ownedProductIds.add((Id) ar.get('pid'));
}

// Process ALL owned products. Do NOT exclude "already renewable" ones: some carry a TermDefined
// selling model but INCOMPLETE PBE coverage (e.g. the BoKS pilot added only USD). Idempotency on the
// selling-model option and each product|book|currency PBE makes re-processing complete products a
// no-op while filling genuine currency gaps on partially-covered ones.
Set<Id> alreadyRenewable = new Set<Id>();           // informational only (reported, not excluded)
for (ProductSellingModelOption o : [
    SELECT Product2Id
    FROM ProductSellingModelOption
    WHERE Product2Id IN :ownedProductIds AND ProductSellingModel.SellingModelType = 'TermDefined']) {
  alreadyRenewable.add(o.Product2Id);
}
Set<Id> targetProductIds = new Set<Id>(ownedProductIds);

// Product codes for the report.
Map<Id, String> codeByProduct = new Map<Id, String>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE Id IN :targetProductIds]) {
  codeByProduct.put(p.Id, p.ProductCode);
}

// 2) Existing Term-Annual selling-model options on targets (idempotency).
Set<Id> psmoPresent = new Set<Id>();
for (ProductSellingModelOption o : [
    SELECT Product2Id
    FROM ProductSellingModelOption
    WHERE Product2Id IN :targetProductIds AND ProductSellingModelId = :TERM_ANNUAL_PSM]) {
  psmoPresent.add(o.Product2Id);
}

// 3) Currencies each target already sells in (from active OneTime PBEs, any book).
Map<Id, Set<String>> currenciesByProduct = new Map<Id, Set<String>>();
for (PricebookEntry pbe : [
    SELECT Product2Id, CurrencyIsoCode
    FROM PricebookEntry
    WHERE Product2Id IN :targetProductIds
      AND IsActive = true
      AND ProductSellingModel.SellingModelType = 'OneTime']) {
  if (!currenciesByProduct.containsKey(pbe.Product2Id)) {
    currenciesByProduct.put(pbe.Product2Id, new Set<String>());
  }
  currenciesByProduct.get(pbe.Product2Id).add(pbe.CurrencyIsoCode);
}

// 4) Existing TermDefined PBEs on targets (idempotency), keyed product|book|currency.
Set<String> pbePresent = new Set<String>();
for (PricebookEntry pbe : [
    SELECT Product2Id, Pricebook2Id, CurrencyIsoCode
    FROM PricebookEntry
    WHERE Product2Id IN :targetProductIds AND ProductSellingModelId = :TERM_ANNUAL_PSM]) {
  pbePresent.add(pbe.Product2Id + '|' + pbe.Pricebook2Id + '|' + pbe.CurrencyIsoCode);
}

// 5) Build the idempotent insert sets.
List<ProductSellingModelOption> psmoInserts = new List<ProductSellingModelOption>();
List<PricebookEntry> standardInserts = new List<PricebookEntry>();
List<PricebookEntry> fortraInserts = new List<PricebookEntry>();
List<String> report = new List<String>();
List<String> skippedNoPbe = new List<String>();
Integer productsTouched = 0;

for (Id pid : targetProductIds) {
  Set<String> currs = currenciesByProduct.get(pid);
  if (currs == null || currs.isEmpty()) {
    skippedNoPbe.add(codeByProduct.get(pid));       // owned but no active OneTime PBE to mirror
    continue;
  }
  productsTouched++;

  Boolean addsPsmo = !psmoPresent.contains(pid);
  if (addsPsmo) {
    psmoInserts.add(new ProductSellingModelOption(
        Product2Id = pid, ProductSellingModelId = TERM_ANNUAL_PSM, IsDefault = false));
  }

  Integer pbeAdds = 0;
  for (String c : currs) {
    Boolean derived = (c == 'USD');
    String sKey = pid + '|' + standardBook + '|' + c;
    String fKey = pid + '|' + fortraBook + '|' + c;
    if (!pbePresent.contains(sKey)) {
      standardInserts.add(new PricebookEntry(
          Product2Id = pid, Pricebook2Id = standardBook, ProductSellingModelId = TERM_ANNUAL_PSM,
          CurrencyIsoCode = c, UnitPrice = 0, IsDerived = derived, IsActive = true));
      pbeAdds++;
    }
    if (!pbePresent.contains(fKey)) {
      fortraInserts.add(new PricebookEntry(
          Product2Id = pid, Pricebook2Id = fortraBook, ProductSellingModelId = TERM_ANNUAL_PSM,
          CurrencyIsoCode = c, UnitPrice = 0, IsDerived = derived, IsActive = true));
      pbeAdds++;
    }
  }
  report.add(codeByProduct.get(pid) + ' : ' + currs.size() + ' currencies, +'
      + (addsPsmo ? '1 PSMO' : '0 PSMO') + ', +' + pbeAdds + ' PBEs');
}

System.debug(LoggingLevel.ERROR, '===== SC-3346 Path B catalog scale-out (' + (DRY_RUN ? 'DRY-RUN' : 'COMMIT') + ') =====');
System.debug(LoggingLevel.ERROR, 'owned New-Maint products: ' + ownedProductIds.size()
    + ' | already renewable (pre-run): ' + alreadyRenewable.size()
    + ' | owned targets processed: ' + targetProductIds.size()
    + ' | with mirrorable OneTime PBEs: ' + productsTouched
    + ' | owned-but-no-OneTime-PBE (skipped): ' + skippedNoPbe.size());
System.debug(LoggingLevel.ERROR, 'TO INSERT -> PSMOs: ' + psmoInserts.size()
    + ' | Standard PBEs: ' + standardInserts.size()
    + ' | Fortra PBEs: ' + fortraInserts.size()
    + ' | total DML rows: ' + (psmoInserts.size() + standardInserts.size() + fortraInserts.size()));
System.debug(LoggingLevel.ERROR, 'PER-PRODUCT:\n  ' + String.join(report, '\n  '));
if (!skippedNoPbe.isEmpty()) {
  System.debug(LoggingLevel.ERROR, 'SKIPPED (owned, no active OneTime PBE to mirror):\n  ' + String.join(skippedNoPbe, '\n  '));
}

if (!DRY_RUN) {
  if (!psmoInserts.isEmpty())     { insert psmoInserts; }
  if (!standardInserts.isEmpty()) { insert standardInserts; }   // standard book before custom book
  if (!fortraInserts.isEmpty())   { insert fortraInserts; }
  System.debug(LoggingLevel.ERROR, 'COMMITTED — ' + psmoInserts.size() + ' PSMOs, '
      + (standardInserts.size() + fortraInserts.size()) + ' PBEs inserted.');
} else {
  System.debug(LoggingLevel.ERROR, 'DRY-RUN only — no DML performed. Flip DRY_RUN=false to commit.');
}
System.debug(LoggingLevel.ERROR, '=================================================================');
