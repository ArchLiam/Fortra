Id quoteId = '0Q0WC0000038bgb0AA';
// Try the RLM transaction-level reprice via ConnectApi.SalesTransaction / Pricing
try {
    ConnectApi.PricingInput pi = new ConnectApi.PricingInput();
    pi.pricingProcess = ConnectApi.PricingProcessEnum.PRICINGFULL;
    ConnectApi.SalesTransactionInput sti = new ConnectApi.SalesTransactionInput();
    System.debug('SalesTransactionInput OK');
} catch (Exception e) {
    System.debug('STI err: ' + e.getTypeName() + ' / ' + e.getMessage());
}
