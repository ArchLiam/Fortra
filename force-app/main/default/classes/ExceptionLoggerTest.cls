/**
 * D-18 — ExceptionLogger contract + end-to-end delivery.
 * Verifies safePublish never throws on a null event, and that a valid
 * Pricing_Exception__e published in a test is delivered to the subscriber Flow
 * (which persists an Exception_Log__c row) after Test.stopTest().
 */
@IsTest
private class ExceptionLoggerTest {

    @IsTest
    static void safePublish_nullEvent_isNoOp() {
        Test.startTest();
        ExceptionLogger.safePublish(null); // must not throw
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Exception_Log__c],
            'A null event must publish nothing and create no log row.');
    }

    @IsTest
    static void safePublish_validEvent_persistsViaSubscriber() {
        Test.startTest();
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c     = 'ExceptionLoggerTest',
            Hook_Phase__c = 'Prehook',
            Severity__c   = 'Error',
            Message__c    = 'unit-test'
        ));
        Test.stopTest(); // delivers the platform event to the subscriber Flow

        List<Exception_Log__c> logs = [
            SELECT Id, Source__c, Hook_Phase__c, Severity__c, Message__c
            FROM Exception_Log__c
            WHERE Source__c = 'ExceptionLoggerTest'
        ];
        System.assertEquals(1, logs.size(),
            'The subscriber Flow should persist exactly one Exception_Log__c row.');
        System.assertEquals('Prehook', logs[0].Hook_Phase__c, 'Hook phase should carry through.');
        System.assertEquals('Error', logs[0].Severity__c, 'Severity should carry through.');
    }
}
