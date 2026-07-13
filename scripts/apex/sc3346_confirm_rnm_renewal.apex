// SC-3346 CONFIRMATION: does a CLEANLY-created renewal (standard Fortra_Create_Renewal_Quote flow)
// land the RNM-sourced maintenance line as Amend/$0 (real defect) or Renew/committed (7AKH was bad test data)?
//
// Test contract: 800WC00000Sy0RfYAJ  00069410  (Activated, USD) -- the build-spec-proven clean set.
// 3 assets on one contract/opportunity: BoKS license + BoKS RNM new-maint (RNM->RRM scenario) + beSECURE subscription (control).
// Same headless path as F-04 (f04_initiateRenewal.apex): Flow.Interview 'Fortra_Create_Renewal_Quote' with assetIds.

Id ASSET_RNM_MAINT = '02iWC000008dekAYAQ'; // PIA-PIA-RNM-PIAMBK  BoKS New-Maintenance (RNM), USD, Price 71   <-- TEST SUBJECT
Id ASSET_LICENSE   = '02iWC000008dekBYAQ'; // PIA-PIA-NRPS-PIAP   BoKS license (contributor), USD, Price 355
Id ASSET_SUB_CTRL  = '02iWC000008dekCYAQ'; // VM-BSL-RSL-BESECB   beSECURE subscription (control, should Renew+commit), USD, Price 6695.3

Id CONTRACT_ID = '800WC00000Sy0RfYAJ'; // 00069410, Activated, ends 2027-06-28

// DIRECT initiateRenewal invocable (renews by contract; no per-asset opportunity check that the flow enforces).
Invocable.Action a = Invocable.Action.createStandardAction('initiateRenewal');
a.setInvocationParameter('renewContractId', String.valueOf(CONTRACT_ID));
a.setInvocationParameter('renewAssetIds', new List<String>{ String.valueOf(ASSET_RNM_MAINT), String.valueOf(ASSET_LICENSE), String.valueOf(ASSET_SUB_CTRL) });
a.setInvocationParameter('renewStartDate', '2027-06-29T00:00:00');
a.setInvocationParameter('renewOutputType', 'Quote');

try {
    List<Invocable.Action.Result> res = a.invoke();
    String base = URL.getOrgDomainUrl().toExternalForm();
    if (res != null && !res.isEmpty()) {
        Invocable.Action.Result r = res[0];
        System.debug(LoggingLevel.ERROR, '========================================'
            + '\n✅ SC-3346 initiateRenewal RESULT'
            + '\n  isSuccess : ' + r.isSuccess()
            + '\n  errors    : ' + r.getErrors()
            + '\n  outputs   : ' + JSON.serialize(r.getOutputParameters())
            + '\n========================================'
            + '\n  NEXT: find the new renewal Quote (newest for the account/contract), then run the Step-4 lineage query.');
    } else {
        System.debug(LoggingLevel.ERROR, '❌ initiateRenewal returned no results');
    }
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, '❌ SC-3346 initiateRenewal FAILED ['
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}
