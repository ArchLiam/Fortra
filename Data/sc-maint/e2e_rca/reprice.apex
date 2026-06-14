// Attempt headless reprice of the test Quote via RLM ConnectApi
Id quoteId = '0Q0WC0000038bgb0AA';
try {
    // Build minimal pricing request for the quote
    ConnectApi.PricingInput pi = new ConnectApi.PricingInput();
    System.debug('PricingInput class exists');
} catch (Exception e) {
    System.debug('ConnectApi.PricingInput err: ' + e.getMessage());
}
