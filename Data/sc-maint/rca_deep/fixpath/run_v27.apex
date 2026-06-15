Id quoteId = '0Q0WC0000038aXd0AI';
System.debug('RMPS-TEST-START: invoking V27 Fortra_Quote_Reprice for ' + quoteId);
Flow.Interview.Fortra_Quote_Reprice f = new Flow.Interview.Fortra_Quote_Reprice(new Map<String,Object>{'QuoteId' => quoteId});
f.start();
System.debug('RMPS-TEST-END: flow completed');
