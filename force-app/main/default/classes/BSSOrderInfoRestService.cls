//
// BSSOrderInfoRestService
//
// REST endpoint. Caller provides Order Number, service returns discount,
// billing and hardware info about the order and its items.
//
// Changes:
// 2026-05-01 Keith Irwin: [BSS-28212] Initial implementation.
// 2026-06-03 Keith Irwin: [BSS-28998] V3: Id and DiscountAmount on Item.
// 2026-06-04 Keith Irwin: [BSS-28998] V4: VAT Number, renames, nulls not blanks.
//

@RestResource(urlMapping='/OrderInfo/*')
global without sharing class BSSOrderInfoRestService {

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            res.addHeader('Content-Type', 'application/json');

            String path = req.requestURI;
            String params = path.substringAfter('/OrderInfo/');
            List<String> parts = params.split('/');

            if (parts.size() < 2) {
                throw new BadRequestException('Unabled to parse `order/{id}`: ' + path);
            }

            String resource = parts[0].toLowerCase().trim();
            String identifier = parts[1].trim();

            if (resource != 'order') {
                throw new BadRequestException('Unsupported resource: ' + resource);
            }

            OrderInfo info = getOrderInfo(identifier);
            String doc = info.toJSON();

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(doc);

        } catch (NotFoundException e) {
            res.statusCode = 404;
            res.responseBody = genError('404', e);
        } catch (BadRequestException e) {
            res.statusCode = 400;
            res.responseBody = genError('400', e);
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = genError('500', e);
        }
    }

    private class ServiceException extends Exception {}
    private class BadRequestException extends Exception {}
    private class NotFoundException extends Exception {}

    private static Blob genError(String status, Exception e) {

        // Turn an exception into a JSON doc we can return with
        // a non-200 HTTP status code.

        String message = '' + e; // .getMessage();
        ErrorInfo error = new ErrorInfo(status, message);
        String doc = JSON.serialize(error);
        return Blob.valueOf(doc);
    }

    private static OrderInfo getOrderInfo(String orderNumber) {

        // Query some info on the Order with the specified `orderNumber`
        // mainly to provide additional context in case it's helpful
        // for debugging.

        List<Order> orders = [
            select
                Id,
                OrderNumber,
                ShowHide_Discounts__c,
                Bill_To_Address__r.Composite_Address_Key__c,
                Bill_To_Account__r.VAT_Number__c,
                BillToContact.Business_Entity_Contact_ID__c
            from
                Order
            where
                OrderNumber = :orderNumber
            limit 1];

        if (orders.size() == 0) {
            throw new NotFoundException('Order Number ' + orderNumber + ' not found.');
        }

        List<OrderItem> items = [
            select
                Id,
                DiscountAmount,
                Hardware_ID__r.Hardware_ID__c,
                Hardware_ID__r.Hardware_Platform__c,
                LPAR_Number__c,
                LPAR_System_Name__c,
                Hardware_ID__r.Model_Number__c,
                MSP_End_User__r.Workday_Worday_ID__c,
                Hardware_ID__r.Number_of_Processors__c,
                Hardware_ID__r.Serial_Number__c,
                Hardware_ID__r.Server_Type__c,
                Hardware_ID__r.Feature_Code__c,
                Hardware_ID__c
            from
                OrderItem
            where
                Order.OrderNumber = :orderNumber
                and Hardware_ID__c not in (null, '')
        ];

        return new OrderInfo(orders.get(0), items);
    }

    global class ErrorInfo {

        // Represents an error in the event we can't fulfill the request.

        public String status;
        public String error;

        public ErrorInfo(String status, String message) {
            this.status = status;
            this.error = message;
        }
    }

    global class OrderInfo {

        // Represents an Order, for converting in to JSON.

        public String orderId;
        public String orderNumber;
        public String billToAddressId;
        public String billToContactId;
        public String vatNumber;
        public String discountVisibilty;
        public Boolean showDiscount;
        public Integer hardwareItemsCount;

        List<OrderInfoItem> hardwareItems;

        public OrderInfo(Order order, List<OrderItem> items) {
            this.orderId = order.Id;
            this.orderNumber = Order.OrderNumber;
            this.billToAddressId = Order.Bill_To_Address__r.Composite_Address_Key__c;
            this.billToContactId = Order.BillToContact.Business_Entity_Contact_ID__c;
            this.vatNumber = Order.Bill_To_Account__r.VAT_Number__c;
            this.showDiscount = Order.ShowHide_Discounts__c == 'Show';
            this.discountVisibilty = this.showDiscount ? 'discountShows' : 'discountDoesnTShow';

            this.hardwareItems = new List<OrderInfoItem>();
            for (OrderItem item : items) {
                this.hardwareItems.add(new OrderInfoItem(item));
            }

            this.hardwareItemsCount = this.hardwareItems.size();
        }

        public String toJSON() {
            return JSON.serialize(this);
        }
    }

    global class OrderInfoItem {

        // Represents an OrderItem, for converting in to JSON.

        public String itemId;
        public Decimal discount;
        public String lparNumber;
        public String lparName;
        public String mspEndUser;
        public String featureCode;
        public String hardwareId;
        public String hardwareType;
        public String model;
        public Decimal processors;
        public String serialNumber;
        public String systemType;
        public String crmHardwareId;

        public OrderInfoItem(OrderItem item) {
            this.itemId = item.Id;
            this.discount = item.DiscountAmount ?? 0.0;
            this.lparNumber = item.LPAR_Number__c;
            this.lparName = item.LPAR_System_Name__c;
            this.mspEndUser = item.MSP_End_User__r?.Workday_Worday_ID__c;
            this.featureCode = item.Hardware_ID__r?.Feature_Code__c;
            this.hardwareId = item.Hardware_ID__r?.Hardware_ID__c;
            this.hardwareType = item.Hardware_ID__r?.Hardware_Platform__c;
            this.model = item.Hardware_ID__r?.Model_Number__c;
            this.processors = item.Hardware_ID__r?.Number_of_Processors__c;
            this.serialNumber = item.Hardware_ID__r?.Serial_Number__c;
            this.systemType = item.Hardware_ID__r?.Server_Type__c;
            this.crmHardwareId = item.Hardware_ID__c;
        }
    }
}