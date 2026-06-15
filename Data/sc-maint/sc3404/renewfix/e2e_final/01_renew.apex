Invocable.Action a = Invocable.Action.createStandardAction('initiateRenewal');
a.setInvocationParameter('renewAssetIds', new List<String>{'02iWC000008DmS1YAK'});
a.setInvocationParameter('renewOutputType', 'Quote');
List<Invocable.Action.Result> results = a.invoke();
for (Invocable.Action.Result r : results) {
    System.debug('E2E-RENEW success=' + r.isSuccess());
    System.debug('E2E-OUTPUTS=' + r.getOutputParameters());
    if (!r.isSuccess()) System.debug('E2E-ERRORS=' + r.getErrors());
}
