import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference } from 'lightning/navigation';

// Import Apex methods for repricing and lock polling
import repriceQuote from '@salesforce/apex/QuoteRepricingController.repriceQuote';
import isQuoteAvailable from '@salesforce/apex/QuoteRepricingController.isQuoteAvailable';

// Import fields
import QUOTE_ID from '@salesforce/schema/Quote.Id';
import CURRENCY_ISO_CODE from '@salesforce/schema/Quote.CurrencyIsoCode';
import START_DATE from '@salesforce/schema/Quote.StartDate';
import LATEST_EFFECTIVE_END_DATE from '@salesforce/schema/Quote.Latest_Effective_End_Date__c';
import HEADER_DISCOUNT_VALUE from '@salesforce/schema/Quote.Header_Discount_Value__c';
import MANUAL_DISCOUNT from '@salesforce/schema/Quote.Manual_Discount__c';
import HEADER_DISCOUNT_TYPE from '@salesforce/schema/Quote.Header_Discount_Type__c';
import HEADER_DISTRIBUTION_LOGIC from '@salesforce/schema/Quote.Header_Distribution_Logic__c';
import HEADER_DISTRIBUTION_TYPE from '@salesforce/schema/Quote.Header_Distribution_Type__c';
import SUBTOTAL from '@salesforce/schema/Quote.Subtotal';

const QUOTE_FIELDS = [
    CURRENCY_ISO_CODE,
    START_DATE,
    LATEST_EFFECTIVE_END_DATE,
    HEADER_DISCOUNT_VALUE,
    MANUAL_DISCOUNT,
    HEADER_DISCOUNT_TYPE,
    HEADER_DISTRIBUTION_LOGIC,
    HEADER_DISTRIBUTION_TYPE,
    SUBTOTAL
];

export default class QuoteLineFlexPanel extends LightningElement {
    @wire(CurrentPageReference)
    pageRef;
    @api recordId;

    @track currencyIsoCode;
    @track startDate;
    @track latestEffectiveEndDate;
    @track headerDiscountValue = 0;
    @track pendingDiscountValue = 0; // Store pending value before update
    @track discountType = 'Percentage'; // Percentage or Amount (must match picklist API values)
    @track distributionLogic = 'Proportionate'; // Equal or Proportionate
    @track quoteSubtotal = 0; // Quote subtotal for conversion calculations

    @track bulkStartDate;
    @track bulkEndDate;
    @track bulkTerm = 12;
    @track updateMode = 'DATE_RANGE';

    @track isLoading = false;
    @track isDiscountUpdating = false;
    @track showHardwareGroupModal = false;

    @track showBulkUpdateModal = false;

    wiredQuoteResult;

    // Currency options (read-only, but keeping structure for potential future use)
    currencyOptions = [];

    // Update mode options
    updateModeOptions = [
        { label: 'Date Range', value: 'DATE_RANGE' },
        { label: 'Date & Term', value: 'DATE_AND_TERM' }
    ];

    // Discount type options (values must match picklist API names)
    discountTypeOptions = [
        { label: 'Percentage', value: 'Percentage' },
        { label: 'Amount', value: 'Amount' }
    ];

    // Distribution logic options
    distributionLogicOptions = [
        { label: 'Equal', value: 'Equal' },
        { label: 'Proportionate', value: 'Proportionate' }
    ];

    get minDate() {
        const today = new Date();
        return today.toISOString().split('T')[0];
    }

    get isDateAndTermMode() {
        return this.updateMode === 'DATE_AND_TERM';
    }

    get isDiscountPercentage() {
        return this.discountType === 'Percentage';
    }

    get discountMaxValue() {
        return this.isDiscountPercentage ? '100' : '999999';
    }

    get discountFormatter() {
        return this.isDiscountPercentage ? 'percent-fixed' : 'currency';
    }

    get isDiscountChanged() {
        return this.pendingDiscountValue !== this.headerDiscountValue;
    }

