/**
 * @description Service class for Operations Checklist CRUD operations.
 * Provides data access methods used by OperationsChecklistController.
 */
public with sharing class OperationsChecklistService {

    /**
     * @description Get all checklist items for a Quote ordered by sort order
     * @param quoteId The ID of the Quote
     * @return List of Quote_Checklist_Item__c records
     */
    public static List<Quote_Checklist_Item__c> getChecklistItems(Id quoteId) {
        return [
            SELECT Id, Item_Name__c, Is_Checked__c, Checked_By__c,
                   Checked_By__r.Name, Checked_Date__c, Notes__c, Sort_Order__c
            FROM Quote_Checklist_Item__c
            WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY Sort_Order__c ASC
        ];
    }

    /**
     * @description Update a checklist item's checked status and notes
     * @param itemId The ID of the checklist item
     * @param isChecked Whether the item is checked
     * @param notes Notes for the item
     * @return The updated Quote_Checklist_Item__c record
     */
    public static Quote_Checklist_Item__c updateChecklistItem(Id itemId, Boolean isChecked, String notes) {
        Quote_Checklist_Item__c item = [
            SELECT Id, Is_Checked__c, Checked_By__c, Checked_Date__c, Notes__c
            FROM Quote_Checklist_Item__c
            WHERE Id = :itemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        item.Is_Checked__c = isChecked;
        item.Notes__c = notes;

        if (isChecked) {
            item.Checked_By__c = UserInfo.getUserId();
            item.Checked_Date__c = System.now();
        } else {
            item.Checked_By__c = null;
            item.Checked_Date__c = null;
        }

        update item;
        return item;
    }

    /**
     * @description Update only the notes field on a checklist item
     * @param itemId The ID of the checklist item
     * @param notes The new notes value
     * @return The updated Quote_Checklist_Item__c record
     */
    public static Quote_Checklist_Item__c updateChecklistItemNotes(Id itemId, String notes) {
        Quote_Checklist_Item__c item = [
            SELECT Id, Notes__c
            FROM Quote_Checklist_Item__c
            WHERE Id = :itemId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        item.Notes__c = notes;
        update item;
        return item;
    }
}