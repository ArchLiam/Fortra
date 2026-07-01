/**
 * @description Pricing context bridge for derived maintenance Source_List_Price__c.
 *
 *              DISABLED: logic commented out per request — maintenance pricing uses
 *              Stamp_Source_List_Price flow + context definition only. Do not deploy
 *              enabled logic until re-enabled.
 */
global class SourceListPricePrehook implements RevSignaling.SignalingApexProcessor {

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        response.message = 'SourceListPricePrehook disabled';
        return response;
    }
}