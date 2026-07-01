/**
 * @description Quick Action class to initialize Operations Checklist manually
 */
public with sharing class InitializeChecklistAction {

    /**
     * @description Initialize checklist for the current Opportunity
     * @param opportunityIds List of Opportunity IDs from the Quick Action context
     */
    @InvocableMethod(label='Initialize Operations Checklist (Button)'
                     description='Manually initialize checklist items for this Opportunity'
                     category='Operations Checklist')
    public static void initializeFromAction(List<Id> opportunityIds) {
        // Prepare requests for the service
        List<ChecklistInitializationService.InitializeRequest> requests =
            new List<ChecklistInitializationService.InitializeRequest>();

        for (Id oppId : opportunityIds) {
            ChecklistInitializationService.InitializeRequest request =
                new ChecklistInitializationService.InitializeRequest();
            request.opportunityId = oppId;
            requests.add(request);
        }

        // Call the initialization service
        List<ChecklistInitializationService.InitializeResult> results =
            ChecklistInitializationService.initializeChecklistForQuote(requests);

        // For Quick Actions, we can't return feedback directly to the user
        // The results will be logged in debug logs
        for (ChecklistInitializationService.InitializeResult result : results) {
            if (result.success) {
                System.debug('SUCCESS: ' + result.message);
            } else {
                System.debug('ERROR: ' + result.message);
            }
        }
    }
}