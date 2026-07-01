//
//
//

@IsTest(seeAllData=false)
public with sharing class GsLicensingControllerTest {

    @TestSetup
    static void setup() {
        loadData();
    }

    @IsTest
    static void testBasic() {
        CapturingMock mock = new CapturingMock(Callout.SUCCEED);
        Order order = [select Id, OrderNumber, AccountId from Order where PONumber = :TEST_PO limit 1];

        Test.setMock(HttpCalloutMock.class, mock);

        // This test is mainly to see if the Order data makes it into the
        // callout send to the GS Licensing service. It does not test if
        // the service itself works because it doesn't do anything other
        // then report failures to the user.

        Test.startTest();
        String result = GsLicensingController.processOrder(order.Id);
        Test.stopTest();

        // I'll let this stand in until I see the actual message.
        System.assert(result.contains('success'), 'Failed to parse JSON result: ' + result);

        // Test user. We don't care who it is.
        System.assert(!String.isBlank(mock.request.getHeader('Gsusername')), 'username header is missing');
        System.assert(!String.isBlank(mock.request.getHeader('Gsname')), 'name header is missing');

        System.assert(mock.request.getHeader('GsBillToAccountID') == order.AccountId, 'Missing bill-to');
        System.assert(mock.request.getHeader('GsShipToAccountID') == order.AccountId, 'Missing ship-to');
        System.assert(mock.request.getBody().contains(order.OrderNumber), 'Missing order number');
    }

    @IsTest
    static void testBadOrderId() {
        Test.startTest();
        String result = GsLicensingController.processOrder('44933ef8-e58a-4c57-b297-9bf8bef953d1');
        Test.stopTest();

        System.assert(result.startsWithIgnoreCase('error'), 'No error message: [' + result + ']');
    }

    @IsTest
    static void testInvalidRequestError() {
        Order order = [select Id from Order where PONumber = :TEST_PO limit 1];

        CapturingMock mock = new CapturingMock(Callout.INVALID);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = GsLicensingController.processOrder(order.Id);
        Test.stopTest();

        // The service returns a 200 no matter what, but if the message is
        // something other than 'success', we need to consider it an error.
        System.assert(result.startsWithIgnoreCase('error'), 'No error message: [' + result + ']');
    }

    @IsTest
    static void testServerError() {
        Order order = [select Id from Order where PONumber = :TEST_PO limit 1];

        CapturingMock mock = new CapturingMock(Callout.FAIL);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String result = GsLicensingController.processOrder(order.Id);
        Test.stopTest();

        System.assert(result.startsWithIgnoreCase('error'), 'No error message: [' + result + ']');
    }

    @IsTest
    static void testCalloutError() {
        Order order = [select Id from Order where PONumber = :TEST_PO limit 1];

        CapturingMock mock = new CapturingMock(Callout.SUCCEED);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GsLicensingController.forceCalloutError = true;
        String result = GsLicensingController.processOrder(order.Id);
        Test.stopTest();

        System.assert(result.startsWithIgnoreCase('error'), 'No error message: [' + result + ']');
    }

    // Test Fixtures

    private static String TEST_PO = 'd16fd8ad-e8ae-4d55-82fd-66dc47970b79';
    private enum Callout { SUCCEED, FAIL, INVALID }

    private static void loadData() {
        Account account = new Account (
            Name = 'Test Account',
            GS_CustomerID__c = 0
        );
        insert account;

        Order order = new Order (
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Ship_To_Account__c = account.Id,
            Bill_To_Account__c = account.Id,
            PONumber = TEST_PO
        );
        insert order;
    }

    public class CapturingMock implements HttpCalloutMock {

        public HttpRequest request;

        private Callout mode = Callout.SUCCEED;

        public CapturingMock(Callout mode) {
            this.mode = mode;
        }

        public HttpResponse respond(HttpRequest request) {
            this.request = request;

            HttpResponse response = new HttpResponse();

            switch on this.mode {
                when SUCCEED {
                    response.setStatusCode(200);
                    response.setBody('{ "message" : "success", "status" : true }');
                }
                when FAIL {
                    response.setStatusCode(500);
                    response.setBody('');
                }
                when INVALID {
                    response.setStatusCode(200);
                    response.setBody('{ "message" : "Bill To should have state/country", "status" : false }');
                }
            }
            return response;
        }
    }
}