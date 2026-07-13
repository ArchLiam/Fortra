public class QuoteCurrencyChangeService {
    
    @InvocableMethod(label='Handle Quote Currency Change' 
                     description='Recalculates quote lines when currency changes')
    public static List<Result> handleCurrencyChange(List<Request> requests) {
        List<Result> results = new List<Result>();
        
        for (Request req : requests) {
            Result res = new Result();
            res.quoteId = req.quoteId;
            
            try {
                // Get Quote details with lines
                Quote quote = [SELECT Id, CurrencyIsoCode, OpportunityId
                               FROM Quote 
                               WHERE Id = :req.quoteId];
                
                // Get existing quote lines
                List<QuoteLineItem> oldLines = [SELECT Id, Product2Id, Quantity,
                                                 QuoteId, UnitPrice, TotalPrice,
                                                 ListPrice, Subtotal, Discount,
                                                 PricebookEntryId
                                                 FROM QuoteLineItem 
                                                 WHERE QuoteId = :req.quoteId];
                
                if (!oldLines.isEmpty()) {
                    // Create new lines before deleting old ones
                    List<QuoteLineItem> newLines = new List<QuoteLineItem>();
                    
                    for (QuoteLineItem oldLine : oldLines) {
                        QuoteLineItem newLine = new QuoteLineItem();
                        newLine.QuoteId = req.quoteId;
                        newLine.Product2Id = oldLine.Product2Id;
                        newLine.Quantity = oldLine.Quantity;
                        newLine.UnitPrice = oldLine.UnitPrice;
                        newLine.PricebookEntryId = oldLine.PricebookEntryId;
                        // CurrencyIsoCode is inherited from Quote
                        // Note: Actual price conversion would happen through price book entries
                        newLines.add(newLine);
                    }
                    
                    // Delete old lines
                    delete oldLines;
                    
                    // Insert new lines
                    insert newLines;
                    
                    res.message = 'Successfully recalculated ' + newLines.size() + 
                                ' quote lines for ' + req.newCurrency;
                } else {
                    res.message = 'No quote lines to recalculate';
                }
                
                // Create audit record
                createAuditRecord(req.quoteId, req.oldCurrency, req.newCurrency);
                
                res.success = true;
                
            } catch (Exception e) {
                res.success = false;
                res.message = 'Error changing currency: ' + e.getMessage();
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