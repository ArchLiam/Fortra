/**
 * @description Controller for Quote repricing operations
 * Handles automatic repricing after discount updates with proper timing checks
 */
public with sharing class QuoteRepricingController {

    /**
     * @description Reprice all quote line items after a delay to avoid record locking
     * @param quoteId The ID of the Quote to reprice
     * @param discountType Type of discount: 'PERCENTAGE' or 'AMOUNT'
     * @return Result object with success status and message
     */
    @AuraEnabled
    public static RepricingResult repriceQuote(Id quoteId, String discountType) {
        RepricingResult result = new RepricingResult();

        // Default to PERCENTAGE if not specified
        if (String.isBlank(discountType)) {
            discountType = 'PERCENTAGE';
        }

        try {
            // Verify quote exists and is accessible
            Quote quote = [
                SELECT Id, Status, Header_Discount_Value__c, Manual_Discount__c, Header_Distribution_Logic__c
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];

            System.debug('Starting repricing for quote: ' + quoteId);

            // Get all quote line items (include Subtotal for proportionate distribution)
            List<QuoteLineItem> lineItems = [
                SELECT Id, Discount, ListPrice, Quantity, UnitPrice, Subtotal
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
            ];

            if (lineItems.isEmpty()) {
                result.success = true;
                result.message = 'No line items to reprice';
                return result;
            }

            System.debug('Found ' + lineItems.size() + ' line items to reprice');

            // Get the header discount value to apply to all line items
            Decimal headerDiscount = quote.Header_Discount_Value__c != null ? quote.Header_Discount_Value__c : 0;
            String distributionLogic = quote.Header_Distribution_Logic__c != null ? quote.Header_Distribution_Logic__c : 'Proportionate';
            System.debug('Applying header discount: ' + headerDiscount + ' as ' + discountType + ' with distribution: ' + distributionLogic);

            // Pre-calculate totals for AMOUNT distribution (only eligible lines with Subtotal > 0)
            Decimal totalSubtotal = 0;
            Integer eligibleLineCount = 0;
            if (discountType == 'AMOUNT') {
                for (QuoteLineItem item : lineItems) {
                    Decimal sub = item.Subtotal != null ? item.Subtotal : 0;
                    if (sub > 0) {
                        totalSubtotal += sub;
                        eligibleLineCount++;
                    }
                }
            }
            System.debug('Total subtotal for distribution: ' + totalSubtotal + ', eligible lines: ' + eligibleLineCount);

            // Pre-calculate AMOUNT discounts per line (with redistribution of capped excess)
            Map<Id, Decimal> lineDiscountMap = new Map<Id, Decimal>();
            if (discountType == 'AMOUNT') {
                // Build subtotal map for eligible lines
                Map<Id, Decimal> subtotalMap = new Map<Id, Decimal>();
                for (QuoteLineItem item : lineItems) {
                    Decimal sub = item.Subtotal != null ? item.Subtotal : 0;
                    subtotalMap.put(item.Id, sub);
                    lineDiscountMap.put(item.Id, 0);
                }

                if (distributionLogic == 'Equal') {
                    // Equal with iterative redistribution of capped excess
                    Set<Id> uncappedIds = new Set<Id>();
                    for (QuoteLineItem item : lineItems) {
                        if (subtotalMap.get(item.Id) > 0) {
                            uncappedIds.add(item.Id);
                        }
                    }

                    Decimal remaining = headerDiscount;
                    Integer safetyLimit = 10;
                    while (remaining > 0.01 && !uncappedIds.isEmpty() && safetyLimit-- > 0) {
                        Decimal share = remaining / uncappedIds.size();
                        Decimal excess = 0;
                        Set<Id> newlyCapped = new Set<Id>();

                        for (Id itemId : uncappedIds) {
                            Decimal sub = subtotalMap.get(itemId);
                            Decimal currentDiscount = lineDiscountMap.get(itemId);
                            Decimal headroom = sub - currentDiscount;

                            if (share >= headroom) {
                                // Cap at subtotal, accumulate excess
                                lineDiscountMap.put(itemId, sub);
                                excess += (share - headroom);
                                newlyCapped.add(itemId);
                            } else {
                                lineDiscountMap.put(itemId, currentDiscount + share);
                            }
                        }
                        uncappedIds.removeAll(newlyCapped);
                        remaining = excess;
                    }
                } else {
                    // Proportionate: distribute based on line's share of total subtotal
                    for (QuoteLineItem item : lineItems) {
                        Decimal sub = subtotalMap.get(item.Id);
                        if (sub > 0 && totalSubtotal > 0) {
                            Decimal lineAmt = headerDiscount * (sub / totalSubtotal);
                            // Cap at subtotal
                            lineDiscountMap.put(item.Id, Math.min(lineAmt, sub));
                        }
                    }
                }
            }

            // Build update records
            List<QuoteLineItem> itemsToUpdate = new List<QuoteLineItem>();

            for (QuoteLineItem item : lineItems) {
                QuoteLineItem updateItem = new QuoteLineItem(Id = item.Id);

                if (discountType == 'PERCENTAGE') {
                    updateItem.Discount = headerDiscount;
                    updateItem.DiscountAmount = null;
                } else {
                    Decimal lineDiscountAmount = lineDiscountMap.get(item.Id);

                    // IMPORTANT: DiscountAmount is a PER-UNIT field, not per-line!
                    Decimal quantity = item.Quantity != null && item.Quantity > 0 ? item.Quantity : 1;
                    Decimal perUnitDiscount = (lineDiscountAmount / quantity).setScale(2, RoundingMode.HALF_UP);

                    // Cap per-unit discount at UnitPrice to pass validation
                    Decimal unitPrice = item.UnitPrice != null ? item.UnitPrice : 0;
                    if (perUnitDiscount > unitPrice && unitPrice > 0) {
                        perUnitDiscount = unitPrice;
                    }

                    updateItem.DiscountAmount = perUnitDiscount;
                    updateItem.Discount = null;
                    System.debug('Line ' + item.Id + ': discount=' + lineDiscountAmount + ' perUnit=' + perUnitDiscount);
                }

                itemsToUpdate.add(updateItem);
            }

            if (!itemsToUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(itemsToUpdate, false);

                Integer successCount = 0;
                Integer failureCount = 0;
                String errorDetails = '';

                for (Database.SaveResult sr : results) {
                    if (sr.isSuccess()) {
                        successCount++;
                    } else {
                        failureCount++;
                        for (Database.Error err : sr.getErrors()) {
                            errorDetails += err.getMessage() + '; ';
                        }
                    }
                }

                if (failureCount > 0) {
                    result.success = false;
                    result.message = 'Discount applied to ' + successCount + ' of ' + lineItems.size() + ' line items. Some items failed. Errors: ' + errorDetails;
                    result.itemCount = successCount;
                } else {
                    result.success = true;
                    String discountLabel = (discountType == 'AMOUNT') ? ('$' + headerDiscount) : (headerDiscount + '%');
                    result.message = 'Discount of ' + discountLabel + ' applied successfully to all ' + successCount + ' line items.';
                    result.itemCount = successCount;
                }
            }

        } catch (QueryException qe) {
            result.success = false;
            result.message = 'Quote not found: ' + qe.getMessage();
            System.debug(LoggingLevel.ERROR, 'Query error: ' + qe.getMessage());

        } catch (DmlException de) {
            result.success = false;
            result.message = 'Error updating line items: ' + de.getDmlMessage(0);
            System.debug(LoggingLevel.ERROR, 'DML error: ' + de.getMessage());

        } catch (Exception e) {
            result.success = false;
            result.message = 'Unexpected error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Unexpected error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }


    /**
     * @description Check if quote is locked (being edited by another process)
     * @param quoteId The ID of the Quote to check
     * @return True if quote is available (not locked)
     */
    @AuraEnabled
    public static Boolean isQuoteAvailable(Id quoteId) {
        try {
            // Try to lock the quote for update
            Quote quote = [
                SELECT Id
                FROM Quote
                WHERE Id = :quoteId
                FOR UPDATE
            ];
            return true; // If we got here, quote is available

        } catch (Exception e) {
            System.debug('Quote is locked: ' + e.getMessage());
            return false; // Quote is locked
        }
    }

    /**
     * @description Wait for quote to become available with polling
     * @param quoteId The ID of the Quote to check
     * @param maxAttempts Maximum number of polling attempts (default 10)
     * @param delayMs Delay between attempts in milliseconds (default 500)
     * @return Result with availability status
     */
    @AuraEnabled
    public static AvailabilityResult waitForQuoteAvailable(Id quoteId, Integer maxAttempts, Integer delayMs) {
        AvailabilityResult result = new AvailabilityResult();

        if (maxAttempts == null) maxAttempts = 10;
        if (delayMs == null) delayMs = 500;

        Integer attempts = 0;
        Boolean available = false;

        while (attempts < maxAttempts && !available) {
            attempts++;
            available = isQuoteAvailable(quoteId);

            if (!available && attempts < maxAttempts) {
                // Sleep is not available in Apex, so we just try again
                // The delay will need to be handled on the client side
                System.debug('Quote not available, attempt ' + attempts + ' of ' + maxAttempts);
            }
        }

        result.available = available;
        result.attempts = attempts;
        result.message = available ?
            'Quote is available after ' + attempts + ' attempt(s)' :
            'Quote is still locked after ' + maxAttempts + ' attempts';

        return result;
    }

    /**
     * Wrapper class for repricing results
     */
    public class RepricingResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer itemCount;

        public RepricingResult() {
            this.success = false;
            this.message = '';
            this.itemCount = 0;
        }
    }

    /**
     * Wrapper class for availability check results
     */
    public class AvailabilityResult {
        @AuraEnabled public Boolean available;
        @AuraEnabled public Integer attempts;
        @AuraEnabled public String message;

        public AvailabilityResult() {
            this.available = false;
            this.attempts = 0;
            this.message = '';
        }
    }
}