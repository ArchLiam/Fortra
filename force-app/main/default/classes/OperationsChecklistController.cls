/**
 * @description Controller for Operations Checklist Lightning Web Component
 * Provides @AuraEnabled methods for checklist CRUD operations
 */
public with sharing class OperationsChecklistController {

    /**
     * @description Get all checklist items for a Quote
     * @param quoteId The ID of the Quote
     * @return ChecklistData wrapper containing items and permission status
     */
    @AuraEnabled(cacheable=true)
    public static ChecklistData getChecklistItems(Id quoteId) {
        ChecklistData data = new ChecklistData();

        try {
            // Check custom permission
            data.hasEditPermission = FeatureManagement.checkPermission('Operations_Checklist_Access');

            // Query checklist items
            data.items = [
                SELECT Id, Item_Name__c, Is_Checked__c, Checked_By__c, Checked_By__r.Name,
                       Checked_Date__c, Notes__c, Sort_Order__c
                FROM Quote_Checklist_Item__c
                WHERE Quote__c = :quoteId
                WITH SECURITY_ENFORCED
                ORDER BY Sort_Order__c ASC
            ];

            // Calculate progress
            Integer totalItems = data.items.size();
            Integer completedItems = 0;

            for (Quote_Checklist_Item__c item : data.items) {
                if (item.Is_Checked__c) {
                    completedItems++;
                }
            }

            data.totalItems = totalItems;
            data.completedItems = completedItems;

            if (totalItems > 0) {
                data.completionPercentage = (Integer)((completedItems * 100.0) / totalItems);
            } else {
                data.completionPercentage = 0;
            }

        } catch (Exception e) {
            throw new AuraHandledException('Error loading checklist items: ' + e.getMessage());
        }

        return data;
    }

    /**
     * @description Update a checklist item (check/uncheck, update notes)
     * @param itemId The ID of the checklist item to update
     * @param isChecked Whether the item is checked
     * @param notes Notes for the item
     * @return Updated ChecklistItem wrapper
     */
    @AuraEnabled
    public static ChecklistItem updateChecklistItem(Id itemId, Boolean isChecked, String notes) {
        // Check custom permission
        if (!FeatureManagement.checkPermission('Operations_Checklist_Access')) {
            throw new AuraHandledException('You do not have permission to update checklist items. Please contact your administrator.');
        }

        try {
            // Query existing item
            Quote_Checklist_Item__c item = [
                SELECT Id, Item_Name__c, Is_Checked__c, Checked_By__c, Checked_Date__c, Notes__c, Sort_Order__c
                FROM Quote_Checklist_Item__c
                WHERE Id = :itemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Update fields
            item.Is_Checked__c = isChecked;
            item.Notes__c = notes;

            if (isChecked) {
                item.Checked_By__c = UserInfo.getUserId();
                item.Checked_Date__c = DateTime.now();
            } else {
                // Clear checked fields if unchecking
                item.Checked_By__c = null;
                item.Checked_Date__c = null;
            }

            update item;

            // Query updated item with user name
            item = [
                SELECT Id, Item_Name__c, Is_Checked__c, Checked_By__c, Checked_By__r.Name,
                       Checked_Date__c, Notes__c, Sort_Order__c
                FROM Quote_Checklist_Item__c
                WHERE Id = :itemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Convert to wrapper
            ChecklistItem result = new ChecklistItem();
            result.id = item.Id;
            result.itemName = item.Item_Name__c;
            result.isChecked = item.Is_Checked__c;
            result.checkedBy = item.Checked_By__c;
            result.checkedByName = item.Checked_By__c != null ? item.Checked_By__r.Name : null;
            result.checkedDate = item.Checked_Date__c;
            result.notes = item.Notes__c;
            result.sortOrder = item.Sort_Order__c != null ? Integer.valueOf(item.Sort_Order__c) : 0;

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error updating checklist item: ' + e.getMessage());
        }
    }

    /**
     * @description Check if current user has Operations Checklist Access permission
     * @return Boolean indicating if user has permission
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasCustomPermission() {
        return FeatureManagement.checkPermission('Operations_Checklist_Access');
    }

    // Wrapper classes for data transfer

    public class ChecklistData {
        @AuraEnabled public List<Quote_Checklist_Item__c> items { get; set; }
        @AuraEnabled public Integer totalItems { get; set; }
        @AuraEnabled public Integer completedItems { get; set; }
        @AuraEnabled public Integer completionPercentage { get; set; }
        @AuraEnabled public Boolean hasEditPermission { get; set; }

        public ChecklistData() {
            this.items = new List<Quote_Checklist_Item__c>();
            this.totalItems = 0;
            this.completedItems = 0;
            this.completionPercentage = 0;
            this.hasEditPermission = false;
        }
    }

    public class ChecklistItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String itemName { get; set; }
        @AuraEnabled public Boolean isChecked { get; set; }
        @AuraEnabled public Id checkedBy { get; set; }
        @AuraEnabled public String checkedByName { get; set; }
        @AuraEnabled public DateTime checkedDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
    }
}