    // Wire to get Quote record
    @wire(getRecord, { recordId: '$recordId', fields: QUOTE_FIELDS })
    wiredQuote(result) {
        this.wiredQuoteResult = result;
        const { data, error } = result;

        if (data) {
            this.currencyIsoCode = data.fields.CurrencyIsoCode?.value;
            this.startDate = data.fields.StartDate?.value;
            this.latestEffectiveEndDate = data.fields.Latest_Effective_End_Date__c?.value;
            this.bulkStartDate = data.fields.StartDate?.value;
            this.headerDiscountValue = data.fields.Header_Discount_Value__c?.value || 0;
            this.pendingDiscountValue = this.headerDiscountValue; // Initialize pending value
            const savedDiscountType = data.fields.Header_Discount_Type__c?.value;
            if (savedDiscountType) {
                this.discountType = savedDiscountType;
            }
            const savedDistLogic = data.fields.Header_Distribution_Logic__c?.value;
            if (savedDistLogic) {
                this.distributionLogic = savedDistLogic;
            }
            this.quoteSubtotal = data.fields.Subtotal?.value || 0;

            // Set currency options for display (read-only)
            if (this.currencyIsoCode) {
                this.currencyOptions = [
                    { label: this.currencyIsoCode, value: this.currencyIsoCode }
                ];
            }
        } else if (error) {
            this.showToast('Error', 'Error loading quote data: ' + this.getErrorMessage(error), 'error');
        }
    }

    // Handler for discount type change (Percentage vs Amount)
    handleDiscountTypeChange(event) {
        const previousType = this.discountType;
        const newType = event.detail.value;
        this.discountType = newType;

        // Convert the pending discount value when switching types
        if (this.pendingDiscountValue > 0 && this.quoteSubtotal > 0) {
            if (previousType === 'Percentage' && newType === 'Amount') {
                // Convert percentage to amount: (percentage / 100) * subtotal
                this.pendingDiscountValue = parseFloat(
                    ((this.pendingDiscountValue / 100) * this.quoteSubtotal).toFixed(2)
                );
            } else if (previousType === 'Amount' && newType === 'Percentage') {
                // Convert amount to percentage: (amount / subtotal) * 100
                this.pendingDiscountValue = parseFloat(
                    ((this.pendingDiscountValue / this.quoteSubtotal) * 100).toFixed(2)
                );
            }
        } else {
            // Reset pending value if no value or no subtotal
            this.pendingDiscountValue = 0;
        }
    }

    // Handler for distribution logic change
    handleDistributionLogicChange(event) {
        this.distributionLogic = event.detail.value;
    }

    // Handler for discount field change - just stores the value, doesn't trigger any actions
    handleHeaderDiscountChange(event) {
        this.pendingDiscountValue = parseFloat(event.target.value) || 0;
    }

    // Handler for Update Discount button click - performs the actual update
    async handleDiscountUpdate() {
        // Validate discount value based on type
        if (this.discountType === 'Percentage') {
            if (this.pendingDiscountValue < 0 || this.pendingDiscountValue > 100) {
                this.showToast('Invalid Discount', 'Percentage discount must be between 0 and 100', 'error');
                return;
            }
        } else {
            if (this.pendingDiscountValue < 0) {
                this.showToast('Invalid Discount', 'Discount amount cannot be negative', 'error');
                return;
            }
        }

        this.isDiscountUpdating = true;

        try {
            // Step 1: Update the Quote record with new discount value
            const fields = {};
            fields[QUOTE_ID.fieldApiName] = this.recordId;
            fields[HEADER_DISCOUNT_VALUE.fieldApiName] = this.pendingDiscountValue;
            fields[MANUAL_DISCOUNT.fieldApiName] = this.pendingDiscountValue;
            fields[HEADER_DISCOUNT_TYPE.fieldApiName] = this.discountType;
            fields[HEADER_DISTRIBUTION_LOGIC.fieldApiName] = this.distributionLogic;
            fields[HEADER_DISTRIBUTION_TYPE.fieldApiName] = 'NetUnitPrice';

            const recordInput = { fields };

            await updateRecord(recordInput);

            // Step 2: Brief delay to let any platform processes settle
            await this.sleep(2000);

            const discountLabel = this.discountType === 'Percentage' ?
                `${this.pendingDiscountValue}%` :
                `${this.currencyIsoCode} ${this.pendingDiscountValue}`;

            // Step 3: Call Apex to apply discount to all line items
            // repriceQuote updates QuoteLineItems (not the Quote), so it doesn't
            // need the Quote lock to be released
            const repricingResult = await repriceQuote({
                quoteId: this.recordId,
                discountType: this.discountType === 'Percentage' ? 'PERCENTAGE' : 'AMOUNT'
            });

            if (repricingResult.success) {
                this.showToast('Success',
                    `Discount updated to ${discountLabel} and ${repricingResult.itemCount} line items repriced.`,
                    'success');

                await refreshApex(this.wiredQuoteResult);
                this.dispatchEvent(new CustomEvent('refresh'));
                setTimeout(() => { window.location.reload(); }, 1500);

            } else {
                this.showToast('Warning',
                    `Discount saved (${discountLabel}) but repricing failed: ${repricingResult.message}. Please click "Reprice All" manually.`,
                    'warning');
                await refreshApex(this.wiredQuoteResult);
            }

        } catch (error) {
            this.showToast('Error', 'Error updating discount: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isDiscountUpdating = false;
        }
    }

    // Poll for quote availability with client-side delays
    async waitForQuoteAvailable(maxAttempts, delayMs) {
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                const available = await isQuoteAvailable({ quoteId: this.recordId });

                if (available) {
                    console.log(`Quote available after ${attempt} attempt(s)`);
                    return true;
                }

                // Wait before next attempt (except on last attempt)
                if (attempt < maxAttempts) {
                    await this.sleep(delayMs);
                }

            } catch (error) {
                console.error(`Error checking quote availability (attempt ${attempt}):`, error);
            }
        }

