// SMOKE TEST 1 — RENEWAL via Fortra_Create_Renewal_Quote (headless)
Id ASSET = '02iWC000008dd1hYAA'; // Cobalt Strike on Contract 00069404, Fortra LLC Test
Map<String,Object> inputs = new Map<String,Object>{
    'assetIds'         => new List<String>{ ASSET },
    'renewalStartDate' => Datetime.newInstance(2027,6,29,0,0,0),
    'renewalEndDate'   => Datetime.newInstance(2028,6,28,0,0,0)
};
try {
    Flow.Interview fi = Flow.Interview.createInterview('Fortra_Create_Renewal_Quote', inputs);
    fi.start();
    System.debug(LoggingLevel.ERROR, 'ST1 RENEWAL'
        + '\n isSuccess=' + fi.getVariableValue('isSuccess')
        + '\n error='     + fi.getVariableValue('errorMessage')
        + '\n quoteId='   + fi.getVariableValue('renewalQuoteId'));
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'ST1 FAILED [' + e.getTypeName() + ' @ ' + e.getLineNumber() + ']: ' + e.getMessage());
}
