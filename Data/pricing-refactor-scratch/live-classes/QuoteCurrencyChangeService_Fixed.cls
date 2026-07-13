public class QuoteCurrencyChangeService_Fixed {
    
    @InvocableMethod(label='Handle Quote Currency Change Fixed' 
                     description='Updates quote currency and recalculates quote lines')
    public static List<Result> handleCurrencyChange(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            res.quoteId = req.quoteId;
            
            try {
                // Get Quote details
                Quote quote = [SELECT Id, CurrencyIsoCode, OpportunityId, Pricebook2Id
                               FROM Quote 
                               WHERE Id = :req.quoteId];
                
                // First, update the Quote's currency
                quote.CurrencyIsoCode = req.newCurrency;
                update quote;
                
                // Get existing quote lines
                List<QuoteLineItem> oldLines = [SELECT Id, Product2Id, Quantity,
                                                 QuoteId, UnitPrice, TotalPrice,
                                                 ListPrice, Subtotal, Discount,
                                                 PricebookEntryId
                                                 FROM QuoteLineItem 
                                                 WHERE QuoteId = :req.quoteId];
                
                if (!oldLines.isEmpty()) {
                    // Get the product IDs
                    Set<Id> productIds = new Set<Id>();
                    for (QuoteLineItem line : oldLines) {
                        productIds.add(line.Product2Id);
                    }
                    
                    // Find PricebookEntries for the new currency
                    Map<Id, PricebookEntry> productToPBE = new Map<Id, PricebookEntry>();
                    for (PricebookEntry pbe : [SELECT Id, Product2Id, UnitPrice, CurrencyIsoCode
                                                FROM PricebookEntry
                                                WHERE Pricebook2Id = :quote.Pricebook2Id
                                                AND Product2Id IN :productIds
                                                AND CurrencyIsoCode = :req.newCurrency
                                                AND IsActive = true]) {
                        productToPBE.put(pbe.Product2Id, pbe);
                    }
                    
                    // Delete old lines first
                    delete oldLines;
                    
                    // Create new lines with correct currency PBEs
                    List<QuoteLineItem> newLines = new List<QuoteLineItem>();
                    
                    for (QuoteLineItem oldLine : oldLines) {
                        PricebookEntry pbe = productToPBE.get(oldLine.Product2Id);
                        
                        if (pbe != null) {
                            QuoteLineItem newLine = new QuoteLineItem();
                            newLine.QuoteId = req.quoteId;
                            newLine.Product2Id = oldLine.Product2Id;
                            newLine.Quantity = oldLine.Quantity;
                            newLine.PricebookEntryId = pbe.Id;
                            newLine.UnitPrice = pbe.UnitPrice; // Use price from new currency PBE
                            newLines.add(newLine);
                        } else {
                            // No PBE found for this product in new currency
                            res.message = 'Warning: No price found for product in ' + req.newCurrency;
                        }
                    }
                    
                    // Insert new lines
                    if (!newLines.isEmpty()) {
                        insert newLines;
                        res.message = 'Successfully updated ' + newLines.size() + 
                                    ' quote lines to ' + req.newCurrency;
                    }
                } else {
                    res.message = 'No quote lines to recalculate';
                }
                
                // Create audit record
                createAuditRecord(req.quoteId, req.oldCurrency, req.newCurrency);
                
                res.success = true;
                
            } catch (Exception e) {
                res.success = false;
                res.message = 'Error changing currency: ' + e.getMessage();
                System.debug('Error: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            }
            
            results.add(res);
        }
        
        return results;
    }
    
    private static void createAuditRecord(Id quoteId, String oldCurrency, String newCurrency) {
        Task auditTask = new Task();
        auditTask.Subject = 'Quote Currency Changed from ' + oldCurrency + ' to ' + newCurrency;
        auditTask.WhatId = quoteId;
        auditTask.Status = 'Completed';
        auditTask.ActivityDate = Date.today();
        auditTask.Description = 'Currency changed by ' + UserInfo.getName() + 
                               ' on ' + DateTime.now().format();
        insert auditTask;
    }
    
    public class Request {
        @InvocableVariable(required=true)
        public Id quoteId;
        
        @InvocableVariable(required=true)
        public String oldCurrency;
        
        @InvocableVariable(required=true)
        public String newCurrency;
    }
    
    public class Result {
        @InvocableVariable
        public Id quoteId;
        
        @InvocableVariable
        public Boolean success;
        
        @InvocableVariable
        public String message;
    }
}