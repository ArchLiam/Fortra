Set<Id> qids = new Set<Id>{'0Q0WC0000039Kc50AE','0Q0WC0000039AMb0AM'};
List<QuoteLineItem> qlis = [SELECT Id FROM QuoteLineItem WHERE QuoteId IN :qids];
delete qlis;
List<QuoteAction> qas = [SELECT Id FROM QuoteAction WHERE QuoteId IN :qids];
if (!qas.isEmpty()) delete qas;
List<Quote> qs = [SELECT Id FROM Quote WHERE Id IN :qids];
delete qs;
System.debug('CLEANUP-DONE deletedQLIs=' + qlis.size() + ' deletedQAs=' + qas.size() + ' deletedQuotes=' + qs.size());
