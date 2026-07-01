/**
 * @description Invocable Apex action to update existing PricebookEntry records with new prices
 * @author Claude Code
 * @date 2025-10-09
 * @modified 2025-10-10 - Added auto-creation of Standard Pricebook entries
 *
 * Purpose: Handle bulk update of PricebookEntry records from Flow, working around Flow's
 *          limitation of not being able to use inputReference with inputAssignments.
 *
 * Enhanced: Now automatically creates Standard Pricebook entries when they don't exist,
 *           allowing seamless creation of Custom Pricebook entries for all currencies.
 *
 * Used by: Fortra_Product_Update_Currency_Prices_SubFlow
 */
public with sharing class UpdatePricebookEntriesInvocable {

    /**
     * @description Input wrapper for the invocable method - Simplified for Flow compatibility
     */
    public class PriceUpdateInput {
        @InvocableVariable(required=true label='Product2 Id' description='ID of the Product2 record')
        public Id product2Id;

        @InvocableVariable(required=true label='Pricebook2 Id' description='ID of the Pricebook2 record')
        public Id pricebook2Id;

        @InvocableVariable(required=true label='Currency ISO Codes' description='List of currency codes (EUR, GBP, CAD, etc.)')
        public List<String> currencyIsoCodes;

        @InvocableVariable(required=true label='Unit Prices' description='List of prices (parallel to currency codes)')
        public List<Decimal> unitPrices;
    }

    /**
     * @description Output wrapper for the invocable method
     */
    public class PriceUpdateOutput {
        @InvocableVariable(label='Updated Count' description='Number of PricebookEntry records updated')
        public Integer updatedCount;

        @InvocableVariable(label='Created Count' description='Number of PricebookEntry records created')
        public Integer createdCount;

        @InvocableVariable(label='Standard Created Count' description='Number of Standard Pricebook entries created')
        public Integer standardCreatedCount;

        @InvocableVariable(label='Error Message' description='Error message if operation failed')
        public String errorMessage;

        @InvocableVariable(label='Success' description='Whether the operation was successful')
        public Boolean success;
    }

    /**
     * @description Update or create PricebookEntry records for multiple currencies
     * @param inputs List of input parameters
     * @return List of output results
     */
    @InvocableMethod(
        label='Update Pricebook Entry Prices'
        description='Updates existing PricebookEntry records or creates new ones with calculated prices for multiple currencies'
        category='Revenue Cloud'
    )
    public static List<PriceUpdateOutput> updatePricebookEntryPrices(List<PriceUpdateInput> inputs) {
        List<PriceUpdateOutput> outputs = new List<PriceUpdateOutput>();

        for (PriceUpdateInput input : inputs) {
            PriceUpdateOutput output = new PriceUpdateOutput();
            output.updatedCount = 0;
            output.createdCount = 0;
            output.standardCreatedCount = 0;
            output.success = false;

            try {
                // Validate inputs
                if (input.product2Id == null || input.pricebook2Id == null) {
                    output.errorMessage = 'Product2Id and Pricebook2Id are required';
                    outputs.add(output);
                    continue;
                }

                // Get Standard Pricebook ID for creating missing Standard entries
                Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
                Boolean targetIsStandardPricebook = (input.pricebook2Id == standardPricebookId);

                // Query ALL PricebookEntry records (active AND inactive) for this Product + Pricebook
                // to detect and handle duplicates
                Map<String, List<PricebookEntry>> allEntriesByCurrency = new Map<String, List<PricebookEntry>>();
                for (PricebookEntry pbe : [
                    SELECT Id, CurrencyIsoCode, UnitPrice, IsActive, ProductSellingModelId, CreatedDate
                    FROM PricebookEntry
                    WHERE Product2Id = :input.product2Id
                    AND Pricebook2Id = :input.pricebook2Id
                    ORDER BY CurrencyIsoCode, CreatedDate DESC  // Newest first per currency
                ]) {
                    if (!allEntriesByCurrency.containsKey(pbe.CurrencyIsoCode)) {
                        allEntriesByCurrency.put(pbe.CurrencyIsoCode, new List<PricebookEntry>());
                    }
                    allEntriesByCurrency.get(pbe.CurrencyIsoCode).add(pbe);
                }

                System.debug('Found entries by currency: ' + allEntriesByCurrency.keySet());

                // Query Standard Pricebook entries (BOTH active and inactive) to check which currencies exist
                // and find the ProductSellingModelId (prefer USD entry as it's most reliable)
                Map<String, Boolean> standardCurrenciesExist = new Map<String, Boolean>();
                Id productSellingModelId = null;
                Id usdProductSellingModelId = null;

                for (PricebookEntry pbe : [
                    SELECT CurrencyIsoCode, ProductSellingModelId, IsActive, CreatedDate
                    FROM PricebookEntry
                    WHERE Product2Id = :input.product2Id
                    AND Pricebook2.IsStandard = true
                    ORDER BY IsActive DESC, CreatedDate DESC  // Prefer active, then newest
                ]) {
                    standardCurrenciesExist.put(pbe.CurrencyIsoCode, true);

                    // Prefer USD entry's ProductSellingModelId as it's most reliable
                    if (pbe.CurrencyIsoCode == 'USD' && pbe.ProductSellingModelId != null && usdProductSellingModelId == null) {
                        usdProductSellingModelId = pbe.ProductSellingModelId;
                    }

                    // Fallback: any non-null ProductSellingModelId (prefer active entries)
                    if (pbe.ProductSellingModelId != null && productSellingModelId == null) {
                        productSellingModelId = pbe.ProductSellingModelId;
                    }
                }

                // Use USD's ProductSellingModelId if available, otherwise use fallback
                if (usdProductSellingModelId != null) {
                    productSellingModelId = usdProductSellingModelId;
                }

                System.debug('Standard currencies that exist: ' + standardCurrenciesExist.keySet());
                System.debug('ProductSellingModelId to use: ' + productSellingModelId);

                // VALIDATION: Warn if ProductSellingModelId is missing
                if (productSellingModelId == null) {
                    System.debug(LoggingLevel.WARN, 'WARNING: ProductSellingModelId is null! New entries will be created without ProductSellingModelId.');
                    System.debug(LoggingLevel.WARN, 'This may cause issues with Revenue Cloud pricing. Verify ProductSellingModelOption exists for this product.');
                }

                // Validate parallel lists
                if (input.currencyIsoCodes == null || input.unitPrices == null) {
                    output.errorMessage = 'Currency codes and unit prices lists are required';
                    outputs.add(output);
                    continue;
                }

                if (input.currencyIsoCodes.size() != input.unitPrices.size()) {
                    output.errorMessage = 'Currency codes and unit prices lists must have the same size';
                    outputs.add(output);
                    continue;
                }

                // Prepare collections for DML
                List<PricebookEntry> entriesToUpdate = new List<PricebookEntry>();
                List<PricebookEntry> entriesToCreate = new List<PricebookEntry>();
                List<PricebookEntry> standardEntriesToCreate = new List<PricebookEntry>();

                // Track which currencies need Standard Pricebook entries created
                Set<String> currenciesNeedingStandardEntry = new Set<String>();

                // Process each currency price (parallel lists)
                for (Integer i = 0; i < input.currencyIsoCodes.size(); i++) {
                    String currencyCode = input.currencyIsoCodes[i];
                    Decimal price = input.unitPrices[i];

                    if (String.isBlank(currencyCode) || price == null) {
                        continue; // Skip invalid entries
                    }

                    System.debug('Processing currency: ' + currencyCode + ', price: ' + price);

                    // Check if entries exist for this currency
                    if (allEntriesByCurrency.containsKey(currencyCode)) {
                        List<PricebookEntry> entries = allEntriesByCurrency.get(currencyCode);

                        if (entries.size() > 1) {
                            // DUPLICATE DETECTED - Keep newest, deactivate others
                            System.debug('WARNING: Found ' + entries.size() + ' entries for ' + currencyCode + ' - deactivating duplicates');

                            for (Integer j = 1; j < entries.size(); j++) {
                                PricebookEntry duplicateEntry = entries[j];
                                if (duplicateEntry.IsActive) {
                                    duplicateEntry.IsActive = false;
                                    entriesToUpdate.add(duplicateEntry);
                                    System.debug('Deactivating duplicate entry: ' + duplicateEntry.Id);
                                }
                            }
                        }

                        // Update the first (newest) entry
                        PricebookEntry entryToKeep = entries[0];

                        // CRITICAL FIX: If ProductSellingModelId is null, we must DELETE and RECREATE
                        // because Salesforce only populates ProductSellingModelId on INSERT, not UPDATE
                        if (entryToKeep.ProductSellingModelId == null && productSellingModelId != null) {
                            System.debug('ProductSellingModelId is null for ' + currencyCode + ' - will DELETE and RECREATE to fix');

                            // Delete the entry (and any duplicates)
                            List<PricebookEntry> entriesToDelete = new List<PricebookEntry>();
                            for (PricebookEntry entry : entries) {
                                entriesToDelete.add(entry);
                            }
                            delete entriesToDelete;

                            // Create new entry with ProductSellingModelId explicitly set
                            PricebookEntry newEntry = new PricebookEntry(
                                Product2Id = input.product2Id,
                                Pricebook2Id = input.pricebook2Id,
                                CurrencyIsoCode = currencyCode,
                                UnitPrice = price,
                                IsActive = true,
                                ProductSellingModelId = productSellingModelId  // CRITICAL: Must be set on INSERT
                            );
                            entriesToCreate.add(newEntry);
                            System.debug('Will DELETE old entry and CREATE new entry for ' + currencyCode + ' with ProductSellingModelId: ' + productSellingModelId);
                        } else {
                            // ProductSellingModelId is already populated - safe to update
                            entryToKeep.UnitPrice = price;
                            entryToKeep.IsActive = true;
                            entriesToUpdate.add(entryToKeep);
                            System.debug('Will UPDATE entry for ' + currencyCode + ': ' + entryToKeep.Id);
                        }

                    } else {
                        // No existing entry - need to create one
                        // Check if we need to create Standard Pricebook entry first
                        if (!standardCurrenciesExist.containsKey(currencyCode)) {
                            // Mark this currency as needing a Standard Pricebook entry
                            currenciesNeedingStandardEntry.add(currencyCode);
                            System.debug('Will CREATE Standard Pricebook entry for ' + currencyCode);

                            // If target IS Standard Pricebook, we'll create it directly there
                            // No need to create it twice
                            if (targetIsStandardPricebook) {
                                System.debug('Target IS Standard Pricebook - will create entry directly');
                                continue; // Skip adding to entriesToCreate since we'll create in Standard
                            }
                        }

                        // Prepare to create entry in target pricebook
                        // (will be created after Standard entries if needed)
                        PricebookEntry newEntry = new PricebookEntry(
                            Product2Id = input.product2Id,
                            Pricebook2Id = input.pricebook2Id,
                            CurrencyIsoCode = currencyCode,
                            UnitPrice = price,
                            IsActive = true,
                            ProductSellingModelId = productSellingModelId  // Use same selling model as Standard entries
                        );
                        entriesToCreate.add(newEntry);
                        System.debug('Will CREATE new entry for ' + currencyCode);
                    }
                }

                // Create Standard Pricebook entries for currencies that don't have them
                if (!currenciesNeedingStandardEntry.isEmpty()) {
                    System.debug('Creating Standard Pricebook entries for: ' + currenciesNeedingStandardEntry);

                    for (String currencyCode : currenciesNeedingStandardEntry) {
                        // Find the price for this currency from the parallel lists
                        Decimal standardPrice = null;
                        for (Integer i = 0; i < input.currencyIsoCodes.size(); i++) {
                            if (input.currencyIsoCodes[i] == currencyCode) {
                                standardPrice = input.unitPrices[i];
                                break;
                            }
                        }

                        if (standardPrice != null) {
                            PricebookEntry standardEntry = new PricebookEntry(
                                Product2Id = input.product2Id,
                                Pricebook2Id = standardPricebookId,
                                CurrencyIsoCode = currencyCode,
                                UnitPrice = standardPrice,
                                IsActive = true,
                                ProductSellingModelId = productSellingModelId
                            );
                            standardEntriesToCreate.add(standardEntry);
                        }
                    }

                    // Create Standard Pricebook entries FIRST (required by Salesforce)
                    if (!standardEntriesToCreate.isEmpty()) {
                        insert standardEntriesToCreate;

                        // If target IS Standard Pricebook, count these as "created" entries
                        // Otherwise, count them separately as "standardCreatedCount"
                        if (targetIsStandardPricebook) {
                            output.createdCount += standardEntriesToCreate.size();
                            System.debug('Created ' + standardEntriesToCreate.size() + ' entries in Standard Pricebook (target)');
                        } else {
                            output.standardCreatedCount = standardEntriesToCreate.size();
                            System.debug('Created ' + standardEntriesToCreate.size() + ' Standard Pricebook entries');
                        }
                    }
                }

                // Perform bulk DML operations
                if (!entriesToUpdate.isEmpty()) {
                    update entriesToUpdate;
                    output.updatedCount = entriesToUpdate.size();
                }

                if (!entriesToCreate.isEmpty()) {
                    insert entriesToCreate;
                    output.createdCount = entriesToCreate.size();
                }

                output.success = true;

            } catch (Exception e) {
                output.errorMessage = e.getMessage();
                output.success = false;
                System.debug(LoggingLevel.ERROR, 'Error updating pricebook entries: ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            }

            outputs.add(output);
        }

        return outputs;
    }
}