        console.warn(`Quote still not available after ${maxAttempts} attempts`);
        return false;
    }


    // Currency change handler (currently disabled but kept for structure)
    handleCurrencyChange(event) {
        // Currency is read-only in current implementation
        console.log('Currency change not implemented');
    }

    // Update Mode change handler
    handleUpdateModeChange(event) {
        this.updateMode = event.detail.value;
    }

    // Bulk Start Date change handler
    handleBulkStartDateChange(event) {
        this.bulkStartDate = event.target.value;
    }

    // Bulk End Date change handler
    handleBulkEndDateChange(event) {
        this.bulkEndDate = event.target.value;
    }

    // Bulk Term change handler
    handleBulkTermChange(event) {
        this.bulkTerm = parseInt(event.target.value, 10) || 12;
    }

    // Bulk Update handler - validates inputs then opens selection modal
    handleBulkUpdate() {
        // Validate inputs before opening modal
        if (!this.bulkStartDate) {
            this.showToast('Missing Required Field', 'Please enter a Start Date', 'error');
            return;
        }
        if (this.updateMode === 'DATE_RANGE' && !this.bulkEndDate) {
            this.showToast('Missing Required Field', 'Please enter an End Date', 'error');
            return;
        }
        if (this.updateMode === 'DATE_AND_TERM' && (!this.bulkTerm || this.bulkTerm < 1)) {
            this.showToast('Invalid Term', 'Please enter a valid term (1-120 months)', 'error');
            return;
        }
        this.showBulkUpdateModal = true;
    }

    handleBulkUpdateCancel() {
        this.showBulkUpdateModal = false;
    }

    handleBulkUpdateSuccess() {
        this.showBulkUpdateModal = false;
        this.showToast('Success', 'Subscription dates updated successfully', 'success');
        refreshApex(this.wiredQuoteResult);
        setTimeout(() => {
            window.location.reload();
        }, 1500);
    }

    // Hardware Groups button handler
    handleNewHardwareGroup() {
        this.showHardwareGroupModal = true;
    }

    // Hardware Group Modal handlers
    handleHardwareGroupCancel() {
        this.showHardwareGroupModal = false;
    }

    handleHardwareGroupSuccess() {
        this.showHardwareGroupModal = false;
        this.showToast('Success', 'Hardware group created successfully', 'success');
        // Refresh the view
        this.dispatchEvent(new CustomEvent('refresh'));
        setTimeout(() => {
            window.location.reload();
        }, 1000);
    }

    // Utility functions
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    getErrorMessage(error) {
        if (error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors[0].message;
            }
            if (error.body.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors);
                if (fieldErrors.length > 0 && fieldErrors[0].length > 0) {
                    return fieldErrors[0][0].message;
                }
            }
        }
        return error.message || 'Unknown error';
    }

    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}