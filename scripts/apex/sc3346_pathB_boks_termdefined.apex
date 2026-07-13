// SC-3346 Path B pilot — make BoKS maintenance (PIA-PIA-RNM-PIAMBK) renewable AS ITSELF.
// Adds a Term-Based-Annual selling-model option + derived TermDefined PBEs (Fortra + Standard books, USD),
// mirroring the already-correct RNM-TermDefined template DP-DLP-RNM-DGSNM.
// NON-DEFAULT: new business stays OneTime; this only makes the product ABLE to renew as a TermDefined node.
// Idempotent: skips anything already present. READ the debug output before trusting it.

Product2 prod = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode='PIA-PIA-RNM-PIAMBK' LIMIT 1];
Id TERM_ANNUAL_PSM = '0jPWC000000060b2AA';            // "Term Based - Annual" (TermDefined)
Id fortraBook   = [SELECT Id FROM Pricebook2 WHERE Name='Fortra Price Book' AND IsStandard=false LIMIT 1].Id;
Id standardBook = [SELECT Id FROM Pricebook2 WHERE IsStandard=true LIMIT 1].Id;

List<String> log = new List<String>();

// 1) ProductSellingModelOption (Term-Based-Annual, non-default)
List<ProductSellingModelOption> psmoEx = [
  SELECT Id FROM ProductSellingModelOption
  WHERE Product2Id=:prod.Id AND ProductSellingModelId=:TERM_ANNUAL_PSM LIMIT 1];
if (psmoEx.isEmpty()) {
  insert new ProductSellingModelOption(
     Product2Id=prod.Id, ProductSellingModelId=TERM_ANNUAL_PSM, IsDefault=false);
  log.add('CREATED PSMO Term-Based-Annual (non-default)');
} else { log.add('PSMO already present'); }

// 2) Derived TermDefined PBEs (mirror template: IsDerived=true, UnitPrice=0), USD, both books
for (Id book : new List<Id>{ standardBook, fortraBook }) {   // Standard first (platform requires it before custom-book PBE)
  List<PricebookEntry> ex = [
    SELECT Id FROM PricebookEntry
    WHERE Product2Id=:prod.Id AND Pricebook2Id=:book
      AND ProductSellingModelId=:TERM_ANNUAL_PSM AND CurrencyIsoCode='USD' LIMIT 1];
  if (ex.isEmpty()) {
    insert new PricebookEntry(
      Product2Id=prod.Id, Pricebook2Id=book, ProductSellingModelId=TERM_ANNUAL_PSM,
      CurrencyIsoCode='USD', UnitPrice=0, IsDerived=true, IsActive=true);
    log.add('CREATED TermDefined PBE in book '+book);
  } else { log.add('PBE already present in book '+book); }
}

System.debug(LoggingLevel.ERROR, '===== SC-3346 Path B catalog change (PIA-PIA-RNM-PIAMBK) =====\n  '
   + String.join(log, '\n  ')
   + '\n============================================================');
