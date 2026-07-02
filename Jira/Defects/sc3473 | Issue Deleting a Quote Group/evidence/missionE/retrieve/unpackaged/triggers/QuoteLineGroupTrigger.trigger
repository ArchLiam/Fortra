/**
 * @description Trigger for QuoteLineGroup object
 * @author Claude Code
 * @date 2025-01-23
 *
 * Handles automatic hardware reference updates on quote lines when group hardware changes
 */
trigger QuoteLineGroupTrigger on QuoteLineGroup (after update) {

    // Handle hardware change propagation on update
    if (Trigger.isAfter && Trigger.isUpdate) {
        QuoteLineGroupTriggerHandler.handleHardwareChange(
            Trigger.new,
            Trigger.oldMap
        );
    }
}