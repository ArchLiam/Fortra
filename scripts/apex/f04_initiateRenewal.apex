// F-04: headless renewal generation via initiateRenewal invocable (same path as Fortra_Create_Renewal_Quote flow)
// Generates a fresh renewal Quote from 2 COLA-eligible Subscription assets, NO reprice afterward.
// Then we query the resulting QLIs to see if COLA + description are populated at generation time.

Id ASSET_beSECURE = '02iWC000008deygYAA'; // beSECURE - Cloud-Based, USD, Price 206, Subscription
Id ASSET_Cobalt   = '02iWC000008deyfYAA'; // Cobalt Strike, USD, Price 5900, Subscription
Id CONTRACT_ID    = '800WC00000SyGrNYAV'; // 00069408, Activated
Id OPP_ID         = '006WC00000RZyeTYAT'; // Renewal Forecast opp on the contract

// Build the invocable request for ConnectApi initiateRenewal action.
// The flow actionType is 'initiateRenewal'; the underlying invocable is exposed as
// quotingAI__createRenewalQuote / RenewalQuoteCreation. We call the standard connect-action via Apex invocable.
Map<String,Object> req = new Map<String,Object>{
    'renewAssetIds'      => new List<Id>{ ASSET_beSECURE, ASSET_Cobalt },
    'renewOutputType'    => 'Quote',
    'renewOpportunityId' => OPP_ID,
    'renewContractId'    => CONTRACT_ID,
    'renewStartDate'     => Date.newInstance(2027,6,29),
    'renewEndDate'       => Date.newInstance(2028,6,28)
};
System.debug(LoggingLevel.ERROR, 'F-04 REQUEST=' + JSON.serialize(req));

// Invoke via Flow.Interview running the actual production flow so we exercise the exact headless path.
Map<String,Object> flowInputs = new Map<String,Object>{
    'assetIds' => new List<String>{ ASSET_beSECURE, ASSET_Cobalt }
};
try {
    Flow.Interview fi = Flow.Interview.createInterview('Fortra_Create_Renewal_Quote', flowInputs);
    fi.start();
    Object outQuoteId = fi.getVariableValue('renewalQuoteId');
    Object isSuccess  = fi.getVariableValue('isSuccess');
    Object errMsg     = fi.getVariableValue('errorMessage');
    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ F-04 RENEWAL GENERATED'
        + '\n  isSuccess   : ' + isSuccess
        + '\n  errorMessage: ' + errMsg
        + '\n  QuoteId     : ' + outQuoteId
        + '\n  Quote URL   : ' + base + '/' + outQuoteId);
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, '❌ F-04 FLOW FAILED ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
