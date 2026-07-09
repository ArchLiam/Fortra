/**
 * D-18 — PricingHookLogger end-to-end.
 * A swallowed pricing-hook exception routed through the logger publishes a
 * Pricing_Exception__e that the subscriber Flow persists to Exception_Log__c with
 * the right Source / Hook_Phase / Severity. Also covers the null-exception path.
 */
@IsTest
private class PricingHookLoggerTest {

    @IsTest
    static void logPosthook_persistsWithPhaseAndSource() {
        Test.startTest();
        PricingHookLogger.logPosthook(
            'PartnerNetPricePosthook',
            '0Q0XXXXXXXXXXXXXXX',
            new PricingException('boom')
        );
        Test.stopTest();

        List<Exception_Log__c> logs = [
            SELECT Source__c, Hook_Phase__c, Severity__c, Exception_Type__c, Message__c, Context_Id__c
            FROM Exception_Log__c
            WHERE Source__c = 'PartnerNetPricePosthook'
        ];
        System.assertEquals(1, logs.size(), 'One posthook degrade should be logged.');
        System.assertEquals('Posthook', logs[0].Hook_Phase__c, 'Phase should be Posthook.');
        System.assertEquals('Error', logs[0].Severity__c, 'Severity should be Error.');
        System.assertEquals('0Q0XXXXXXXXXXXXXXX', logs[0].Context_Id__c, 'Context id should carry through.');
        System.assert(logs[0].Message__c != null && logs[0].Message__c.contains('boom'),
            'Message should carry the exception text.');
    }

    @IsTest
    static void logPrehook_nullException_stillPublishes() {
        Test.startTest();
        PricingHookLogger.logPrehook('COLAUpliftPrehook', null, null);
        Test.stopTest();

        List<Exception_Log__c> logs = [
            SELECT Source__c, Hook_Phase__c, Exception_Type__c
            FROM Exception_Log__c
            WHERE Source__c = 'COLAUpliftPrehook'
        ];
        System.assertEquals(1, logs.size(), 'A null exception must still log a degrade row.');
        System.assertEquals('Prehook', logs[0].Hook_Phase__c, 'Phase should be Prehook.');
        System.assertEquals(null, logs[0].Exception_Type__c, 'Null exception → null type.');
    }
}
