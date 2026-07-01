//
// BSIInvoicePaymentLinkControllerTest
//
// Test coverage for the InterPayments payment link forwarder
// controller.
//
// Changes:
// 2025-11-20 Keith Irwin: [BSS-24692] Initial implementation
//

@IsTest (seeAllData=false)
public class BSIInvoicePaymentLinkControllerTest {

    @TestSetup
    static void setup() {
        loadData();
    }

    @IsTest
    static void testBasic() {
        PageReference page = Page.pay_invoice;
        page.getParameters().put('id', TEST_GUID);
        Test.setCurrentPage(page);
        Test.setMock(HttpCalloutMock.class, new InterPaymentMock());

        Test.startTest();
        BSIInvoicePaymentLinkController controller = new BSIInvoicePaymentLinkController();
        PageReference link = controller.goToPaymentLink();
        Test.stopTest();

        System.assert(link != null, 'Null redirect link');
        System.assert(link.getUrl() == TEST_LINK, 'Link missing url.');
        System.assert(link.getRedirect(), 'Link not set to redirect.');
    }

    @IsTest
    static void testBadAuth() {
        PageReference page = Page.pay_invoice;
        page.getParameters().put('id', TEST_GUID);
        Test.setCurrentPage(page);
        Test.setMock(HttpCalloutMock.class, new InterPaymentBadAuth());

        Test.startTest();
        BSIInvoicePaymentLinkController controller = new BSIInvoicePaymentLinkController();
        PageReference link = controller.goToPaymentLink();
        Test.stopTest();

        System.assert(link == null, 'Non-null redirect link.');
        System.assert(!String.isBlank(controller.debug), 'No error message.');
    }

    @IsTest
    static void testBadAPI() {
        PageReference page = Page.pay_invoice;
        page.getParameters().put('id', TEST_GUID);
        Test.setCurrentPage(page);
        Test.setMock(HttpCalloutMock.class, new InterPaymentBadAPI());

        Test.startTest();
        BSIInvoicePaymentLinkController controller = new BSIInvoicePaymentLinkController();
        PageReference link = controller.goToPaymentLink();
        Test.stopTest();

        System.assert(link == null, 'Non-null redirect link.');
        System.assert(!String.isBlank(controller.debug), 'No error message.');
    }

    @IsTest
    static void testNoId() {
        Test.setMock(HttpCalloutMock.class, new InterPaymentMock());
        Test.startTest();
        BSIInvoicePaymentLinkController controller = new BSIInvoicePaymentLinkController();
        PageReference link = controller.goToPaymentLink();

        System.assert(link == null, 'No token should return null page ref.');
        System.assert(!String.isBlank(controller.debug), 'Emtpy debug message.');
        Test.stopTest();
    }

    @IsTest
    static void testBadId() {
        PageReference page = Page.pay_invoice;
        page.getParameters().put('id', 'BAD' + TEST_GUID);
        Test.setCurrentPage(page);
        Test.setMock(HttpCalloutMock.class, new InterPaymentMock());
        Test.startTest();

        BSIInvoicePaymentLinkController controller = new BSIInvoicePaymentLinkController();
        PageReference link = controller.goToPaymentLink();
        System.assert(link == null, 'No token should return null page ref.');
        System.assert(!String.isBlank(controller.debug), 'Emtpy debug message.');
        Test.stopTest();
    }

    // Test Fixtures

    private static String TEST_GUID = '85fd709d-45dd-4ec4-9275-b8a931a5ee0f';
    private static String TEST_LINK = 'https://example.com/ef0f81ad-f7ff-43d9-8c89-5cb1597e90bb';

    private static void loadData() {
        Account account = new Account (
            Name = 'Test Account'
        );
        insert account;

        Order order = new Order (
            AccountId = account.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft'
        );
        insert order;

        Workday_Invoice__c invoice = new Workday_Invoice__c (
            Name = 'INV-00000001',
            Amount_Due__c = 456.78,
            Payment_URL__c = 'https://example.com?id=' + TEST_GUID,
            order__c = order.Id
        );
        insert invoice;
    }

    private class MockException extends Exception {}

    public class InterPaymentBadAuth implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(403);
            return response;
        }
    }

    public class InterPaymentBadAPI implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request.getEndpoint();

            if (endpoint.endsWith('/oauth/token')) {
                response.setStatusCode(200);
                response.setBody('{ "access_token" : "123", "expires_in" : 86400 }');
                return response;
            }

            response.setStatusCode(404);
            response.setBody('{"error" : "error"}');
            return response;
        }
    }

    public class InterPaymentMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request.getEndpoint();

            if (endpoint.endsWith('/oauth/token')) {
                response.setStatusCode(200);
                response.setBody('{ "access_token" : "123", "expires_in" : 86400 }');
                return response;
            }

            if (endpoint.endsWith('v2/payment-links')) {
                response.setStatusCode(201);
                response.setBody('{ "paymentLink" : { "url" : "' + TEST_LINK + '" }}');
                return response;
            }

            throw new MockException('The test mock exception did not properly mock.');
        }
    }
}