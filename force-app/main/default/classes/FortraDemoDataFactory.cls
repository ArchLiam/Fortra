/**
 * @description Generates realistic, idempotent demo data (accounts, places, products,
 * pricebook entries, opportunities, quotes, hardware, line groups, and line items) across
 * four Fortra quote document template scenarios for sandbox use; cleans up prior demo
 * records before each run and relies on specific picklist values (Fortra_Product_Type__c,
 * Quote_Type__c, Net_Terms__c, Show_Hide_Discounts__c, Header_Discount_Type__c,
 * Server_Type__c, Hardware__c.Status__c) existing in the target org.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class FortraDemoDataFactory {

    // ── Tag used to identify and clean up all demo records ──────────────
    private static final String DEMO_TAG = '[FORTRA-DEMO]';

    // ── Entry point ─────────────────────────────────────────────────────
    /**
     * @description Entry point that rebuilds the full demo data set: purges any existing
     * demo records, then inserts accounts, places, products, pricebook entries,
     * opportunities, quotes, hardware, line groups, and line items, and logs a summary.
     */
    public static void run() {
        cleanup();

        Pricebook2 stdPb = getStandardPricebook();

        List<Account>  accounts = insertAccounts();
        List<Places__c> places  = insertPlaces(accounts);
        List<Product2> products = insertProducts();
        List<PricebookEntry> pbes = insertPricebookEntries(stdPb.Id, products);
        List<Opportunity> opps  = insertOpportunities(accounts);
        List<Quote> quotes = insertQuotes(stdPb.Id, opps, places);
        List<Hardware__c> hardware = insertHardware(accounts[2]);
        List<QuoteLineGroup> groups = insertLineGroups(quotes[2].Id, hardware);
        insertLineItems(quotes, pbes, groups, hardware);

        printSummary(quotes);
    }

    // ── Cleanup — removes all records tagged with DEMO_TAG ──────────────
    /**
     * @description Deletes every demo record identified by the DEMO_TAG marker, cascading
     * from child to parent (line items, line groups, quotes, opportunities, hardware,
     * places, pricebook entries, products, accounts) to satisfy referential dependencies.
     */
    public static void cleanup() {
        delete [SELECT Id FROM QuoteLineItem
                WHERE Quote.Name LIKE :('%' + DEMO_TAG + '%')];
        delete [SELECT Id FROM QuoteLineGroup
                WHERE QuoteId IN (SELECT Id FROM Quote WHERE Name LIKE :('%' + DEMO_TAG + '%'))];
        delete [SELECT Id FROM Quote       WHERE Name LIKE :('%' + DEMO_TAG + '%')];
        delete [SELECT Id FROM Opportunity WHERE Name LIKE :('%' + DEMO_TAG + '%')];
        delete [SELECT Id FROM Hardware__c
                WHERE Account__c IN (
                    SELECT Id FROM Account WHERE Name LIKE :('%' + DEMO_TAG + '%')
                )];
        delete [SELECT Id FROM Places__c   WHERE Name LIKE :('%' + DEMO_TAG + '%')];
        delete [SELECT Id FROM PricebookEntry
                WHERE Product2.ProductCode LIKE :('%' + DEMO_TAG + '%')
                AND Pricebook2.IsStandard = true];
        delete [SELECT Id FROM Product2    WHERE ProductCode LIKE :('%' + DEMO_TAG + '%')];
        delete [SELECT Id FROM Account     WHERE Name LIKE :('%' + DEMO_TAG + '%')];
        System.debug('FortraDemoDataFactory: cleanup complete.');
    }

    // ────────────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ────────────────────────────────────────────────────────────────────

    /**
     * @description Queries and returns the org's standard pricebook.
     * @return The standard Pricebook2 record.
     */
    private static Pricebook2 getStandardPricebook() {
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
    }

    // ── ACCOUNTS ─────────────────────────────────────────────────────────
    /**
     * @description Inserts the four demo accounts (one per scenario) tagged with DEMO_TAG.
     * @return The inserted list of Account records.
     */
    private static List<Account> insertAccounts() {
        List<Account> records = new List<Account>{
            new Account(
                Name              = 'Apex Digital Solutions Inc. ' + DEMO_TAG,
                AccountNumber     = 'DEMO-10045',
                Phone             = '(312) 555-0192'
            ),
            new Account(
                Name              = 'Meridian Health Systems ' + DEMO_TAG,
                AccountNumber     = 'DEMO-20178',
                Phone             = '(512) 555-0348'
            ),
            new Account(
                Name              = 'Central Banking Corp ' + DEMO_TAG,
                AccountNumber     = 'DEMO-30291',
                Phone             = '(212) 555-0574'
            ),
            new Account(
                Name              = 'Summit Retail Group LLC ' + DEMO_TAG,
                AccountNumber     = 'DEMO-40382',
                Phone             = '(206) 555-0819'
            )
        };
        insert records;
        return records;
    }

    // ── PLACES ───────────────────────────────────────────────────────────
    /**
     * @description Inserts demo Places__c address records linked to the given accounts,
     * including two locations for the renewal (banking) account.
     * @param accounts The demo accounts the places are associated with.
     * @return The inserted list of Places__c records.
     */
    private static List<Places__c> insertPlaces(List<Account> accounts) {
        List<Places__c> records = new List<Places__c>{
            new Places__c(
                Name                    = 'Apex Digital Chicago HQ ' + DEMO_TAG,
                Account__c              = accounts[0].Id,
                Address__Street__s      = '200 W Monroe Street Suite 2100',
                Address__City__s        = 'Chicago',
                Address__StateCode__s   = 'IL',
                Address__PostalCode__s  = '60606',
                Address__CountryCode__s = 'US'
            ),
            new Places__c(
                Name                    = 'Meridian Health Austin HQ ' + DEMO_TAG,
                Account__c              = accounts[1].Id,
                Address__Street__s      = '3801 South Lamar Blvd Floor 4',
                Address__City__s        = 'Austin',
                Address__StateCode__s   = 'TX',
                Address__PostalCode__s  = '78704',
                Address__CountryCode__s = 'US'
            ),
            new Places__c(
                Name                    = 'Central Banking Corp HQ ' + DEMO_TAG,
                Account__c              = accounts[2].Id,
                Address__Street__s      = '100 Wall Street Floor 12',
                Address__City__s        = 'New York',
                Address__StateCode__s   = 'NY',
                Address__PostalCode__s  = '10005',
                Address__CountryCode__s = 'US'
            ),
            new Places__c(
                Name                    = 'Central Banking Corp Finance ' + DEMO_TAG,
                Account__c              = accounts[2].Id,
                Address__Street__s      = '100 Wall Street Floor 8',
                Address__City__s        = 'New York',
                Address__StateCode__s   = 'NY',
                Address__PostalCode__s  = '10005',
                Address__CountryCode__s = 'US'
            ),
            new Places__c(
                Name                    = 'Summit Retail Seattle HQ ' + DEMO_TAG,
                Account__c              = accounts[3].Id,
                Address__Street__s      = '1201 Third Avenue Suite 400',
                Address__City__s        = 'Seattle',
                Address__StateCode__s   = 'WA',
                Address__PostalCode__s  = '98101',
                Address__CountryCode__s = 'US'
            )
        };
        insert records;
        return records;
    }

    // ── PRODUCTS ─────────────────────────────────────────────────────────
    /**
     * @description Inserts the demo Product2 catalog covering all four scenarios (software,
     * subscription, renewal maintenance, and services), each tagged with DEMO_TAG.
     * @return The inserted list of Product2 records in scenario order.
     */
    private static List<Product2> insertProducts() {
        List<Product2> records = new List<Product2>{

            // [0-2] Scenario 1 — New Software
            new Product2(
                Name                   = 'GoAnywhere MFT Enterprise (500 Users)',
                ProductCode            = 'GA-ENT-500-LIC-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Software',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'GoAnywhere MFT Enterprise perpetual license for up to 500 concurrent users with unlimited file transfers and connectors.'
            ),
            new Product2(
                Name                   = 'GoAnywhere Agents Bundle - 50 Agents',
                ProductCode            = 'GA-AGT-050-LIC-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Software',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Bundle of 50 GoAnywhere MFT Agent connections for automating file transfers to remote systems.'
            ),
            new Product2(
                Name                   = 'GoAnywhere Secure Mail Add-On',
                ProductCode            = 'GA-SMAIL-ADN-LIC-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Software',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Secure email delivery module enabling encrypted email transmission directly from GoAnywhere MFT workflows.'
            ),

            // [3-5] Scenario 2 — Subscription
            new Product2(
                Name                   = 'Tripwire Enterprise Cloud - 1,000 Assets (Annual)',
                ProductCode            = 'TW-ENT-CLD-1K-ANN-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Subscription',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Tripwire Enterprise cloud-hosted configuration and vulnerability management for up to 1,000 monitored assets. Annual subscription.'
            ),
            new Product2(
                Name                   = 'Tripwire Log Center Cloud - 500 GB/day',
                ProductCode            = 'TW-LC-CLD-500G-ANN-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Subscription',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Cloud-based SIEM and log analytics platform with up to 500 GB/day ingestion capacity. Annual subscription.'
            ),
            new Product2(
                Name                   = 'Tripwire Connect - Integration Platform (Annual)',
                ProductCode            = 'TW-CONN-SAAS-ANN-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Subscription',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Tripwire Connect integration and workflow automation platform for bidirectional data exchange with ITSM tools. Annual subscription.'
            ),

            // [6-7] Scenario 3 — Renewal Maintenance
            new Product2(
                Name                   = 'Core Security ISPF - Annual Maintenance Renewal',
                ProductCode            = 'CS-ISPF-MAINT-RNW-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Renewal Maintenance',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Annual maintenance renewal for Core Security ISPF providing privileged access control on IBM iSeries and Power Systems.'
            ),
            new Product2(
                Name                   = 'Core Security Access Control - Annual Maintenance Renewal',
                ProductCode            = 'CS-ACCTRL-MAINT-RNW-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Renewal Maintenance',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Annual maintenance renewal for Core Security Access Control covering user authentication and authorization for IBM Power platforms.'
            ),

            // [8-10] Scenario 4 — Services
            new Product2(
                Name                   = 'GoAnywhere MFT - Remote Implementation (Hourly)',
                ProductCode            = 'SVC-GA-IMPL-REM-HR-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Services',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Remote professional services for GoAnywhere MFT installation, configuration, and workflow development. Billed per hour.'
            ),
            new Product2(
                Name                   = 'GoAnywhere - Migration Assessment & Planning',
                ProductCode            = 'SVC-GA-MAP-FIXED-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Services',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Fixed-scope engagement covering discovery, current-state analysis, migration playbook, and project timeline for GoAnywhere MFT adoption.'
            ),
            new Product2(
                Name                   = 'GoAnywhere Administrator Training - Virtual (2-Day)',
                ProductCode            = 'SVC-GA-TRN-VIRT-2D-' + DEMO_TAG,
                IsActive               = true,
                Fortra_Product_Type__c = 'Services',
                QuantityUnitOfMeasure  = 'Each',
                Description            = 'Two-day virtual instructor-led administrator training covering GoAnywhere MFT architecture, workflows, security configuration, and troubleshooting.'
            )
        };
        insert records;
        return records;
    }

    // ── PRICEBOOK ENTRIES ────────────────────────────────────────────────
    /**
     * @description Inserts standard-pricebook entries with list prices for each demo product.
     * @param pbId The standard pricebook Id the entries belong to.
     * @param p The demo products, positionally mapped to their unit prices.
     * @return The inserted list of PricebookEntry records aligned to the product order.
     */
    private static List<PricebookEntry> insertPricebookEntries(Id pbId, List<Product2> p) {
        List<PricebookEntry> records = new List<PricebookEntry>{
            // Scenario 1 - Software
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[0].Id, UnitPrice = 42000.00, IsActive = true),  // [0]
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[1].Id, UnitPrice = 8500.00,  IsActive = true),  // [1]
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[2].Id, UnitPrice = 6200.00,  IsActive = true),  // [2]
            // Scenario 2 - Subscription
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[3].Id, UnitPrice = 68000.00, IsActive = true),  // [3]
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[4].Id, UnitPrice = 22500.00, IsActive = true),  // [4]
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[5].Id, UnitPrice = 8400.00,  IsActive = true),  // [5]
            // Scenario 3 - Renewal (ISPF has 2 price points across 2 hardware groups)
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[6].Id, UnitPrice = 18500.00, IsActive = true),  // [6] ISPF
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[7].Id, UnitPrice = 6200.00,  IsActive = true),  // [7] Access Control
            // Scenario 4 - Services
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[8].Id,  UnitPrice = 225.00,  IsActive = true),  // [8]  hourly rate
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[9].Id,  UnitPrice = 4500.00, IsActive = true),  // [9]  assessment
            new PricebookEntry(Pricebook2Id = pbId, Product2Id = p[10].Id, UnitPrice = 3200.00, IsActive = true)   // [10] training
        };
        insert records;
        return records;
    }

    // ── OPPORTUNITIES ────────────────────────────────────────────────────
    /**
     * @description Inserts one demo opportunity per account at the Proposal/Price Quote stage.
     * @param accts The demo accounts each opportunity is associated with.
     * @return The inserted list of Opportunity records.
     */
    private static List<Opportunity> insertOpportunities(List<Account> accts) {
        List<Opportunity> records = new List<Opportunity>{
            new Opportunity(
                Name            = 'Demo - GoAnywhere MFT Enterprise ' + DEMO_TAG,
                AccountId       = accts[0].Id,
                StageName       = 'Proposal/Price Quote',
                CloseDate       = Date.today().addDays(60),
                CurrencyIsoCode = 'USD'
            ),
            new Opportunity(
                Name            = 'Demo - Tripwire Enterprise Cloud ' + DEMO_TAG,
                AccountId       = accts[1].Id,
                StageName       = 'Proposal/Price Quote',
                CloseDate       = Date.today().addDays(45),
                CurrencyIsoCode = 'USD'
            ),
            new Opportunity(
                Name            = 'Demo - Core Security Annual Renewal ' + DEMO_TAG,
                AccountId       = accts[2].Id,
                StageName       = 'Proposal/Price Quote',
                CloseDate       = Date.today().addDays(30),
                CurrencyIsoCode = 'USD'
            ),
            new Opportunity(
                Name            = 'Demo - GoAnywhere Implementation Services ' + DEMO_TAG,
                AccountId       = accts[3].Id,
                StageName       = 'Proposal/Price Quote',
                CloseDate       = Date.today().addDays(30),
                CurrencyIsoCode = 'USD'
            )
        };
        insert records;
        return records;
    }

    // ── QUOTES ───────────────────────────────────────────────────────────
    /**
     * @description Inserts one demo quote per opportunity, each configured for its scenario
     * with the appropriate quote type, terms, discount display, and bill-to/ship-to places.
     * @param pbId The standard pricebook Id assigned to each quote.
     * @param opps The demo opportunities each quote is linked to.
     * @param places The demo places used for bill-to and ship-to references.
     * @return The inserted list of Quote records.
     */
    private static List<Quote> insertQuotes(
        Id pbId,
        List<Opportunity> opps,
        List<Places__c> places
    ) {
        Date today = Date.today();
        List<Quote> records = new List<Quote>{

            // [0] New Software — Apex Digital, Chicago
            new Quote(
                Name                    = 'Apex Digital – GoAnywhere MFT Enterprise Bundle ' + DEMO_TAG,
                OpportunityId           = opps[0].Id,
                Pricebook2Id            = pbId,
                Status                  = 'Draft',
                ExpirationDate          = today.addDays(60),
                Quote_Type__c           = 'New',
                Language__c             = 'English',
                Net_Terms__c            = 'Net 30',
                CurrencyIsoCode         = 'USD',
                Show_Hide_Discounts__c  = 'Show',
                Header_Discount_Type__c = 'Percentage',
                Ship_To_Place__c        = places[0].Id,
                Bill_To_Place__c        = places[0].Id,
                Description             = 'Initial GoAnywhere MFT enterprise deployment for 500-user environment including agent connections and secure mail delivery.'
            ),

            // [1] Subscription — Meridian Health, Austin
            new Quote(
                Name                    = 'Meridian Health – Tripwire Enterprise Cloud Suite ' + DEMO_TAG,
                OpportunityId           = opps[1].Id,
                Pricebook2Id            = pbId,
                Status                  = 'Draft',
                ExpirationDate          = today.addDays(45),
                Quote_Type__c           = 'New',
                Language__c             = 'English',
                Net_Terms__c            = 'Net 60',
                CurrencyIsoCode         = 'USD',
                Show_Hide_Discounts__c  = 'Hide',
                Ship_To_Place__c        = places[1].Id,
                Bill_To_Place__c        = places[1].Id,
                Description             = 'Comprehensive cloud security suite covering configuration management, SIEM, and integration orchestration for HIPAA-regulated environment.'
            ),

            // [2] Renewal Maintenance — Central Banking, New York
            new Quote(
                Name                    = 'Central Banking Corp – Core Security Annual Renewal ' + DEMO_TAG,
                OpportunityId           = opps[2].Id,
                Pricebook2Id            = pbId,
                Status                  = 'Draft',
                ExpirationDate          = today.addDays(30),
                Quote_Type__c           = 'Renewal',
                Language__c             = 'English',
                Net_Terms__c            = 'Net 90',
                CurrencyIsoCode         = 'USD',
                Show_Hide_Discounts__c  = 'Show',
                Header_Discount_Type__c = 'Percentage',
                Ship_To_Place__c        = places[2].Id,
                Bill_To_Place__c        = places[3].Id,
                Description             = 'Annual maintenance renewal for Core Security ISPF and Access Control covering 2 IBM production systems across 3 LPARs. Jul 2026–Jun 2027.'
            ),

            // [3] Services — Summit Retail, Seattle
            new Quote(
                Name                    = 'Summit Retail – GoAnywhere MFT Implementation Services ' + DEMO_TAG,
                OpportunityId           = opps[3].Id,
                Pricebook2Id            = pbId,
                Status                  = 'Draft',
                ExpirationDate          = today.addDays(30),
                Quote_Type__c           = 'New',
                Language__c             = 'English',
                Net_Terms__c            = 'Net 30',
                CurrencyIsoCode         = 'USD',
                Show_Hide_Discounts__c  = 'Hide',
                Ship_To_Place__c        = places[4].Id,
                Bill_To_Place__c        = places[4].Id,
                Description             = 'Professional services engagement for GoAnywhere MFT remote implementation, migration planning, and virtual administrator training.'
            )
        };
        insert records;
        return records;
    }

    // ── HARDWARE (Scenario 3 only) ───────────────────────────────────────
    /**
     * @description Inserts the two demo iSeries/Power hardware records used by the renewal
     * maintenance scenario for the given account.
     * @param acct The account the hardware records belong to.
     * @return The inserted list of Hardware__c records.
     */
    private static List<Hardware__c> insertHardware(Account acct) {
        List<Hardware__c> records = new List<Hardware__c>{
            new Hardware__c(
                Account__c              = acct.Id,
                Hardware_ID__c          = 'HW-CBC-001',
                Serial_Number__c        = 'IS-2019-4821A',
                Model_Number__c         = 'IBM Power E1080',
                iSeries_Model__c        = '9080-M9S',
                Server_Type__c          = 'iSeries',
                Feature_Code__c         = '9009-22G',
                iSeries_Feature_Code__c = 'FC-3584',
                Number_of_Processors__c = 8,
                Status__c               = 'Active',
                Notes__c                = 'Primary production iSeries – Chicago DC. Hosts CBCPROD01 (P01) and CBCDEV01 (P02) LPARs.'
            ),
            new Hardware__c(
                Account__c              = acct.Id,
                Hardware_ID__c          = 'HW-CBC-002',
                Serial_Number__c        = 'PS-2021-7732B',
                Model_Number__c         = 'IBM Power S1022',
                iSeries_Model__c        = '9105-22A',
                Server_Type__c          = 'iSeries',
                Feature_Code__c         = '9105-22A',
                iSeries_Feature_Code__c = 'FC-5765',
                Number_of_Processors__c = 4,
                Status__c               = 'Active',
                Notes__c                = 'Secondary production Power Systems – NJ DR site. Hosts CBCPROD02 (P01) LPAR.'
            )
        };
        insert records;
        return records;
    }

    // ── QUOTE LINE GROUPS (Scenario 3 only) ──────────────────────────────
    /**
     * @description Inserts hardware-scoped quote line groups on the renewal quote, one per
     * hardware system, with the renewal term start and end dates.
     * @param quoteId The renewal quote the line groups belong to.
     * @param hw The demo hardware records each group is associated with.
     * @return The inserted list of QuoteLineGroup records.
     */
    private static List<QuoteLineGroup> insertLineGroups(Id quoteId, List<Hardware__c> hw) {
        Date rnwStart = Date.newInstance(2026, 7, 1);
        Date rnwEnd   = Date.newInstance(2027, 6, 30);
        List<QuoteLineGroup> records = new List<QuoteLineGroup>{
            new QuoteLineGroup(
                Name                   = 'IBM Power E1080 – Primary Production',
                QuoteId                = quoteId,
                Hardware__c            = hw[0].Id,
                Hardware_Notes__c      = 'CBC Chicago DC – 8-processor E1080. Hosts PROD (P01) and DEV (P02) partitions.',
                SortOrder              = 1,
                StartDate              = rnwStart,
                EndDate                = rnwEnd
            ),
            new QuoteLineGroup(
                Name                   = 'IBM Power S1022 – DR Site',
                QuoteId                = quoteId,
                Hardware__c            = hw[1].Id,
                Hardware_Notes__c      = 'CBC NJ DR site – 4-processor S1022. Hosts PROD partition (P01) only.',
                SortOrder              = 2,
                StartDate              = rnwStart,
                EndDate                = rnwEnd
            )
        };
        insert records;
        return records;
    }

    // ── QUOTE LINE ITEMS ─────────────────────────────────────────────────
    /**
     * @description Inserts the quote line items for all four scenarios, applying scenario-
     * specific quantities, discounts, service dates, LPAR details, and hardware/group links.
     * @param quotes The demo quotes the line items are added to.
     * @param pbes The pricebook entries supplying each line's product and unit price.
     * @param groups The renewal quote line groups the maintenance lines are placed under.
     * @param hardware The hardware records referenced by the renewal maintenance lines.
     */
    private static void insertLineItems(
        List<Quote> quotes,
        List<PricebookEntry> pbes,
        List<QuoteLineGroup> groups,
        List<Hardware__c> hardware
    ) {
        Date subStart = Date.newInstance(2026, 6, 1);
        Date subEnd   = Date.newInstance(2027, 5, 31);
        Date rnwStart = Date.newInstance(2026, 7, 1);
        Date rnwEnd   = Date.newInstance(2027, 6, 30);

        List<QuoteLineItem> records = new List<QuoteLineItem>{

            // ── Q1: New Software – 3 products, 5% discount ───────────────
            new QuoteLineItem(
                QuoteId                = quotes[0].Id,
                PricebookEntryId       = pbes[0].Id,
                Quantity               = 1,
                UnitPrice              = 42000.00,
                Discount               = 5,
                SortOrder              = 1,
                Fortra_Product_Type__c = 'Software',
                Description            = 'GoAnywhere MFT Enterprise perpetual license – 500 concurrent users, unlimited connectors and workflows.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[0].Id,
                PricebookEntryId       = pbes[1].Id,
                Quantity               = 1,
                UnitPrice              = 8500.00,
                Discount               = 5,
                SortOrder              = 2,
                Fortra_Product_Type__c = 'Software',
                Description            = 'GoAnywhere Agents Bundle – 50 agent connections for automated high-volume remote transfer workflows.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[0].Id,
                PricebookEntryId       = pbes[2].Id,
                Quantity               = 1,
                UnitPrice              = 6200.00,
                Discount               = 5,
                SortOrder              = 3,
                Fortra_Product_Type__c = 'Software',
                Description            = 'GoAnywhere Secure Mail add-on – encrypted email delivery with S/MIME and digital signature support.'
            ),

            // ── Q2: Subscription – 3 products, 1-year, no discount ───────
            new QuoteLineItem(
                QuoteId                = quotes[1].Id,
                PricebookEntryId       = pbes[3].Id,
                Quantity               = 1,
                UnitPrice              = 68000.00,
                Discount               = 0,
                SortOrder              = 1,
                Fortra_Product_Type__c = 'Subscription',
                ServiceDate            = subStart,
                Effective_End_Date__c  = subEnd,
                Description            = 'Tripwire Enterprise Cloud – cloud-hosted config and vulnerability management for 1,000 monitored assets.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[1].Id,
                PricebookEntryId       = pbes[4].Id,
                Quantity               = 1,
                UnitPrice              = 22500.00,
                Discount               = 0,
                SortOrder              = 2,
                Fortra_Product_Type__c = 'Subscription',
                ServiceDate            = subStart,
                Effective_End_Date__c  = subEnd,
                Description            = 'Tripwire Log Center Cloud – cloud SIEM, 500 GB/day ingestion, real-time correlation and compliance reporting.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[1].Id,
                PricebookEntryId       = pbes[5].Id,
                Quantity               = 1,
                UnitPrice              = 8400.00,
                Discount               = 0,
                SortOrder              = 3,
                Fortra_Product_Type__c = 'Subscription',
                ServiceDate            = subStart,
                Effective_End_Date__c  = subEnd,
                Description            = 'Tripwire Connect – bidirectional integration with ServiceNow, Jira, Splunk, and Qualys.'
            ),

            // ── Q3: Renewal – Group 1 (IBM E1080, 2 LPARs) ──────────────
            new QuoteLineItem(
                QuoteId                = quotes[2].Id,
                PricebookEntryId       = pbes[6].Id,
                QuoteLineGroupId       = groups[0].Id,
                Quantity               = 1,
                UnitPrice              = 18500.00,
                Discount               = 8,
                SortOrder              = 1,
                Fortra_Product_Type__c = 'Renewal Maintenance',
                ServiceDate            = rnwStart,
                Effective_End_Date__c  = rnwEnd,
                LPAR_System_Name__c    = 'CBCPROD01',
                LPAR_Number__c         = 'P01',
                Description            = 'Core Security ISPF annual maintenance – primary production LPAR (CBCPROD01 / P01).',
                // Hardware__c lookup enables DR traversal: Hardware__r.Serial_Number__c,
                // Hardware__r.iSeries_Model__c, Hardware__r.iSeries_Feature_Code__c, etc.
                // Model__c, System_Type__c, Serial_Number__c are ID-type fields on QLI — omit
                Hardware__c            = hardware[0].Id,
                Hardware_Notes__c      = 'CBC Chicago DC – 8-processor E1080. Hosts PROD (P01) and DEV (P02) partitions.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[2].Id,
                PricebookEntryId       = pbes[7].Id,
                QuoteLineGroupId       = groups[0].Id,
                Quantity               = 1,
                UnitPrice              = 6200.00,
                Discount               = 8,
                SortOrder              = 2,
                Fortra_Product_Type__c = 'Renewal Maintenance',
                ServiceDate            = rnwStart,
                Effective_End_Date__c  = rnwEnd,
                LPAR_System_Name__c    = 'CBCDEV01',
                LPAR_Number__c         = 'P02',
                Description            = 'Core Security Access Control annual maintenance – development LPAR (CBCDEV01 / P02).',
                Hardware__c            = hardware[0].Id,
                Hardware_Notes__c      = 'CBC Chicago DC – 8-processor E1080. Hosts PROD (P01) and DEV (P02) partitions.'
            ),

            // ── Q3: Renewal – Group 2 (IBM S1022, 1 LPAR) ───────────────
            new QuoteLineItem(
                QuoteId                = quotes[2].Id,
                PricebookEntryId       = pbes[6].Id,
                QuoteLineGroupId       = groups[1].Id,
                Quantity               = 1,
                UnitPrice              = 24000.00,
                Discount               = 8,
                SortOrder              = 1,
                Fortra_Product_Type__c = 'Renewal Maintenance',
                ServiceDate            = rnwStart,
                Effective_End_Date__c  = rnwEnd,
                LPAR_System_Name__c    = 'CBCPROD02',
                LPAR_Number__c         = 'P01',
                Description            = 'Core Security ISPF annual maintenance – DR production LPAR (CBCPROD02 / P01).',
                Hardware__c            = hardware[1].Id,
                Hardware_Notes__c      = 'CBC NJ DR site – 4-processor S1022. Hosts PROD partition (P01) only.'
            ),

            // ── Q4: Services – 3 lines, no discount ──────────────────────
            new QuoteLineItem(
                QuoteId                = quotes[3].Id,
                PricebookEntryId       = pbes[8].Id,
                Quantity               = 40,
                UnitPrice              = 225.00,
                Discount               = 0,
                SortOrder              = 1,
                Fortra_Product_Type__c = 'Services',
                Description            = 'Remote GoAnywhere MFT implementation – 40 hrs @ $225/hr. Includes install, configuration, and 5 production workflow builds.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[3].Id,
                PricebookEntryId       = pbes[9].Id,
                Quantity               = 1,
                UnitPrice              = 4500.00,
                Discount               = 0,
                SortOrder              = 2,
                Fortra_Product_Type__c = 'Services',
                Description            = 'GoAnywhere Migration Assessment & Planning – 5-day fixed engagement: discovery, current-state analysis, migration playbook.'
            ),
            new QuoteLineItem(
                QuoteId                = quotes[3].Id,
                PricebookEntryId       = pbes[10].Id,
                Quantity               = 2,
                UnitPrice              = 3200.00,
                Discount               = 0,
                SortOrder              = 3,
                Fortra_Product_Type__c = 'Services',
                Description            = 'GoAnywhere Admin Training Virtual (2-Day) – 2 sessions, up to 6 participants each. Includes lab guide and recording.'
            )
        };
        insert records;
    }

    // ── SUMMARY ──────────────────────────────────────────────────────────
    /**
     * @description Writes a formatted debug-log summary of the created demo quotes,
     * including their record Ids and per-scenario totals, discounts, and terms.
     * @param quotes The demo quotes to report on.
     */
    private static void printSummary(List<Quote> quotes) {
        System.debug('');
        System.debug('╔══════════════════════════════════════════════════════════════╗');
        System.debug('║          FORTRA DEMO DATA — CREATED SUCCESSFULLY             ║');
        System.debug('╠══════════════════════════════════════════════════════════════╣');
        System.debug('║  [Q1] NewSoftware     → ' + quotes[0].Id + '  ║');
        System.debug('║  [Q2] Subscription    → ' + quotes[1].Id + '  ║');
        System.debug('║  [Q3] Renewal Maint   → ' + quotes[2].Id + '  ║');
        System.debug('║  [Q4] Services        → ' + quotes[3].Id + '  ║');
        System.debug('╠══════════════════════════════════════════════════════════════╣');
        System.debug('║  Q1 ~$53,865   3 Software products   5% disc   Net 30       ║');
        System.debug('║  Q2 ~$98,900   3 Subscriptions       no disc   Net 60       ║');
        System.debug('║  Q3 ~$44,644   3 Renewal LPARs       8% disc   Net 90       ║');
        System.debug('║  Q4 ~$16,900   3 Services lines      no disc   Net 30       ║');
        System.debug('╠══════════════════════════════════════════════════════════════╣');
        System.debug('║  To remove all demo records: FortraDemoDataFactory.cleanup() ║');
        System.debug('╚══════════════════════════════════════════════════════════════╝');
    }
}