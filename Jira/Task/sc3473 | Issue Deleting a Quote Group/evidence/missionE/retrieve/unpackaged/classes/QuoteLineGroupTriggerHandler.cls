/**
 * @description Trigger handler for QuoteLineGroup to update hardware references
 * @author Claude Code
 * @date 2025-01-23
 *
 * This handler automatically updates Hardware_Reference__c on all quote lines in a group
 * when the group's Hardware__c field changes.
 *
 * Handles:
 * - Group's hardware changed from A to B (update all lines to new hardware)
 * - Group's hardware assigned from null to A (update all lines)
 * - Group's hardware cleared from A to null (clear all lines)
 */
public with sharing class QuoteLineGroupTriggerHandler {

    /**
     * @description Main handler method for hardware change detection
     * @param newGroups List of updated QuoteLineGroup records
     * @param oldMap Map of old QuoteLineGroup records
     */
    public static void handleHardwareChange(
        List<QuoteLineGroup> newGroups,
        Map<Id, QuoteLineGroup> oldMap
    ) {
        // Step 1: Detect which groups had Hardware__c changed
        Map<Id, Id> groupToNewHardwareMap = new Map<Id, Id>();
        Set<Id> groupIds = new Set<Id>();

        for (QuoteLineGroup newGroup : newGroups) {
            QuoteLineGroup oldGroup = oldMap.get(newGroup.Id);

            // Check if Hardware__c field changed
            if (oldGroup.Hardware__c != newGroup.Hardware__c) {
                groupIds.add(newGroup.Id);
                // Map group to its new hardware (can be null)
                groupToNewHardwareMap.put(newGroup.Id, newGroup.Hardware__c);
            }
        }

        // Exit early if no hardware changes
        if (groupIds.isEmpty()) {
            return;
        }

        // Step 2: Query all QuoteLineItems in affected groups
        List<QuoteLineItem> quoteLinesToUpdate = [
            SELECT Id, QuoteLineGroupId, Hardware__c
            FROM QuoteLineItem
            WHERE QuoteLineGroupId IN :groupIds
        ];

        // Exit early if no quote lines to update
        if (quoteLinesToUpdate.isEmpty()) {
            return;
        }

        // Step 3: Update Hardware__c on all lines
        for (QuoteLineItem line : quoteLinesToUpdate) {
            Id newHardwareId = groupToNewHardwareMap.get(line.QuoteLineGroupId);
            line.Hardware__c = newHardwareId;
        }

        // Step 4: Bulk update quote lines
        try {
            update quoteLinesToUpdate;
        } catch (DmlException e) {
            // Log error but don't block the group update
            System.debug('Error updating quote line hardware references: ' + e.getMessage());
            throw e;
        }
    }
}