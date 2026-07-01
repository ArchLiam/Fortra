//
// GsLicensingController
//
// Backs an LWC Quick Action folks can run on an Order that will ask
// Globalscape infrastructure to ... generate serial numbers or ...
// licenses. Note: We might convert this to an Invocable
// Action run from a flow. Or it might work for both.
//
// Changes:
// 2026-03-12 Keith Irwin [BSS-26894]: Initial implementation.
//

public without sharing class GsLicensingController {

    @AuraEnabled
    public static String processOrder(String orderId) {
        try {
            OrderInfo info = getOrder(orderId);
            return sendToGlobalscape(info);
        } catch (Exception e) {
            return 'ERROR 1: ' + e.getMessage();
        }
    }

    @TestVisible
    private static Boolean forceCalloutError = false;
    private class TestException extends Exception {}

    private static String sendToGlobalscape(OrderInfo info) {
        try {

            if (forceCalloutError) {
                throw new TestException('exception');
            }

            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint('callout:GS_License_Gen_API');
            request.setHeader('Gsusername', info.username);
            request.setHeader('Gsname', info.name);
            request.setHeader('GsBillToAccountID', info.billingAccountId);
            request.setHeader('GsShipToAccountID', info.shippingAccountId);
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            request.setBody(info.body);
            request.setTimeout(120000);

            Http http = new Http();
            HTTPResponse response = http.send(request);

            Integer code = response.getStatusCode();
            String status = response.getStatus();
            String body = response.getBody();

            ServiceResponse gsResponse = unpack(body) ?? new ServiceResponse('Unable to parse response:' + body);

            String message = code + ' | ' + status + ' | ' + gsResponse.cleanMessage;
            if (code >= 300) {
                return 'ERROR 3: ' + message + ', ' + info;
            } else if (gsResponse.status == false) {
                return 'ERROR 4: [' + message + '], ' + info;
            } else {
                return gsResponse.cleanMessage + ' → [' + info + '] → [' + body + ']';
            }
        } catch (Exception e) {
            return 'ERROR 2: ' + e;
        }
    }

    // In all cases, the Globalscape Service will return a 200 with a simple
    // response. If the status = false, that message the message indicates an
    // issue the service had attempting to fulfill the request.

    public class ServiceResponse {
        public String message = '';
        public Boolean status = true;

        public String cleanMessage {
            get {
                return (this.message ?? '').trim();
            }
        }

        public ServiceResponse(String message) {
            this.message = message;
            this.status = false;
        }
    }

    private static ServiceResponse unpack(String xml) {
        try {
            ServiceResponse response = (ServiceResponse)JSON.deserialize(xml, ServiceResponse.class);
            return response;
        } catch (Exception e) {
            return null;
        }
    }

    private static OrderInfo getOrder(String id) {
        Order order = [
            select
                Id, Name, Account_NameText__c, Ship_To_Account__c,
                Bill_To_Account__c, Account.GS_CustomerID__c,
                gsOrderID__c, gsShipDate__c, OrderNumber
            from Order
            where id = :id
            limit 1
        ];
        return new OrderInfo(order);
    }

    public class OrderInfo {
        public String username;
        public String name;
        public String orderNumber;
        public String billingAccountId;
        public String shippingAccountId;
        public String customerId;
        public String body;

        public OrderInfo(Order order) {
            this.username = UserInfo.getUserName();
            this.name = UserInfo.getName();
            this.orderNumber = order.OrderNumber;
            this.billingAccountId = String.valueOf(order.Bill_To_Account__c) ?? 'missing';
            this.shippingAccountId = String.valueOf(order.Ship_To_Account__c) ?? 'missing';
            this.customerId = String.valueOf(order.Account.GS_CustomerID__c ?? 0);

            this.body = 'ordernumber=' + this.orderNumber + '&' +
                'customerid=' + this.customerId;
        }
    }
}