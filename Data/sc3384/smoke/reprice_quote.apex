// SC-3384 smoke: reprice quote via the RLM autolaunched flow (fires PartnerNetPricePosthook).
Flow.Interview.Fortra_Quote_Reprice f = new Flow.Interview.Fortra_Quote_Reprice(
    new Map<String, Object>{ 'QuoteId' => '0Q0WC000003FcrF0AS' });
f.start();
System.debug('SMOKE: reprice invoked for 0Q0WC000003FcrF0AS');
