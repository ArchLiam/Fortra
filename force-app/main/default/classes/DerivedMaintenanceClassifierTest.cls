/**
 * @description Unit tests for DerivedMaintenanceClassifier, verifying detection of
 *              derived maintenance product types and new-business maintenance lines.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class DerivedMaintenanceClassifierTest {

    /**
     * @description Verifies that isDerivedMaintenanceProductType returns true for
     *              New and Renewal Maintenance types and false for other types and null.
     */
    @IsTest
    static void isDerivedMaintenanceProductType_matchesNewAndRenewalMaintenance() {
        System.assertEquals(true, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('New Maintenance'));
        System.assertEquals(true, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('Renewal Maintenance'));
        System.assertEquals(false, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('Perpetual'));
        System.assertEquals(false, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType(null));
    }

    /**
     * @description Verifies that isNewBusinessDerivedMaintenance returns true only for
     *              New Maintenance on non-renewal quotes whose line is not already handled
     *              by the renewal-COLA path, and false otherwise.
     */
    @IsTest
    static void isNewBusinessDerivedMaintenance_onlyNewMaintOnNonRenewalNotAlreadyColaHandled() {
        Id lineId = '0QLWC000000000AAAA';
        Map<Id, QuoteLineItem> colaLines = new Map<Id, QuoteLineItem>{ lineId => new QuoteLineItem(Id = lineId) };

        // New Maintenance, non-renewal, not a COLA line -> true
        System.assertEquals(true, DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(
            'New Maintenance', false, '0QLWC000000001AAAA', colaLines));
        // Renewal quote -> false
        System.assertEquals(false, DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(
            'New Maintenance', true, '0QLWC000000001AAAA', colaLines));
        // Not New Maintenance -> false
        System.assertEquals(false, DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(
            'Renewal Maintenance', false, '0QLWC000000001AAAA', colaLines));
        // Already handled by the renewal-COLA path (line is in the map) -> false
        System.assertEquals(false, DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(
            'New Maintenance', false, lineId, colaLines));
        // Null map / null line -> still true (nothing excludes it)
        System.assertEquals(true, DerivedMaintenanceClassifier.isNewBusinessDerivedMaintenance(
            'New Maintenance', false, null, null));
    }
}