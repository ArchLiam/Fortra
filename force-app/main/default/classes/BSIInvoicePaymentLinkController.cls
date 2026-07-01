//
// BSIInvoicePaymentLinkController
//
// Controller for a page that accepts an invoice identifier
// and then redirects the user to an InterPayment page where
// they can pay that invoice for a credit card.
//
// Changes:
// 2025-11-20 Keith Irwin: [BSS-24692] Initial implementation
//

public without sharing class BSIInvoicePaymentLinkController {

    public String debug { get; set; }

    // We don't want to give away any security related info about why an error
    // occurred, so just display this with an associated number. The real info,
    // if not obvious, will be sent to the debug log.

    private static String stockError = 'Unable to access the invoice payment system at this time.';

    // From custom metadata.

    private Settings settings;

    public BSIInvoicePaymentLinkController() {
    }

    public PageReference goToPaymentLink() {

        try {

            String token = this.getParameter('id');
            if (token == null) {
                throw new FinderException('ERROR 200: Invalid payment URL.');
            }

            InvoiceInfo invoice = this.findInvoice(token);
            if (invoice == null) {
                System.debug('ERROR 201: Unable to retrieve invoice for [' + token + ']');
                throw new FinderException('ERROR 201: Unable to retrieve invoice.');
            }

            this.settings = new Settings();

            String result = this.getPaymentLink(invoice);
            PageReference link = new PageReference(result);
            link.setRedirect(true);
            return link;
        } catch (Exception e) {
            String msg = e.getMessage();
            this.debug = msg;

            // Try to intercept the Unauthorized endpoint error, which is a
            // local configuration issue. We don't want our dirty laundry
            // exposed to the Internet!

            if (msg.startsWith('Unauthorized endpoint')) {
                System.debug('ERROR 103: ' + msg);
                this.debug = 'Error 103: ' + stockError;
            }
            return null;
        }
    }

    // Queries

    private class FinderException extends Exception {}

    // A convience class representing the invoice info we want to extract
    // from the system. InterPayments needs the amount as an Integer, so
    // multiply any values by 100.

    public class InvoiceInfo {
        public String name = '';
        public Integer amount = 0;
        public Integer tax = 0;

        public InvoiceInfo(Workday_Invoice__c invoice) {
            this.name = invoice.name;
            this.amount = Integer.valueOf((invoice.Amount_Due__c ?? 0) * 100);
            this.tax = 0; // Not available in the Workday_Invoice__c table
        }
    }

    // The incoming token arrives as an ID, but the complete URL is stored
    // in the invoice table. We have to match the token as best we can. In this
    // case, find the most recent match if there's more than one.

    private InvoiceInfo findInvoice(String id) {
        String match = '%' + id;
        List<Workday_Invoice__c> invoices = [
            select Id, Name, Amount_Due__c, Payment_Url__c
            from Workday_Invoice__c
            where Payment_Url__c like :match
            order by CreatedDate desc
            limit 1
        ];

        if (invoices.isEmpty()) {
            return null;
        }

        return new InvoiceInfo(invoices.get(0));
    }

    // NETWORK

    // While the token lasts for 24 hours, let's not cache it as this page
    // isn't used all that often. Not worth the effort. If we get feedback
    // from InterPayments that we're using Client Credentials to grab a token
    // too often, this is where we can cache (using Saleforce's Cache class).

    private String authToken = '';

    private String getPaymentLink(InvoiceInfo invoice) {
        PaymentLinkRequest doc = new PaymentLinkRequest(this.settings, invoice.name, invoice.amount, invoice.tax);
        String jsonRequest = JSON.serializePretty(doc);
        //this.debug = '<pre>' + jsonRequest + '</pre>';
        String token = login();

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://' + settings.host + '/v2/payment-links');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setBody(jsonRequest);

        Http http = new Http();
        HTTPResponse res = http.send(req);
        String body = res.getBody();

        if (res.getStatusCode() != 201) {
            System.debug('ERROR 102: ' + body);
            this.debug = body;
            throw new BSINetworkException('Error 102: (' + res.getStatusCode() + ') ' + stockError);
        }

        PaymentLinkRequest result = (PaymentLinkRequest)JSON.deserialize(body, PaymentLinkRequest.class);
        return result.paymentLink.url;
    }

    // As part of the OAuth flow, we use the client ID/Secret to grap a token
    // we'll need for subsequent authorization requests.

    private String login() {
        if (!String.isEmpty(this.authToken)) {
            return this.authToken;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(this.settings.tokenPath);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        String jsonString = new OAuthRequest(this.settings.audience, this.settings.clientId, this.settings.clientSecret).toJson();
        req.setBody(jsonString);

        Http http = new Http();
        HTTPResponse res = http.send(req);
        String body = res.getBody();

        if (res.getStatusCode() != 200) {
            System.debug('ERROR 101: ' + body);
            throw new BSINetworkException('Error 101: (' + res.getStatusCode() + ') ' + stockError);
        }

        OAuthResult result = (OAuthResult)JSON.deserialize(body, OAuthResult.class);
        this.authToken = result.access_token;
        return result.access_token;
    }

    private class BSINetworkException extends Exception {}

    // These objects exist to be serialized into a JSON request for posting
    // to the InterPayments API.

    private class PaymentLinkRequest {
        PaymentLinkBody paymentLink = new PaymentLinkBody();

        public PaymentLinkRequest(Settings settings, String invoice, Integer amount, Integer tax) {
            paymentLink.confirmation.redirectUrl = settings.redirectUrl;
            paymentLink.gatewayId = settings.gatewayId;
            paymentLink.amount = amount;
            paymentLink.taxAmount = tax;
            paymentLink.invoiceNumbers = new String[] { invoice };
            paymentLink.locationId = settings.locationId;
        }
    }

    private class PaymentLinkBody {
        public Integer amount = 0;
        public Boolean capture = true;
        public String paymentLinkType = 'Checkout'; // Awaiting 'invoice'
        public PaymentConfirmation confirmation = new PaymentConfirmation();
        public String gatewayId = '';
        public String[] invoiceNumbers = new String[] { };
        public String locationId = '';
        public PaymentLinkSession session = new PaymentLinkSession();
        public Integer taxAmount = 0;
        public String url = ''; // used when deserializing response, to extract payment link
    }

    private class PaymentConfirmation {
        public String redirectUrl = 'https://www.fortra.com';
    }

    private class PaymentLinkSession {
        PaymentLinkCard card = new PaymentLinkCard();
    }

    private class PaymentLinkCard {
    }

    private class OAuthRequest {
        public String grant_type = 'client_credentials';
        public String audience = '';
        public String client_id = '';
        public String client_secret = '';

        public OAuthRequest(String audience, String client, String secret) {
            this.audience = audience;
            this.client_id = client;
            this.client_secret = EncodingUtil.urlEncode(secret, 'UTF-8');
        }

        public String toJson() {
            return JSON.serialize(this);
        }
    }

    private class OAuthResult {
        public String access_token;
        public Integer expires_in;
    }

    // Settings

    private class Settings {

        // OAuth
        public String tokenPath = '';
        public String clientId = '';
        public String clientSecret = '';
        public String audience = '';

        // API
        public String host = '';
        public String gatewayId = '';
        public String redirectUrl = '';
        public String locationId = '';

        public Settings() {

            // We're likely to harden secrets in the future. This represents a
            // bit of indirection in case we want to pull those secrets from
            // something other than generally visible custom metadata. The
            // rest of this class uses this class for settings, so if you keep
            // the names the same, we're good for whatever comes next!

            // Note that we can't grab Named Credentials from here, but the rest
            // of the settings we need are safe for Custom Metadata.

            InterPayment_Settings__mdt config = null;

            try {
                config = [
                    select
                        ApiHost__c, AuthTokenUrl__c, ClientId__c, ClientSecret__c,
                        GatewayId__c, RedirectUrl__c, Audience__c, Location_Id__c
                    from InterPayment_Settings__mdt where IsActive__c = true limit 1
                ];
            } catch (Exception e) {
                System.debug('Error 104: Unable to find an InterPayment_Settings__mdt to use for the client: ' + e.getMessage());
                throw new BSINetworkException('Error 104: ' + stockError);
            }

            // OAuth
            this.tokenPath = config.AuthTokenUrl__c;
            this.clientId = config.ClientId__c;
            this.clientSecret = config.ClientSecret__c;
            this.audience = config.Audience__c;

            // API
            this.host = config.ApiHost__c;
            this.gatewayId = config.GatewayId__c;
            this.redirectUrl = config.RedirectUrl__c;
            this.locationId = config.Location_Id__c;
        }
    }

    // Utilities

    private String getParameter(String name) {
        String value = ApexPages.currentPage().getParameters().get(name);
        return value;
    }
}