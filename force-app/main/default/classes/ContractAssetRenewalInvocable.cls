/**
 * @description Initiates contract asset renewal with skipPricing=true so RCA does not
 *              block on stacked Percentage/Amount rate adjustments copied from the
 *              original order. Fortra COLA / maintenance stamping runs on the renewal
 *              quote after creation via existing reprice flows.
 */
public with sharing class ContractAssetRenewalInvocable {

    @TestVisible
    private static Id testRenewalQuoteIdOverride;

    public class Request {
        @InvocableVariable(required=true label='Contract Id')
        public Id contractId;

        @InvocableVariable(required=true label='Asset Ids')
        public List<Id> assetIds;

        @InvocableVariable(label='Renewal Start Date')
        public Date renewalStartDate;

        @InvocableVariable(label='Renewal End Date')
        public Date renewalEndDate;

        @InvocableVariable(label='Opportunity Id')
        public Id opportunityId;
    }

    public class Response {
        @InvocableVariable(label='Renewal Quote Id')
        public Id renewalQuoteId;

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Initiate Contract Asset Renewal'
        description='Creates a renewal quote from contract assets, skipping pre-renew pricing validation'
        category='Revenue'
    )
    public static List<Response> initiateRenewal(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null) {
            return responses;
        }

        for (Request request : requests) {
            responses.add(processRequest(request));
        }
        return responses;
    }

    @TestVisible
    private static Map<String, Object> buildInvocationParameters(Request request) {
        Map<String, Object> params = new Map<String, Object>{
            'renewAssetIds' => toIdStringList(request.assetIds),
            'renewContractId' => String.valueOf(request.contractId),
            'renewOutputType' => 'Quote',
            'skipPricing' => true
        };
        if (request.opportunityId != null) {
            params.put('renewOpportunityId', String.valueOf(request.opportunityId));
        }
        if (request.renewalStartDate != null) {
            params.put('renewStartDate', formatRenewalDateTime(request.renewalStartDate, false));
        }
        if (request.renewalEndDate != null) {
            params.put('renewEndDate', formatRenewalDateTime(request.renewalEndDate, true));
        }
        return params;
    }

    @TestVisible
    private static List<String> toIdStringList(List<Id> recordIds) {
        List<String> idStrings = new List<String>();
        if (recordIds == null) {
            return idStrings;
        }
        for (Id recordId : recordIds) {
            if (recordId != null) {
                idStrings.add(String.valueOf(recordId));
            }
        }
        return idStrings;
    }

    @TestVisible
    private static Response processRequest(Request request) {
        Response response = new Response();
        response.success = false;

        if (request == null || request.contractId == null || request.assetIds == null || request.assetIds.isEmpty()) {
            response.errorMessage = 'Contract Id and at least one Asset Id are required.';
            return response;
        }

        try {
            if (Test.isRunningTest() && testRenewalQuoteIdOverride != null) {
                response.renewalQuoteId = testRenewalQuoteIdOverride;
                response.success = true;
                return response;
            }

            Invocable.Action action = Invocable.Action.createStandardAction('initiateRenewal');
            Map<String, Object> params = buildInvocationParameters(request);
            for (String paramName : params.keySet()) {
                action.setInvocationParameter(paramName, params.get(paramName));
            }

            List<Invocable.Action.Result> results = action.invoke();
            if (results == null || results.isEmpty()) {
                response.errorMessage = 'initiateRenewal returned no result.';
                return response;
            }

            Invocable.Action.Result result = results[0];
            if (!result.isSuccess()) {
                response.errorMessage = collectErrors(result);
                return response;
            }

            Map<String, Object> outputs = result.getOutputParameters();
            Object quoteId = outputs != null ? outputs.get('renewRecordId') : null;
            if (quoteId == null) {
                response.errorMessage = 'initiateRenewal succeeded but did not return renewRecordId.';
                return response;
            }

            response.renewalQuoteId = (Id) quoteId;
            response.success = true;
        } catch (Exception ex) {
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    @TestVisible
    private static String formatRenewalDateTime(Date value, Boolean endOfDay) {
        Datetime dt = toRenewalDateTime(value, endOfDay);
        if (dt == null) {
            return null;
        }
        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    @TestVisible
    private static Datetime toRenewalDateTime(Date value, Boolean endOfDay) {
        if (value == null) {
            return null;
        }
        if (endOfDay) {
            return Datetime.newInstanceGmt(value.year(), value.month(), value.day(), 23, 59, 59);
        }
        return Datetime.newInstanceGmt(value.year(), value.month(), value.day(), 0, 0, 0);
    }

    @TestVisible
    private static String collectErrors(Invocable.Action.Result result) {
        List<String> messages = new List<String>();
        if (result.getErrors() != null) {
            for (Invocable.Action.Error error : result.getErrors()) {
                if (String.isNotBlank(error.getMessage())) {
                    messages.add(error.getMessage());
                }
            }
        }
        return messages.isEmpty() ? 'initiateRenewal failed.' : String.join(messages, '; ');
    }
}