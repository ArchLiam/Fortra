// SC-3346 Path B proof: renew maintenance AS ITSELF.
// Add an RNM-PIAMBK line on its NEW Term-Based-Annual (TermDefined) model, with a Renew QuoteAction sourcing
// the owned RNM-PIAMBK asset -> EXACT Product2Id match (native happy path). Then reprice should commit the COLA net.
Id Q         = '0Q0WC000003JkyH0AS';          // fresh BoKS renewal
Id RNM_ASSET = '02iWC000008dekAYAQ';          // owned PIA-PIA-RNM-PIAMBK (OneTime) asset, Price 71
Id RNM_TD_PBE= '01uWC000007EEIQYA4';          // PIA-PIA-RNM-PIAMBK Fortra Term-Based-Annual (TermDefined) USD (just created)
PricebookEntry pbe = [SELECT Product2Id FROM PricebookEntry WHERE Id=:RNM_TD_PBE];
try {
  QuoteAction qa = new QuoteAction(QuoteId=Q, Type='Renew', SourceAssetId=RNM_ASSET);
  insert qa;
  QuoteLineItem qli = new QuoteLineItem(
      QuoteId=Q, PricebookEntryId=RNM_TD_PBE, Product2Id=pbe.Product2Id, Quantity=1, QuoteActionId=qa.Id);
  insert qli;
  QuoteLineItem c = [
    SELECT Product2.ProductCode, Fortra_Product_Type__c, QuoteActionId, QuoteAction.Type,
           QuoteAction.SourceAsset.Product2.ProductCode, NetUnitPrice, UnitPrice
    FROM QuoteLineItem WHERE Id=:qli.Id];
  System.debug(LoggingLevel.ERROR, '========================================'
    + '\nPATH B line added (renew-as-itself, EXACT match)'
    + '\n  product   : ' + c.Product2.ProductCode + ' (' + c.Fortra_Product_Type__c + ')'
    + '\n  QA type   : ' + c.QuoteAction.Type
    + '\n  QA source : ' + c.QuoteAction.SourceAsset.Product2.ProductCode + '  <- should equal the line product'
    + '\n  UnitPrice : ' + c.UnitPrice + '   NetUnitPrice: ' + c.NetUnitPrice
    + '\n========================================');
} catch(Exception e) {
  System.debug(LoggingLevel.ERROR, 'FAIL ['+e.getTypeName()+' L'+e.getLineNumber()+']: '+e.getMessage());
}
