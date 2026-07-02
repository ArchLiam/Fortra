/**
 * Hardware Group Manager LWC Component
 *
 * Unified modal for managing hardware groups in Revenue Cloud:
 * - Mode 1: Create New Hardware Group
 * - Mode 2: Edit Existing Hardware Group
 * - Mode 3: Assign Hardware to Group
 *
 * @author Marc DeBrey
 * @version 1.1 - Added hardware attribute display for pGroup, Server Type, Users Per Partition
 * @since 2025-01
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';

// Import Apex methods
import getQuoteAccountId from '@salesforce/apex/HardwareGroupController.getQuoteAccountId';
import getExistingGroups from '@salesforce/apex/HardwareGroupController.getExistingGroups';
import searchHardware from '@salesforce/apex/HardwareGroupController.searchHardware';
import getUnassignedHardware from '@salesforce/apex/HardwareGroupController.getUnassignedHardware';
import createHardwareRecord from '@salesforce/apex/HardwareGroupController.createHardwareRecord';
import getHardwareById from '@salesforce/apex/HardwareGroupController.getHardwareById';
import createHardwareGroup from '@salesforce/apex/HardwareGroupController.createHardwareGroup';
import updateHardwareGroup from '@salesforce/apex/HardwareGroupController.updateHardwareGroup';
import assignHardwareToGroup from '@salesforce/apex/HardwareGroupController.assignHardwareToGroup';
import getPicklistOptions from '@salesforce/apex/HardwareGroupController.getPicklistOptions';
import getFeatureCodeOptions from '@salesforce/apex/HardwareGroupController.getFeatureCodeOptions';
import getHardwareAttributesForLWC from '@salesforce/apex/HardwarePreConfigInvocable.getHardwareAttributesForLWC';

export default class HardwareGroupManager extends LightningElement {
    // ========== API Properties ==========
    @api recordId; // Quote ID from parent context
    @api objectApiName; // Should be 'Quote' or Revenue Cloud quote object

    // ========== State Management ==========
    @track currentMode = null; // 'create' | 'edit' | 'assign'
    @track currentStep = 'mode-selection'; // State machine current step
    @track isLoading = false;

    // ========== Data Properties ==========
    @track existingGroups = [];
    @track hardwareRecords = [];
    @track selectedGroup = null;
    @track selectedHardware = null;
    @track hardwareAttributes = null; // Hardware attributes from HardwarePreConfigInvocable
    @track picklistOptions = {};
    @track quoteAccountId = null;

    // ========== Form Data ==========
    @track groupName = '';
    @track hardwareNotes = '';
    @track assignHardwareNow = false;
    @track newHardware = {
        // Hardware Name (first field, also used for Group Name)
        hardwareName: '',
        // Hardware Platform (controls conditional field display)
        hardwarePlatform: '',
        // iSeries-specific fields
        serialNumber: '',
        iSeriesModel: '',
        featureCode: '',
        processors: null,
        pGroup: '',
        // Cross Platform-specific fields
        hostname: '',
        hardwareId: '',
        operatingSystem: '',
        // Common configuration attributes (shared across platforms)
        serverType: '',
        usersPerPartition: null,
        // Legacy fields (hidden from new form)
        status: '',
        category: '',
        environment: '',
        cpw: null,
        storage: null
    };
    @track featureCodeOptions = []; // Dependent picklist options based on selected model

    // ========== Search Filters ==========
    @track searchFilters = {
        status: '',
        category: '',
        environment: '',
        serialNumber: '',
        model: ''
    };

    // ========== UI State ==========
    @track showModeSelection = true;
    @track showGroupSelection = false;
    @track showHardwareSearch = false;
    @track showCreateHardware = false;
    @track showGroupConfig = false;
    @track validationErrors = [];
    @track hardwareCreatedAndSelected = false; // Flag to track if hardware was just created

    // ========== Computed Properties ==========
    get isModeSelection() {
        return this.currentStep === 'mode-selection';
    }

    get isHardwareSelectionStep() {
        return this.currentStep === 'hardware-selection';
    }

    get modeOptions() {
        return [
            { label: 'Create New Hardware Group', value: 'create' },
            { label: 'Edit Existing Hardware Group', value: 'edit' },
            { label: 'Assign Hardware to Group', value: 'assign' }
        ];
    }

    get groupColumns() {
        return [
            { label: 'Group Name', fieldName: 'Name', type: 'text' },
            { label: 'Hardware ID', fieldName: 'Hardware__r.Hardware_ID__c', type: 'text' },
            { label: 'Model', fieldName: 'modelDisplay', type: 'text' },
            { label: '# Lines', fieldName: 'lineCount', type: 'number' },
            { label: 'Notes', fieldName: 'Hardware_Notes__c', type: 'text' }
        ];
    }

    get hardwareColumns() {
        return [
            { label: 'Hardware ID', fieldName: 'Hardware_ID__c', type: 'text' },
            { label: 'Model', fieldName: 'modelDisplay', type: 'text' },
            { label: 'Serial Number', fieldName: 'Serial_Number__c', type: 'text' },
            { label: 'Status', fieldName: 'Status__c', type: 'text' },
            { label: 'Category', fieldName: 'Hardware_Category__c', type: 'text' }
        ];
    }

    // SC-3468: resolve the model shown in the UI. iSeries hardware stores its model in the typed
    // iSeries_Model__c picklist (which also controls the Feature Code dependent picklist); legacy /
    // non-iSeries hardware uses the free-text Model_Number__c. Flatten to a single `modelDisplay` so
    // the value the user picked is visible in the datatable and detail cards regardless of platform.
    decorateModel(rec) {
        if (!rec) {
            return rec;
        }
        return { ...rec, modelDisplay: rec.iSeries_Model__c || rec.Model_Number__c || '' };
    }

    get canProceed() {
        // TODO: Implement validation logic based on current step
        if (this.isModeSelection) {
            return this.currentMode !== null;
        }
        return true;
    }

    get canFinish() {
        if (this.currentMode === 'create') {
            // Create mode requires group name (unique) and hardware if "Assign or change hardware" is checked
            if (this.assignHardwareNow) {
                return this.groupName !== '' && !this.isGroupNameDuplicate(this.groupName) && this.selectedHardware !== null;
            }
            return this.groupName !== '' && !this.isGroupNameDuplicate(this.groupName);
        }
        if (this.currentMode === 'edit') {
            // Edit mode requires unique name and hardware selection if hardware section is shown
            if (this.assignHardwareNow) {
                return this.groupName !== '' && !this.isGroupNameDuplicate(this.groupName) && this.selectedHardware !== null;
            }
            return this.groupName !== '' && !this.isGroupNameDuplicate(this.groupName);
        }
        if (this.currentMode === 'assign') {
            // Assign mode requires hardware selection
            return this.selectedHardware !== null;
        }
        return true;
    }

    get modalTitle() {
        if (this.currentMode === 'create') return 'Create New Hardware Group';
        if (this.currentMode === 'edit') return 'Edit Hardware Group';
        if (this.currentMode === 'assign') return 'Assign Hardware to Group';
        return 'Hardware Groups Management';
    }

    get statusOptions() {
        return this.picklistOptions.status || [];
    }

    get categoryOptions() {
        return this.picklistOptions.category || [];
    }

    get environmentOptions() {
        return this.picklistOptions.environment || [];
    }

    // ========== Hardware Platform Options ==========
    get hardwarePlatformOptions() {
        return this.picklistOptions.hardwarePlatform || [];
    }

    get iSeriesModelOptions() {
        return this.picklistOptions.iSeriesModel || [];
    }

    get pGroupOptions() {
        return this.picklistOptions.pGroup || [];
    }

    get operatingSystemOptions() {
        return this.picklistOptions.operatingSystem || [];
    }


    // ========== Conditional Display Properties ==========
    get isISeries() {
        return this.newHardware.hardwarePlatform === 'iSeries';
    }

    get isCrossPlatform() {
        return this.newHardware.hardwarePlatform === 'Cross Platform';
    }

    get showPlatformFields() {
        return this.newHardware.hardwarePlatform !== '';
    }

    get featureCodeDisabled() {
        return !this.newHardware.iSeriesModel;
    }

    get accountId() {
        // Get account from quote - will need to query this
        return this.quoteAccountId;
    }

    get isEditMode() {
        return this.currentMode === 'edit';
    }

    get isAssignMode() {
        return this.currentMode === 'assign';
    }

    get showHardwareAssignment() {
        // Show hardware assignment section for both Create and Edit modes
        return this.currentMode === 'create' || this.currentMode === 'edit';
    }

    get finishButtonLabel() {
        if (this.currentMode === 'create') return 'Create Group';
        if (this.currentMode === 'edit') return 'Update Group';
        if (this.currentMode === 'assign') return 'Assign to Group';
        return 'Finish';
    }

    get continueDisabled() {
        return !this.canProceed;
    }

    get selectedGroupDisabled() {
        return !this.selectedGroup;
    }

    get selectedHardwareDisabled() {
        return !this.selectedHardware;
    }

    get canFinishDisabled() {
        return !this.canFinish;
    }

    // ========== Wizard Progress ==========
    get wizardStages() {
        // Define stages based on current mode
        const stages = [];

        if (this.currentMode === 'create') {
            // Create mode stages
            stages.push(
                { key: 'mode-selection', label: 'Select Mode', completed: true, active: false },
                { key: 'configure-group', label: 'Configure Group', completed: this.currentStep !== 'configure-group', active: this.currentStep === 'configure-group' }
            );
            // Only add hardware selection step if user has checked the checkbox
            if (this.assignHardwareNow) {
                stages.push({ key: 'hardware-selection', label: 'Hardware Selection', completed: false, active: this.currentStep === 'hardware-selection' });
            }
        } else if (this.currentMode === 'edit') {
            stages.push(
                { key: 'mode-selection', label: 'Select Mode', completed: true, active: false },
                { key: 'select-group', label: 'Select Group', completed: this.currentStep !== 'select-group', active: this.currentStep === 'select-group' },
                { key: 'configure-group', label: 'Edit Group', completed: false, active: this.currentStep === 'configure-group' }
            );
        } else if (this.currentMode === 'assign') {
            stages.push(
                { key: 'mode-selection', label: 'Select Mode', completed: true, active: false },
                { key: 'select-hardware', label: 'Select Hardware', completed: this.currentStep !== 'select-hardware', active: this.currentStep === 'select-hardware' },
                { key: 'select-group', label: 'Select Group', completed: false, active: this.currentStep === 'select-group' }
            );
        } else {
            stages.push(
                { key: 'mode-selection', label: 'Select Mode', completed: false, active: true }
            );
        }

        return stages;
    }

    get currentStepValue() {
        // Return the current step key for lightning-progress-indicator
        // Find the active stage and return its key
        const activeStage = this.wizardStages.find(stage => stage.active);
        return activeStage ? activeStage.key : 'mode-selection';
    }

    get showWizardProgress() {
        // Show wizard progress on ALL screens, including mode selection
        return true;
    }

    get showAvailableHardware() {
        // Hide Available Hardware section if hardware was just created and selected
        return !this.hardwareCreatedAndSelected;
    }

    // ========== Hardware Attribute Display Properties ==========
    get hasHardwareAttributes() {
        return this.hardwareAttributes && this.hardwareAttributes.hasHardware;
    }

    get hardwarePGroupDisplay() {
        return this.hardwareAttributes?.pGroupValue || 'Not set';
    }



    // ========== Lifecycle Hooks ==========
    connectedCallback() {
        this.loadPicklistOptions();
        this.loadExistingGroups();
        this.loadQuoteAccount();
    }

    // ========== Wire Methods ==========
    wiredGroupsResult;
    @wire(getExistingGroups, { quoteId: '$recordId' })
    wiredGroups(result) {
        this.wiredGroupsResult = result;
        if (result.data) {
            // Transform data to add lineCount field for datatable
            this.existingGroups = result.data.map(group => ({
                ...group,
                lineCount: group.QuoteLineItems ? group.QuoteLineItems.length : 0,
                // SC-3468: flatten the related hardware model (iSeries code preferred) for the datatable
                modelDisplay: group.Hardware__r
                    ? (group.Hardware__r.iSeries_Model__c || group.Hardware__r.Model_Number__c || '')
                    : ''
            }));
            console.log('Loaded hardware groups:', this.existingGroups.length, this.existingGroups);
        } else if (result.error) {
            console.error('Error loading hardware groups:', result.error);
            this.showToast('Error', 'Failed to load hardware groups', 'error');
        }
    }

    // ========== Data Loading Methods ==========
    async loadPicklistOptions() {
        try {
            this.picklistOptions = await getPicklistOptions();
        } catch (error) {
            this.showToast('Error', 'Failed to load filter options', 'error');
        }
    }

    async loadExistingGroups() {
        // Handled by @wire
    }

    // ========== Mode Selection ==========
    handleModeSelection(event) {
        this.currentMode = event.detail.value;
    }

    handleContinue() {
        if (!this.currentMode) {
            this.showToast('Warning', 'Please select an option', 'warning');
            return;
        }

        this.showModeSelection = false;
        this.initializeWorkflow(this.currentMode);
    }

    async initializeWorkflow(mode) {
        // Set up initial state for selected workflow
        if (mode === 'create') {
            this.showGroupConfig = true;
            this.currentStep = 'configure-group';
        } else if (mode === 'edit') {
            this.showGroupSelection = true;
            this.currentStep = 'select-group';
        } else if (mode === 'assign') {
            // New workflow: Skip group selection, go directly to hardware search
            // Automatically load unassigned hardware for the account
            await this.loadUnassignedHardware();
            this.showHardwareSearch = true;
            this.currentStep = 'select-hardware';
        }
    }

    /**
     * @description Load unassigned hardware for the account (for assign mode)
     */
    async loadUnassignedHardware() {
        try {
            this.isLoading = true;

            // Get account ID from quote if not already loaded
            if (!this.quoteAccountId) {
                await this.loadQuoteAccount();
            }

            // Call getUnassignedHardware Apex method
            const results = await getUnassignedHardware({
                quoteId: this.recordId,
                accountId: this.quoteAccountId
            });

            this.hardwareRecords = results.map(rec => this.decorateModel(rec));

            if (results.length === 0) {
                this.showToast('Info', 'No unassigned hardware found for this account', 'info');
            }

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to load unassigned hardware', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ========== Hardware Search ==========
    async handleSearchHardware() {
        try {
            this.isLoading = true;

            // Get account ID from quote if not already loaded
            if (!this.quoteAccountId) {
                await this.loadQuoteAccount();
            }

            // Call searchHardware Apex method
            const results = await searchHardware({
                accountId: this.quoteAccountId,
                filters: this.searchFilters
            });

            this.hardwareRecords = results.map(rec => this.decorateModel(rec));

            if (results.length === 0) {
                this.showToast('Info', 'No hardware found matching your criteria', 'info');
            }

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to search hardware', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleHardwareSelection(event) {
        const selectedRows = event.detail.selectedRows;
        if (selectedRows.length > 0) {
            const hardware = selectedRows[0];

            // Check if hardware has non-Quoting status (edit restriction)
            // Only applies in edit mode - assign mode can assign any hardware
            if (this.currentMode === 'edit' && hardware.Status__c && hardware.Status__c !== 'Quoting') {
                this.showToast(
                    'Selection Restricted',
                    'Hardware with owned products cannot be assigned. Only hardware in "Quoting" status can be used.',
                    'warning'
                );
                this.selectedHardware = null;
                this.hardwareAttributes = null;
                return;
            }

            this.selectedHardware = hardware;
            // Fetch hardware attributes for display
            await this.fetchHardwareAttributes(this.selectedHardware.Id);
        } else {
            this.selectedHardware = null;
            this.hardwareAttributes = null;
        }
    }

    /**
     * @description Fetch hardware attributes for the selected hardware
     * @param {String} hardwareId - The Hardware__c record ID
     */
    async fetchHardwareAttributes(hardwareId) {
        if (!hardwareId) {
            this.hardwareAttributes = null;
            return;
        }

        try {
            // Use the HardwarePreConfigInvocable to get attributes
            // Note: This method expects a QuoteLineGroup ID, but we have hardware ID
            // We need to call getHardwareAttributesForLWC differently or use a direct query
            // For now, we'll set attributes from the selectedHardware record itself
            const hw = this.selectedHardware;
            this.hardwareAttributes = {
                hasHardware: true,
                pGroupValue: this.normalizePGroupValue(hw.P_Group_List__c),
                pGroupRawValue: hw.P_Group_List__c,
                serverType: hw.Server_Type__c,
                usersPerPartition: hw.Users_Per_Partition__c
            };
        } catch (error) {
            console.warn('[HardwareGroupManager] Error fetching hardware attributes:', error);
            this.hardwareAttributes = null;
        }
    }

    /**
     * @description Normalize pGroup value from P05 to P5 format
     * @param {String} rawValue - The raw pGroup value
     * @return {String} The normalized value
     */
    normalizePGroupValue(rawValue) {
        if (!rawValue) return null;
        // Convert P05 → P5 for display consistency with AttributeDefinition
        return rawValue === 'P05' ? 'P5' : rawValue;
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        this.searchFilters[field] = event.detail.value;
    }

    handleClearFilters() {
        this.searchFilters = {
            status: '',
            category: '',
            environment: '',
            serialNumber: '',
            model: ''
        };
        this.hardwareRecords = [];
    }

    async loadQuoteAccount() {
        try {
            this.quoteAccountId = await getQuoteAccountId({ quoteId: this.recordId });
            // Verify account was actually returned
            if (!this.quoteAccountId) {
                console.warn('[HardwareGroupManager] No Account found for Quote:', this.recordId);
            }
        } catch (error) {
            console.warn('[HardwareGroupManager] Error loading quote account:', error);
            this.showToast('Error', 'Failed to load quote account', 'error');
            throw error;
        }
    }

    // ========== Hardware Creation ==========
    handleToggleCreateHardware() {
        this.showCreateHardware = !this.showCreateHardware;
        if (this.showCreateHardware) {
            // Reset form with all new fields
            this.newHardware = {
                // Hardware Name (first field, also used for Group Name)
                hardwareName: '',
                // Hardware Platform (controls conditional field display)
                hardwarePlatform: '',
                // iSeries-specific fields
                serialNumber: '',
                iSeriesModel: '',
                featureCode: '',
                processors: null,
                pGroup: '',
                // Cross Platform-specific fields
                hostname: '',
                hardwareId: '',
                operatingSystem: '',
                // Common configuration attributes (shared across platforms)
                serverType: '',
                usersPerPartition: null,
                // Legacy fields (hidden from new form)
                status: '',
                category: '',
                environment: '',
                cpw: null,
                storage: null
            };
            // Clear feature code options
            this.featureCodeOptions = [];
        }
    }

    handleNewHardwareChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;

        switch(field) {
            // Hardware Name (first field - also auto-populates Group Name)
            case 'hardwareName':
                this.newHardware.hardwareName = value;
                // Auto-populate the Group Name with the Hardware Name
                this.groupName = value;
                this.validateGroupName();
                break;
            // Hardware Platform
            case 'hardwarePlatform':
                this.newHardware.hardwarePlatform = value;
                // Reset platform-specific fields when platform changes
                if (value === 'iSeries') {
                    this.newHardware.hostname = '';
                    this.newHardware.hardwareId = '';
                    this.newHardware.operatingSystem = '';
                } else if (value === 'Cross Platform') {
                    this.newHardware.serialNumber = '';
                    this.newHardware.iSeriesModel = '';
                    this.newHardware.featureCode = '';
                    this.newHardware.processors = null;
                    this.newHardware.pGroup = '';
                    this.featureCodeOptions = [];
                }
                break;
            // iSeries-specific fields
            case 'serialNumber':
                this.newHardware.serialNumber = value;
                break;
            case 'iSeriesModel':
                this.newHardware.iSeriesModel = value;
                // Load dependent feature code options when model changes
                this.newHardware.featureCode = ''; // Reset feature code
                if (value) {
                    this.loadFeatureCodeOptions(value);
                } else {
                    this.featureCodeOptions = [];
                }
                break;
            case 'featureCode':
                this.newHardware.featureCode = value;
                break;
            case 'processors':
                this.newHardware.processors = value ? parseFloat(value) : null;
                break;
            case 'pGroup':
                this.newHardware.pGroup = value;
                break;
            // Cross Platform-specific fields
            case 'hostname':
                this.newHardware.hostname = value;
                break;
            case 'hardwareId':
                this.newHardware.hardwareId = value;
                break;
            case 'operatingSystem':
                this.newHardware.operatingSystem = value;
                break;
            // Legacy fields
            case 'status':
                this.newHardware.status = value;
                break;
            case 'category':
                this.newHardware.category = value;
                break;
            case 'environment':
                this.newHardware.environment = value;
                break;
            case 'cpw':
                this.newHardware.cpw = value ? parseFloat(value) : null;
                break;
            case 'storage':
                this.newHardware.storage = value ? parseFloat(value) : null;
                break;
        }
    }

    /**
     * Load feature code options based on selected iSeries model
     * @param {string} modelValue - The selected model value
     */
    async loadFeatureCodeOptions(modelValue) {
        try {
            const options = await getFeatureCodeOptions({ modelValue: modelValue });
            this.featureCodeOptions = options;
        } catch (error) {
            console.error('Error loading feature code options:', error);
            this.featureCodeOptions = [];
        }
    }

    async handleCreateHardware() {
        try {
            // Validate required fields
            if (!this.newHardware.hardwareName) {
                this.showToast('Warning', 'Please enter a Hardware Name', 'warning');
                return;
            }

            if (!this.newHardware.hardwarePlatform) {
                this.showToast('Warning', 'Please select a Hardware Platform', 'warning');
                return;
            }

            if (this.isISeries) {
                // iSeries requires: Serial Number, Model Number
                if (!this.newHardware.serialNumber || !this.newHardware.iSeriesModel) {
                    this.showToast('Warning', 'Please fill in Serial Number and Model Number', 'warning');
                    return;
                }
            } else if (this.isCrossPlatform) {
                // Cross Platform requires: Hostname, Hardware ID, Operating System
                if (!this.newHardware.hostname || !this.newHardware.hardwareId || !this.newHardware.operatingSystem) {
                    this.showToast('Warning', 'Please fill in Hostname, Hardware ID, and Operating System', 'warning');
                    return;
                }
            }

            this.isLoading = true;

            // Get account ID from quote if not already loaded
            if (!this.quoteAccountId) {
                await this.loadQuoteAccount();
            }

            // Validate account ID was successfully loaded
            if (!this.quoteAccountId) {
                this.showToast('Error', 'Unable to determine Account for this Quote. Please refresh and try again.', 'error');
                this.isLoading = false;
                return;
            }

            // Build hardware data object based on platform type
            const hardwareData = {
                Hardware_Name__c: this.newHardware.hardwareName,
                Hardware_Platform__c: this.newHardware.hardwarePlatform
            };

            if (this.isISeries) {
                // iSeries-specific fields
                hardwareData.Serial_Number__c = this.newHardware.serialNumber;
                hardwareData.iSeries_Model__c = this.newHardware.iSeriesModel;
                // SC-3468 (reverted 2026-07-02): Model_Number__c is the deprecated legacy free-text
                // field; per business (German Wren) hardware now records the model via the governed
                // iSeries_Model__c / iSeries_Feature_Code__c drop-downs only, so we no longer dual-write
                // the picked value into Model_Number__c.

                if (this.newHardware.featureCode) {
                    hardwareData.iSeries_Feature_Code__c = this.newHardware.featureCode;
                }
                if (this.newHardware.processors) {
                    hardwareData.Number_of_Processors__c = this.newHardware.processors;
                }
                if (this.newHardware.pGroup) {
                    hardwareData.P_Group_List__c = this.newHardware.pGroup;
                }
            } else if (this.isCrossPlatform) {
                // Cross Platform-specific fields
                hardwareData.Hostname__c = this.newHardware.hostname;
                hardwareData.Hardware_ID__c = this.newHardware.hardwareId;
                hardwareData.Host_Operating_System__c = this.newHardware.operatingSystem;
            }

            if (this.newHardware.serverType) {
                hardwareData.Server_Type__c = this.newHardware.serverType;
            }
            if (this.newHardware.usersPerPartition != null) {
                hardwareData.Users_Per_Partition__c = this.newHardware.usersPerPartition;
            }

            // Call createHardwareRecord Apex method
            const newHardwareId = await createHardwareRecord({
                hardwareData: hardwareData,
                accountId: this.quoteAccountId
            });

            // Fetch the newly created record directly by Id (deterministic read-after-write).
            // Previously this re-ran searchHardware (WHERE Account__c=... ORDER BY Hardware_ID__c LIMIT 200)
            // and did .find(); on accounts with >200 Hardware rows the new record fell outside that 200-row
            // window, so .find() returned undefined and the record was silently dropped (SC-3423). Querying
            // by Id is O(1) and immune to the LIMIT/ORDER BY/NULLS-FIRST window and to any cacheable staleness.
            const createdHardware = await getHardwareById({ hardwareId: newHardwareId });

            if (createdHardware) {
                this.selectedHardware = this.decorateModel(createdHardware);
                this.hardwareRecords = [this.decorateModel(createdHardware)];
                // Set flag to hide Available Hardware section and show only Selected Hardware
                this.hardwareCreatedAndSelected = true;
                // Fetch hardware attributes for the newly created hardware
                await this.fetchHardwareAttributes(createdHardware.Id);

                this.showToast('Success', 'Hardware created and selected successfully', 'success');
                this.showCreateHardware = false;
            } else {
                // The record was created but could not be retrieved for selection. Do NOT report
                // success: surface a clear, actionable message and keep the create form open so the
                // failure is never silent (the unconditional success toast was the SC-3423 masking bug).
                this.showToast(
                    'Warning',
                    'Hardware was created but could not be selected automatically. Please use Search Hardware to locate and select it.',
                    'warning'
                );
            }

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to create hardware', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ========== Group Operations ==========
    async handleGroupSelection(event) {
        const selectedRows = event.detail.selectedRows;
        if (selectedRows.length > 0) {
            this.selectedGroup = selectedRows[0];

            // Pre-populate form fields for edit mode
            if (this.currentMode === 'edit') {
                // Check if hardware is assigned and has non-Quoting status (edit restriction)
                const hardwareStatus = this.selectedGroup.Hardware__r?.Status__c;
                if (this.selectedGroup.Hardware__c && hardwareStatus && hardwareStatus !== 'Quoting') {
                    this.showToast(
                        'Edit Restricted',
                        'Hardware with owned products cannot be edited. Only hardware in "Quoting" status can be modified.',
                        'warning'
                    );
                    // Clear the selection to prevent proceeding
                    this.selectedGroup = null;
                    return;
                }

                this.groupName = this.selectedGroup.Name;
                this.hardwareNotes = this.selectedGroup.Hardware_Notes__c || '';
                this.selectedHardware = this.selectedGroup.Hardware__c ? {
                    Id: this.selectedGroup.Hardware__c,
                    Hardware_ID__c: this.selectedGroup.Hardware__r?.Hardware_ID__c,
                    Model_Number__c: this.selectedGroup.Hardware__r?.Model_Number__c,
                    iSeries_Model__c: this.selectedGroup.Hardware__r?.iSeries_Model__c,
                    // SC-3468: iSeries code preferred, free-text Model_Number__c fallback
                    modelDisplay: (this.selectedGroup.Hardware__r?.iSeries_Model__c
                        || this.selectedGroup.Hardware__r?.Model_Number__c || ''),
                    Status__c: this.selectedGroup.Hardware__r?.Status__c,
                    // Include hardware attribute fields from the related Hardware__c record
                    P_Group_List__c: this.selectedGroup.Hardware__r?.P_Group_List__c,
                    Server_Type__c: this.selectedGroup.Hardware__r?.Server_Type__c,
                    Users_Per_Partition__c: this.selectedGroup.Hardware__r?.Users_Per_Partition__c
                } : null;

                // Fetch hardware attributes if hardware is assigned
                if (this.selectedHardware) {
                    await this.fetchHardwareAttributes(this.selectedHardware.Id);
                } else {
                    this.hardwareAttributes = null;
                }
            }
        }
    }

    async handleCreateGroup() {
        // Final duplicate name check before server call
        if (this.isGroupNameDuplicate(this.groupName)) {
            this.showToast('Error', 'A group with this name already exists on this quote.', 'error');
            this.validateGroupName();
            return;
        }

        try {
            this.isLoading = true;

            const groupId = await createHardwareGroup({
                quoteId: this.recordId,
                groupName: this.groupName,
                notes: this.hardwareNotes,
                hardwareId: this.selectedHardware?.Id
            });

            this.showToast('Success', 'Hardware group created successfully', 'success');

            // Dispatch success event for parent component
            this.dispatchEvent(new CustomEvent('success'));

            this.handleClose();

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to create group', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleUpdateGroup() {
        // Final duplicate name check before server call
        if (this.isGroupNameDuplicate(this.groupName)) {
            this.showToast('Error', 'A group with this name already exists on this quote.', 'error');
            this.validateGroupName();
            return;
        }

        try {
            this.isLoading = true;

            await updateHardwareGroup({
                groupId: this.selectedGroup.Id,
                groupName: this.groupName,
                notes: this.hardwareNotes,
                hardwareId: this.selectedHardware?.Id
            });

            this.showToast('Success', 'Hardware group updated successfully', 'success');

            // Dispatch success event for parent component
            this.dispatchEvent(new CustomEvent('success'));

            this.handleClose();

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to update group', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleAssignHardware() {
        try {
            this.isLoading = true;

            await assignHardwareToGroup({
                groupId: this.selectedGroup.Id,
                hardwareId: this.selectedHardware.Id
            });

            this.showToast('Success', 'Hardware assigned to group successfully', 'success');

            // Dispatch success event for parent component
            this.dispatchEvent(new CustomEvent('success'));

            this.handleClose();

        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to assign hardware', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ========== Form Handlers ==========
    handleGroupNameChange(event) {
        this.groupName = event.detail.value;
        this.validateGroupName();
    }

    handleHardwareNotesChange(event) {
        this.hardwareNotes = event.detail.value;
    }

    handleAssignHardwareNowChange(event) {
        this.assignHardwareNow = event.detail.checked;

        // For Edit mode, load hardware when checkbox is checked
        if (this.assignHardwareNow && this.currentMode === 'edit') {
            this.loadUnassignedHardware();
        }
    }

    // ========== Navigation ==========
    handleNext() {
        if (this.currentMode === 'create' && this.currentStep === 'configure-group') {
            // Create mode: Move from configure-group to hardware-selection (if checkbox checked)
            if (this.assignHardwareNow) {
                this.showGroupConfig = false;
                this.showHardwareSearch = true;
                this.currentStep = 'hardware-selection';
                // Load unassigned hardware when entering hardware selection
                this.loadUnassignedHardware();
            } else {
                // Skip hardware selection, go directly to finish
                this.handleFinish();
            }
        } else if (this.currentMode === 'edit' && this.showGroupSelection && this.selectedGroup) {
            // Move from group selection to edit form
            this.showGroupSelection = false;
            this.showGroupConfig = true;
            this.currentStep = 'configure-group';
        } else if (this.currentMode === 'assign' && this.showHardwareSearch && this.selectedHardware) {
            // New workflow: Move from hardware selection to group selection
            this.showHardwareSearch = false;
            this.showGroupSelection = true;
            this.currentStep = 'select-group';
        }
    }

    handleBack() {
        if (this.currentStep === 'hardware-selection' && this.currentMode === 'create') {
            // Create mode: Go back from hardware-selection to configure-group
            this.showHardwareSearch = false;
            this.showGroupConfig = true;
            this.currentStep = 'configure-group';
            this.selectedHardware = null;
            this.hardwareAttributes = null;
            this.hardwareRecords = [];
        } else if (this.currentStep === 'configure-group' && this.currentMode === 'create') {
            // Create mode: Go back to mode selection
            this.showGroupConfig = false;
            this.showModeSelection = true;
            this.currentStep = 'mode-selection';
            this.currentMode = null;
            this.groupName = '';
            this.hardwareNotes = '';
            this.assignHardwareNow = false;
        } else if (this.currentStep === 'configure-group' && this.currentMode === 'edit') {
            // Edit mode: Go back to group selection
            this.showGroupConfig = false;
            this.showGroupSelection = true;
            this.currentStep = 'select-group';
            this.selectedGroup = null;
        } else if (this.currentStep === 'select-hardware' && this.currentMode === 'assign') {
            // Assign mode: Go back to mode selection (hardware is the first screen)
            this.showHardwareSearch = false;
            this.showModeSelection = true;
            this.currentStep = 'mode-selection';
            this.currentMode = null;
            this.selectedHardware = null;
            this.hardwareAttributes = null;
        } else if (this.currentStep === 'select-group') {
            if (this.currentMode === 'assign') {
                // Assign mode: Go back to hardware selection
                this.showGroupSelection = false;
                this.showHardwareSearch = true;
                this.currentStep = 'select-hardware';
                this.selectedGroup = null;
            } else {
                // Edit mode: Go back to mode selection
                this.showGroupSelection = false;
                this.showModeSelection = true;
                this.currentStep = 'mode-selection';
                this.currentMode = null;
            }
        }
    }

    handleFinish() {
        if (this.currentMode === 'create') {
            this.handleCreateGroup();
        } else if (this.currentMode === 'edit') {
            this.handleUpdateGroup();
        } else if (this.currentMode === 'assign') {
            this.handleAssignHardware();
        }
    }

    handleCancel() {
        // Dispatch cancel event for parent component
        this.dispatchEvent(new CustomEvent('cancel'));

        // Also handle close for Quick Action context
        this.handleClose();
    }

    handleClose() {
        // Refresh the quote page data
        if (this.wiredGroupsResult) {
            refreshApex(this.wiredGroupsResult);
        }

        // Close the modal (for Quick Action context)
        // Use try-catch since CloseActionScreenEvent only works in Quick Action context
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            console.log('CloseActionScreenEvent not available in this context');
        }

        // Refresh the quote view using NavigationMixin
        // Note: The parent component should handle the success event to refresh
        // This legacy Aura event approach is removed as it doesn't work in LWC
    }

    // ========== Utility Methods ==========

    /**
     * Check if a group name already exists on this quote (case-insensitive)
     * @param {string} name - The group name to check
     * @returns {boolean} true if duplicate exists
     */
    isGroupNameDuplicate(name) {
        if (!name || !this.existingGroups || this.existingGroups.length === 0) {
            return false;
        }
        const normalizedName = name.trim().toLowerCase();
        return this.existingGroups.some(group => {
            // In edit mode, exclude the currently selected group
            if (this.currentMode === 'edit' && this.selectedGroup && group.Id === this.selectedGroup.Id) {
                return false;
            }
            return group.Name && group.Name.trim().toLowerCase() === normalizedName;
        });
    }

    /**
     * Validate the group name input and show/clear inline error
     */
    validateGroupName() {
        const input = this.template.querySelector('lightning-input[data-id="groupNameInput"]');
        if (!input) return;

        if (this.isGroupNameDuplicate(this.groupName)) {
            input.setCustomValidity('A group with this name already exists on this quote.');
        } else {
            input.setCustomValidity('');
        }
        input.reportValidity();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}