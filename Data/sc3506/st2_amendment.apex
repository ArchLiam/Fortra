// SMOKE TEST 2 — AMENDMENT via Fortra_Create_Amendment_Quote (headless), qty +1
Id ASSET = '02iWC000008eU4QYAU'; // Cobalt Strike on Contract 00069417, Fortra LLC Test
Map<String,Object> inputs = new Map<String,Object>{
    'assetIds'       => new List<String>{ ASSET },
    'amendmentDate'  => Date.newInstance(2026,9,1),
    'quantityChange' => 1
};
try {
    Flow.Interview fi = Flow.Interview.createInterview('Fortra_Create_Amendment_Quote', inputs);
    fi.start();
    System.debug(LoggingLevel.ERROR, 'ST2 AMENDMENT'
        + '\n isSuccess=' + fi.getVariableValue('isSuccess')
        + '\n error='     + fi.getVariableValue('errorMessage')
        + '\n quoteId='   + fi.getVariableValue('amendmentQuoteId'));
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'ST2 FAILED [' + e.getTypeName() + ' @ ' + e.getLineNumber() + ']: ' + e.getMessage());
}
