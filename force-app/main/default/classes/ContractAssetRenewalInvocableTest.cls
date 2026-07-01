@IsTest
private class ContractAssetRenewalInvocableTest {

    @IsTest
    static void processRequest_requiresContractAndAssets() {
        ContractAssetRenewalInvocable.Response nullRequest =
            ContractAssetRenewalInvocable.processRequest(null);
        System.assertEquals(false, nullRequest.success);

        ContractAssetRenewalInvocable.Request missingAssets =
            new ContractAssetRenewalInvocable.Request();
        missingAssets.contractId = fakeId(Contract.SObjectType);

        ContractAssetRenewalInvocable.Response nullAssets =
            ContractAssetRenewalInvocable.processRequest(missingAssets);
        System.assertEquals(false, nullAssets.success);
        System.assert(nullAssets.errorMessage.contains('required'));
    }

    @IsTest
    static void processRequest_successWithTestOverride() {
        Id quoteId = fakeId(Quote.SObjectType);
        ContractAssetRenewalInvocable.testRenewalQuoteIdOverride = quoteId;

        ContractAssetRenewalInvocable.Request request =
            new ContractAssetRenewalInvocable.Request();
        request.contractId = fakeId(Contract.SObjectType);
        request.assetIds = new List<Id>{ fakeId(Asset.SObjectType) };

        ContractAssetRenewalInvocable.Response response =
            ContractAssetRenewalInvocable.processRequest(request);

        System.assertEquals(true, response.success);
        System.assertEquals(quoteId, response.renewalQuoteId);

        ContractAssetRenewalInvocable.testRenewalQuoteIdOverride = null;
    }

    @IsTest
    static void buildInvocationParameters_includesOptionalFields() {
        ContractAssetRenewalInvocable.Request request =
            new ContractAssetRenewalInvocable.Request();
        request.contractId = fakeId(Contract.SObjectType);
        request.assetIds = new List<Id>{ fakeId(Asset.SObjectType) };
        request.opportunityId = fakeId(Opportunity.SObjectType);
        request.renewalStartDate = Date.newInstance(2027, 6, 24);
        request.renewalEndDate = Date.newInstance(2028, 6, 23);

        Map<String, Object> params = ContractAssetRenewalInvocable.buildInvocationParameters(request);

        System.assertEquals(true, params.get('skipPricing'));
        System.assertEquals('Quote', params.get('renewOutputType'));
        System.assertEquals(String.valueOf(request.contractId), params.get('renewContractId'));
        System.assertEquals(1, ((List<String>) params.get('renewAssetIds')).size());
    }

    @IsTest
    static void collectErrors_defaultsWhenEmpty() {
        Invocable.Action action = Invocable.Action.createStandardAction('initiateRenewal');
        action.setInvocationParameter('renewAssetIds', new List<Id>());
        List<Invocable.Action.Result> results = action.invoke();
        System.assert(!results.isEmpty());

        String message = ContractAssetRenewalInvocable.collectErrors(results[0]);
        System.assert(String.isNotBlank(message));
    }

    @IsTest
    static void formatRenewalDateTime_usesIsoGmtString() {
        String start = ContractAssetRenewalInvocable.formatRenewalDateTime(
            Date.newInstance(2027, 6, 24),
            false
        );
        System.assertEquals('2027-06-24T00:00:00Z', start);
    }

    @IsTest
    static void toRenewalDateTime_buildsStartAndEndOfDay() {
        Date testDate = Date.newInstance(2027, 6, 24);

        Datetime startDt = ContractAssetRenewalInvocable.toRenewalDateTime(testDate, false);
        Datetime endDt = ContractAssetRenewalInvocable.toRenewalDateTime(testDate, true);

        System.assertEquals(0, startDt.hourGmt());
        System.assertEquals(23, endDt.hourGmt());
        System.assertEquals(null, ContractAssetRenewalInvocable.toRenewalDateTime(null, false));
    }

    @IsTest
    static void initiateRenewal_returnsResponsePerRequest() {
        ContractAssetRenewalInvocable.testRenewalQuoteIdOverride = fakeId(Quote.SObjectType);

        ContractAssetRenewalInvocable.Request request =
            new ContractAssetRenewalInvocable.Request();
        request.contractId = fakeId(Contract.SObjectType);
        request.assetIds = new List<Id>{ fakeId(Asset.SObjectType) };

        List<ContractAssetRenewalInvocable.Response> responses =
            ContractAssetRenewalInvocable.initiateRenewal(
                new List<ContractAssetRenewalInvocable.Request>{ request }
            );

        System.assertEquals(1, responses.size());
        System.assertEquals(true, responses[0].success);

        ContractAssetRenewalInvocable.testRenewalQuoteIdOverride = null;
    }

    @IsTest
    static void processRequest_surfacesInvokeFailure() {
        ContractAssetRenewalInvocable.testRenewalQuoteIdOverride = null;

        ContractAssetRenewalInvocable.Request request =
            new ContractAssetRenewalInvocable.Request();
        request.contractId = fakeId(Contract.SObjectType);
        request.assetIds = new List<Id>{ fakeId(Asset.SObjectType) };

        ContractAssetRenewalInvocable.Response response =
            ContractAssetRenewalInvocable.processRequest(request);

        System.assertEquals(false, response.success);
        System.assert(String.isNotBlank(response.errorMessage));
    }

    @IsTest
    static void initiateRenewal_invocableNoOpOnNull() {
        System.assertEquals(0, ContractAssetRenewalInvocable.initiateRenewal(null).size());
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000001AAA');
    }
}