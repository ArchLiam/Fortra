@IsTest
private class DerivedMaintenanceClassifierTest {

    @IsTest
    static void isDerivedMaintenanceProductType_matchesNewAndRenewalMaintenance() {
        System.assertEquals(true, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('New Maintenance'));
        System.assertEquals(true, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('Renewal Maintenance'));
        System.assertEquals(false, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType('Perpetual'));
        System.assertEquals(false, DerivedMaintenanceClassifier.isDerivedMaintenanceProductType(null));
    }

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
