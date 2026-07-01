//
// BSSOrderInfoRestServiceTest
//
// Coverage tests for BSSOrderInfoRestService which returns Order info
// (mainly hardware) to supplement Workday invoices.
//
// Changes:
// 2026-05-05 Keith Irwin: [BSS-28212] Initial implementation.
// 2026-06-03 Keith Irwin: [BSS-28998] Validation updates for V2
//

@IsTest(seeAllData=false)
public without sharing class BSSOrderInfoRestServiceTest {

    @TestSetup
    static void setup() {
        loadData();
    }

    @IsTest
    static void testBasicRequest() {
        Order order = [select OrderNumber from Order limit 1];
        String orderNumber = order.OrderNumber;
        System.assert(orderNumber != null, 'We can find the order number.');
        RestResponse response = new RestResponse();
        RestRequest request = new RestRequest();

        request.requestURI = '/services/apexrest/OrderInfo/order/' + orderNumber;
        request.httpMethod = 'GET';

        RestContext.request = request;
        RestContext.response = response;

        BSSOrderInfoRestService.doGet();

        Assert.isTrue(response.statusCode == 200, '200 status when successfull');

        String doc = response.responseBody.toString();
        try {
            BSSOrderInfoRestService.OrderInfo info =
                (BSSOrderInfoRestService.OrderInfo)JSON.deserialize(
                        doc,
                        BSSOrderInfoRestService.OrderInfo.class
                    );
        } catch (Exception e) {
            Assert.fail('Response Body should match OrderInfo spec');
        }
    }

    @IsTest
    static void testNotFound() {
        RestResponse response = new RestResponse();
        RestRequest request = new RestRequest();

        request.requestURI = '/services/apexrest/OrderInfo/order/ababab';
        request.httpMethod = 'GET';

        RestContext.request = request;
        RestContext.response = response;

        BSSOrderInfoRestService.doGet();

        Assert.isTrue(404 == response.statusCode, '404 status when not found.');
    }

    @IsTest
    static void testBadRequest() {
        RestResponse response = new RestResponse();
        RestRequest request = new RestRequest();

        request.requestURI = '/services/apexrest/OrderInfo/lalala/ababab';
        request.httpMethod = 'GET';

        RestContext.request = request;
        RestContext.response = response;

        BSSOrderInfoRestService.doGet();

        Assert.isTrue(400 == response.statusCode, '400 status when bad request');
    }

    // Fixtures

    private static String SERIAL = 'SN-2b696faa-a8d7';

    private static void loadData() {
        Account account = new Account(name = 'Test Account');
        insert account;
        Hardware__c hw = new Hardware__c(
            Account__c = account.Id,
            Serial_Number__c = SERIAL
        );
        insert hw;

        Id pricebookId = Test.getStandardPricebookId();

        Product2 product = new Product2(
            name = 'Test Product',
            IsActive = true,
            QuantityUnitOfMeasure = 'Each'
        );
        insert product;

        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 199.99,
            IsActive = true
        );
        insert entry;

        Opportunity opportunity = new Opportunity(
            Name = 'Test',
            StageName = 'Evaluating',
            Pricebook2Id = pricebookId,
            AccountId = account.Id,
            CloseDate = Date.today().addDays(100)
        );
        insert opportunity;

        Quote quote = new Quote(
            Name = 'Test',
            OpportunityId = opportunity.Id,
            Pricebook2Id = pricebookId,
            CurrencyIsoCode = 'USD',
            Status = 'Accepted'
        );
        insert quote;

        OrderValidationTriggerHandler.bypassValidation = true;
        Order order = new Order(
            AccountId = account.Id,
            QuoteId = quote.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = pricebookId
        );
        insert order;

        OrderItem item = new OrderItem(
            OrderId = order.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            UnitPrice = 199.99,
            Hardware_ID__c = hw.Id
        );
        insert item;
    }
}