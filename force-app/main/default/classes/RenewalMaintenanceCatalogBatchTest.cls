/**
 * @description Verifies that RenewalMaintenanceCatalogProvisionBatch, run in dry-run mode over the live
 *              catalog, projects work without writing a single ProductSellingModelOption or
 *              PricebookEntry. The commit path (idempotent additive inserts) is validated as a UAT
 *              integration run — a full data-built catalog (Product2 + ProductSellingModel +
 *              PricebookEntry across two books) is impractical to assemble in a unit context.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest(SeeAllData=true)
private class RenewalMaintenanceCatalogBatchTest {

    /**
     * @description A dry-run batch reads the catalog and stages projections but performs no DML.
     */
    @isTest
    static void dryRunProjectsWithoutDml() {
        Integer psmoBefore = [SELECT COUNT() FROM ProductSellingModelOption];
        Integer pbeBefore = [SELECT COUNT() FROM PricebookEntry];

        Test.startTest();
        Database.executeBatch(new RenewalMaintenanceCatalogProvisionBatch(true), 50);
        Test.stopTest();

        Assert.areEqual(psmoBefore, [SELECT COUNT() FROM ProductSellingModelOption],
            'dry-run must not insert any ProductSellingModelOption');
        Assert.areEqual(pbeBefore, [SELECT COUNT() FROM PricebookEntry],
            'dry-run must not insert any PricebookEntry');
    }
}
