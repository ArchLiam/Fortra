# Pricing Procedure V21 — Validation Scenario Catalog
Procedure: `Rev_Mgmt_Default_Pricing_Procedure` — Active Version **V21** (FortraUAT, confirmed 2026-06-29)

**104 scenarios** across 11 categories.

## A. Pricing Source / Channel  (7)

### A-01 — Catalog/list-priced new line (PricingSource not LastTransaction)  `P0`
- **Tests:** A standard non-contracted, non-derived line is priced directly from the catalog price book entry (Product2.ListPrice via PBE) with no adjustment, rather than from a prior transaction
- **Proc mechanism:** DP2 List Price step (Line.ListPrice = PricebookEntry.UnitPrice); Price Book Entries; Attribute Pricing Filter (ItemPricingSource NotEquals 'LastTransaction'); Quantity*Price (ItemPricingSource NotEquals 'LastTransaction')
- **Expected:** NetUnitPrice/UnitPrice resolves from PBE list price; Quantity*Price computes ItemNetTotalPrice = NetUnitPrice * Qty; discounts applied downstream
- **Test setup:** New quote, Cyber brand Software (e.g. Digital Guardian/Cobalt Strike), One-Time/Perpetual, Qty=5, USD, Direct, no attributes, IsContracted=null
- **Provenance:** none / catalog-derived

### A-02 — LastTransaction-sourced line bypasses catalog repricing (carry-forward)  `P0`
- **Tests:** A line whose ItemPricingSource='LastTransaction' must SKIP catalog price book, attribute pricing, partner/volume discount, and Quantity*Price recompute, preserving the prior-transaction price; on order reprice the prior order price is also preserved
- **Proc mechanism:** Negative filters (ItemPricingSource NotEquals 'LastTransaction') on Attribute Pricing Filter, Quantity*Price, Manual Quote Level Discount, Partner Discount Derived Maint, List Operation; ListOperation80 (Equals 'LastTransaction') handles carry-forward
- **Expected:** Prior-transaction/order NetUnitPrice preserved; no catalog re-derivation
- **Test setup:** Renewal/amend or order-reprice line with ItemPricingSource='LastTransaction', Qty=2
- **Provenance:** none / catalog-derived

### A-03 — Derived asset price on renewal (inherit Asset.Price, not catalog)  `P0`
- **Tests:** A renewal quote line inherits its UnitPrice from the prior Asset.Price (the net price that was invoiced) via native pull, not a fresh pricebook lookup
- **Proc mechanism:** Derived Products - Native Pull; Derived Pricing Filter (ItemIsDerived=true); QuoteAction(Renew) -> Asset.Price -> QuoteLineItem.UnitPrice (pre-COLA)
- **Expected:** Renewal line UnitPrice equals the prior invoiced Asset price, not the current pricebook entry
- **Test setup:** Renewal quote, QuoteAction.Type='Renew', line refs prior-order Asset, same product
- **Provenance:** SC-3372 / SC-3346

### A-04 — Contracted/asset-sourced line stamps PricingDate  `P1`
- **Tests:** A line tied to an existing contract/asset stamps PricingDate=EffectiveDate so contracted pricing is honored on its effective date rather than a fresh catalog lookup
- **Proc mechanism:** Contacted Pricing (IsContracted IsNotNull AND IsContracted=true AND PricingDate IsNull -> set PricingDate=EffectiveDate)
- **Expected:** PricingDate set from EffectiveDate; contracted price effective-date alignment applied
- **Test setup:** Software contracted asset line, IsContracted=true, PricingDate=null, Txn=Amend on existing contract
- **Provenance:** none / catalog-derived

### A-05 — Derived non-derived exclusion from derived filters  `P1`
- **Tests:** A standard line (ItemIsDerived=false/null) must NOT enter Derived Pricing Filter, Derived Maintenance Net Filter, or Stamp Contributor Base derived branches; standard waterfall applies
- **Proc mechanism:** Derived Pricing Filter / Derived Maintenance Net Filter (ItemIsDerived Equals true) exclude it; Stamp Base Filter ((ItemIsDerived IsNull OR =false)) includes it
- **Expected:** Standard waterfall applies; derived formula skipped
- **Test setup:** Software line, ItemIsDerived=false, Qty=3, New quote
- **Provenance:** none / catalog-derived

### A-06 — Contracted-vs-catalog source switch mid-quote (IsContracted toggled / asset detach)  `P2`
- **Tests:** When a line's IsContracted/ItemPricingSource changes between reprices (e.g. asset detached so a contracted line reverts to catalog, or a fresh line becomes contracted), the procedure must re-route between Contacted Pricing and the catalog waterfall and clear the stale PricingDate; verifies the source-switch transition, not just steady-state A-02/A-04
- **Proc mechanism:** Contacted Pricing (IsContracted=true AND PricingDate IsNull) vs catalog DP2 List Price; on switch to catalog the negative IsContracted branch + PricingDate must reset so a stale contracted PricingDate doesn't pin an old pricebook date
- **Expected:** Toggling IsContracted re-routes the line: contracted->catalog clears PricingDate and re-derives from PBE as-of EffectiveDate; catalog->contracted seeds PricingDate; no stale-date carryover
- **Test setup:** Line first priced contracted (PricingDate seeded), detach asset / set IsContracted=false, reprice -> expect catalog price + reset PricingDate
- **Provenance:** none / completeness-gap

### A-07 — Derived maintenance family inconsistency (BoKS vs FIM)  `P2`
- **Tests:** BoKS new-maintenance derives correctly (20% tier x 355 list = 71) but FIM new-maintenance either 100%-copies list or prices $0 because FIM products carry no Maintenance Type Defn attribute, falling to native Formula=UnitPrice or unbound
- **Proc mechanism:** DerivedPricingFormula tier lookup on Maintenance_Rate__mdt / Maintenance Type Defn attribute; missing attribute -> native Formula=UnitPrice fallback (100% copy) or unbound $0
- **Expected:** All maintenance products should carry Maintenance Type Defn; if missing, fallback should be a documented standard (e.g. Standard 20%), not variable 100% or $0
- **Test setup:** New quote (a) BoKS license+maint expect 355x20%=71; (b) FIM license+maint expect FIM-standard-rate x list
- **Provenance:** SC-3346 (NewMaint derivation / demo recipe)

## B. Selling Model  (8)

### B-01 — One-Time/Perpetual selling model PricingTermCount=1  `P0`
- **Tests:** A perpetual/one-time line gets PricingTermCount stamped to the one-time constant so Subscription Pricing computes a single-term price; order creates Activated non-subscription Asset and recognizes full revenue
- **Proc mechanism:** Assignment (OneTimePricingTermCountConstant -> PricingTermCount); Subscription Pricing (PricingTermCountValueOneConstant); ProductSellingModel='One-Time'
- **Expected:** PricingTermCount=1; ItemNetTotalPrice = NetUnitPrice * Qty * 1; Asset.IsSubscription=false, full revenue recognized
- **Test setup:** Perpetual software (e.g. Cobalt Strike), One-Time/Perpetual, Qty=1-4, USD, Direct, no support
- **Provenance:** none / catalog-derived

### B-02 — Term-Defined subscription (annual, renewable) with proration enabled  `P0`
- **Tests:** A Term-Defined line with StartProrationPeriod and ItemSubscriptionTerm enters the term-defined proration path, stamps PricingTermCount, and creates an Asset lifecycle (SubscriptionEndDate, renewal automation >=90 days before expiry)
- **Proc mechanism:** Term-Defined proration filter (SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull); ProrationTermDefined element -> PricingTermCount; ListOperationTermDefinedPTC
- **Expected:** Term proration computed; PricingTermCount derived (1 annual or fractional); Asset.IsSubscription=true with SubscriptionEndDate=Start+term; renewal auto-created >=90 days prior
- **Test setup:** Subscription software (e.g. Digital Guardian DLP yearly), Term-Defined, ItemSubscriptionTerm=12/36, StartProrationPeriod set, Qty=10
- **Provenance:** SC-3420 / SC-3415 / SC-3411

### B-03 — Usage / tiered-quantity model (PhishLabs, Tripwire, Alert Logic)  `P0`
- **Tests:** Subscription line whose price is computed by a customer attribute (assets, revenue, users, nodes) via CalculationMatrix tier lookup, multiplying NetUnitPrice by full PricingTermCount across the subscription duration
- **Proc mechanism:** Subscription Pricing (LineItemQuantity * PricingTermCount * InputUnitPrice -> InputUnitPrice); Subscription Aggregate Price; CalculationMatrix rows keyed on attribute-value range (Base + Attr*Multiplier or direct tier)
- **Expected:** Line total = Base + (attribute x multiplier) or tier price, applied per term; ItemNetTotalPrice reflects qty * term-count * unit price
- **Test setup:** PhishLabs Domain Protection, customer revenue 25B, tiered table multiplier; or Subscription Term-Defined term=12 Qty=8
- **Provenance:** SC-3390 (tiered twice) / SC-3384 (non-USD tiers)

### B-04 — Evergreen subscription (SaaS, no defined term end) full-period count  `P1`
- **Tests:** An Evergreen line gets the Evergreen term-count constant, is excluded from Term-Defined fixed-term proration, and (partial periods disabled, no end date) uses full-period count
- **Proc mechanism:** Assignment (EvergreenPricingTermCountConstant -> PricingTermCount); ListOperation94 (SellingModelType='TermDefined' OR 'Evergreen'); ListOperation91 (Evergreen AND (AllowPartialProrationPeriods=false OR itemTransientEndDate IsNull))
- **Expected:** Evergreen term count applied; full evergreen period billed; no fixed-term/partial proration; Asset continues past initial term unless cancelled
- **Test setup:** MSP monthly recurring (e.g. Alert Logic MDR Essentials node tier), Evergreen, AllowPartialProrationPeriods=false, itemTransientEndDate=null, GBP
- **Provenance:** none / catalog-derived

### B-05 — Evergreen anytime proration (partial periods + transient end date)  `P1`
- **Tests:** An Evergreen line that allows partial proration periods and has a transient end date enters the anytime (mid-period) proration line filter
- **Proc mechanism:** Evergreen anytime proration filter (Line level); ListOperation83 (SellingModelType='Evergreen' AND AllowPartialProrationPeriods=true AND itemTransientEndDate IsNotNull)
- **Expected:** Anytime (mid-period) proration computed against the transient end date
- **Test setup:** Subscription Evergreen, AllowPartialProrationPeriods=true, itemTransientEndDate mid-period, Qty=2
- **Provenance:** none / catalog-derived

### B-06 — Evergreen renewal (auto-continue, no fixed term-end)  `P1`
- **Tests:** An Evergreen line on a renewal/amend (QuoteAction context) keeps its evergreen term-count constant and prior net rather than re-deriving a fixed term; verifies the Evergreen×Renewal cell which is uncovered (catalog has Evergreen-new B-04/B-05 and TermDefined-renewal but no Evergreen-renewal)
- **Proc mechanism:** Assignment (EvergreenPricingTermCountConstant -> PricingTermCount) co-resident with Derived/COLA renewal branches; ListOperation94 (SellingModelType='Evergreen') AND QuoteTypeText='Renewal' carry-forward
- **Expected:** Evergreen renewal carries prior net (or COLA-uplifted net), keeps evergreen term count, no fixed-term proration, no end-date derivation; asset continues
- **Test setup:** Evergreen SaaS line (e.g. Alert Logic MDR node tier), QuoteTypeText='Renewal', QuoteAction.Type='Renew', AllowPartialProrationPeriods=false, GBP
- **Provenance:** none / completeness-gap

### B-07 — Usage/tiered model on Quote-to-Order convert + order reprice (tier re-eval on OrderItem context)  `P1`
- **Tests:** A usage/tiered (CalculationMatrix attribute-keyed) line must re-evaluate its tier identically on the OrderItem context after convert; verifies Usage×Convert cell (B-03 covers usage on quote only, F-09 covers convert generically but not the matrix attribute hydration on order side)
- **Proc mechanism:** Subscription Pricing + CalculationMatrix tier lookup on OrderItem context; attribute (revenue/nodes/users) must hydrate via OrderEntitiesMapping; whole proc re-run on order
- **Expected:** OrderItem tier price identical to quote; matrix attribute hydrated on order context; no $0 no-match from missing order-side attribute mapping
- **Test setup:** PhishLabs/Alert Logic tiered line, convert close-won quote to order, Reprice-All, verify tier attribute resolves on OrderItem
- **Provenance:** none / completeness-gap

### B-08 — Neither Evergreen nor Term-Defined (one-time) excluded from proration filters  `P2`
- **Tests:** A One-Time/Perpetual line (SellingModelType neither Evergreen nor TermDefined) is excluded from both proration line filters and gets one-time treatment
- **Proc mechanism:** ListOperation87 (SellingModelType NotEquals 'Evergreen' AND NotEquals 'TermDefined')
- **Expected:** No proration applied; one-time treatment
- **Test setup:** Software Perpetual, SellingModelType='OneTime', Qty=3
- **Provenance:** none / catalog-derived

## C. Product Type  (7)

### C-01 — Hardware/Power high-quantity line (per-unit decomposition, governor-safe)  `P0`
- **Tests:** A physical Hardware/Power line (GP Item Class OTHER, RC_46000) with large quantity prices each unit and aggregates correctly without CPU/SOQL governor blow-up; can link to a Hardware__c grouping record
- **Proc mechanism:** Quantity*Price; Aggregate Price; All Lines Null Safe Filter (LineItemQuantity >= 0); per-unit Power decomposition (1 OrderItem/unit)
- **Expected:** Each unit priced; ItemNetTotalPrice correct; no CPU/SOQL governor breach; appliance can link to Hardware record
- **Test setup:** Hardware/Power (e.g. Core CTS Gen4 sensor or seat-count Power line), Qty=150 sentinel, New order convert
- **Provenance:** SC-3447 / SC-3366

### C-02 — Maintenance product type derived pricing (new + renewal, RC_42000/43000/43120)  `P0`
- **Tests:** A maintenance SKU (separate from license) priced as a derived line: new maint as % of list (often 20-24%) via the maintenance derived branch; renewal maint perpetually renewing
- **Proc mechanism:** Derived Maintenance Net Filter (ItemIsDerived=true); Derived Pricing Formula (tier% x contributor base); Manual/Partner Discount - Derived Maintenance
- **Expected:** Maintenance net = contributor base * tier percent; new maint lines included with license, renewal lines created at asset renewal time
- **Test setup:** Derived maintenance (BoKS), ItemIsDerived=true, attached to license, New quote; or Tripwire perpetual + new maint RC_42000
- **Provenance:** SC-3410 / SC-3412 / SC-3346

### C-03 — Software product type aggregation (perpetual, RC_41000)  `P1`
- **Tests:** Software lines (Fortra_Product_Type__c='Software' / GP Item Class SOFTWARE) aggregate into the Software subtotal bucket; license + optional maintenance, no subscription lifecycle
- **Proc mechanism:** Total Software (Fortra_Product_Type__c Equals 'Software'); Software Aggregate Price
- **Expected:** Software lines summed into Total Software / Software subtotal
- **Test setup:** Perpetual software (e.g. Tripwire FIM console), Qty=1-2, mixed-type quote, 10k USD list
- **Provenance:** none / catalog-derived

### C-04 — Services product type aggregation  `P1`
- **Tests:** Services lines (Fortra_Product_Type__c='Services' / GP Item Class SERVICES) aggregate into the Services subtotal bucket; priced per hour/day/block, regional multiplier applied if enabled
- **Proc mechanism:** Total Services (Fortra_Product_Type__c Equals 'Services'); Services Aggregate Price; regional multiplier if Allow_Regional_Pricing__c=true
- **Expected:** Services lines summed into Total Services bucket; no bundle/subscription splitting
- **Test setup:** Services (e.g. Digital Guardian setup, SERV SUP), hours 40, rate 250 USD, Qty=1
- **Provenance:** none / catalog-derived

### C-05 — Subscription product type / subscription-split aggregation (RC_41202)  `P1`
- **Tests:** Subscription lines aggregate into the Subscription subtotal bucket; subscription-split bundle SKUs (Is Workday Bundle=TRUE) create LIC + MAINT child SKUs for Workday rev-rec while the quote shows one line
- **Proc mechanism:** Total Subscription (Fortra_Product_Type__c Equals 'Subscription'); Subscription Aggregate Price; order-time _LIC/_MAINT split for RC_41202 bundles
- **Expected:** Subscription lines summed into bucket; quote shows single bundle price; order creates two Workday lines (license/maintenance deferred separately)
- **Test setup:** Subscription (e.g. Clearswift Essentials), 12-month term, list 50k, Qty=4
- **Provenance:** none / catalog-derived

### C-06 — Add-on / modular feature priced separately but grouped  `P1`
- **Tests:** Add-on SKUs (e.g. GoAnywhere Advanced Workflows, PhishLabs Dark Web add-on) are priced separately and additively but grouped with the primary product line; no special override unless parent bundle pricing gates it
- **Proc mechanism:** Product2.Bundle='Add-On'/'Bundle Component'; parent SKU link; additive line pricing
- **Expected:** Add-on line included in same group as primary product; no override unless bundle gate
- **Test setup:** GoAnywhere Essentials (base 25k) + Advanced Workflows add-on (12.65k) as two lines in same group, subscription
- **Provenance:** none / catalog-derived

### C-07 — Mixed-type quote category-bucket isolation (Software+Services+Subscription+Hardware on one quote)  `P1`
- **Tests:** A single quote with all four Fortra_Product_Type buckets must route each line to its own subtotal (Total Software / Total Services / Total Subscription / Hardware) with no cross-contamination, and the four buckets sum to the header; isolated single-type tests (C-01..C-05) exist but not the combined routing/rollup
- **Proc mechanism:** Total Software / Total Services / Total Subscription filters on Fortra_Product_Type__c + respective Aggregate Price steps run on the same quote; header rollup sums all buckets
- **Expected:** Each line lands in exactly one bucket; buckets sum to Subtotal/TotalPrice; no line counted twice; empty-bucket reset (K-05) honored if a type absent
- **Test setup:** One quote: Software perpetual + Services regional + Subscription term-defined + Hardware Power, verify four subtotals and header sum
- **Provenance:** SC-3345 (completeness-gap cross)

## D. Pricing Mode  (10)

### D-01 — Attribute Value Pricing - Calculated Mode  `P0`
- **Tests:** A line with an attribute adjustment in Calculated mode multiplies the base price by the attribute multiplier percent and bridges base/net via IF guards; must price correctly on first reprice
- **Proc mechanism:** Attribute Value Pricing - Calculated Mode (Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Calculated'); Base_Price__c * Attribute_Multiplier_Pct__c; Calculated Mode Base/Net Bridge
- **Expected:** InputUnitPrice = Base_Price__c * multiplier; base and net bridged via IF(>0) guards
- **Test setup:** Product Has_Attribute_Adjustment__c=true, Attribute_Price_Mode__c='Calculated', multiplier set
- **Provenance:** SC-3390 / SC-3393

### D-02 — Attribute Value Pricing - Total Price Mode (fixed-price tier lookup)  `P0`
- **Tests:** A line with attribute adjustment in Total Price mode takes Base_Price__c directly as the input unit price (exact per-tier price, no base+multiplier), bridging net/base with IF(>0)
- **Proc mechanism:** Attribute Value Pricing - Total Price Mode (Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Total Price'); Base_Price__c -> InputUnitPrice; Total Price Base/Net Bridge; CalculationMatrix PriceModelType='Total Price'
- **Expected:** InputUnitPrice = Base_Price__c (matrix tier price); net/base bridged with IF(>0) guards
- **Test setup:** Has_Attribute_Adjustment__c=true, Attribute_Price_Mode__c='Total Price' (e.g. Alert Logic MDR 100-node tier exact MRF)
- **Provenance:** SC-3393 / SC-3390

### D-03 — Attribute server-type discount config completeness (3-attribute key)  `P0`
- **Tests:** Attribute-based adjustment keyed on Feature x Deployment x ServerType; a missing combination (e.g. {SFTP, OnPrem, NonProd}) yields no match so AttributeDiscount makes no change and net stays at list (also covers GoAnywhere Non-Production 50% rule)
- **Proc mechanism:** AttributeBasedPrice step queries Attribute_Based_Adjustment_Decision_Table with 3-attribute key; no match -> no adjustment -> NetUnitPrice stays list
- **Expected:** All valid attribute combinations have config rows; {SFTP,OnPrem,NonProd} -> Net != list; Non-Production deployment -> Net = List x 0.5
- **Test setup:** GS-GSE-NRPS-AAMP (Advanced Authentication), select {SFTP, OnPrem, NonProd} -> expect Net != 3150 list; GoAnywhere Dev instance -> 50%
- **Provenance:** SC-3360

### D-04 — GSA pricing (GSW__c=true) at 50% of list  `P0`
- **Tests:** A GSA/GSW federal-contract line prices at ListPrice * 0.5 (or GSA pricebook variant, e.g. TeamQuest TQG); a standard GSW__c=false/null line is excluded from GSA halving
- **Proc mechanism:** GSA Pricing (GSW__c Equals true) formula ListPrice * 0.5 -> InputUnitPrice; negative branch leaves catalog/attribute price
- **Expected:** GSW=true: InputUnitPrice = ListPrice * 0.5, no partner stacking; GSW=false: catalog/attribute price retained
- **Test setup:** GSW__c=true GSA/federal line, Qty=2; plus a GSW__c=false standard direct line
- **Provenance:** none / catalog-derived

### D-05 — Attribute Value Pricing - Unit Price Mode (base + multiplier)  `P1`
- **Tests:** A line with attribute adjustment in Unit Price mode uses Base_Price__c as the unit-price input (Base + Attr*Multiplier per tier), preserving net if >0
- **Proc mechanism:** Attribute Value Pricing - Unit Price Mode (Has_Attribute_Adjustment__c=true AND Attribute_Price_Mode__c='Unit Price'); Unit Price Base/Net Bridge; CalculationMatrix PriceModelType='Calculated'
- **Expected:** InputUnitPrice = Base + (attribute x multiplier) per tier with bridges; net preserved if >0
- **Test setup:** Has_Attribute_Adjustment__c=true, Attribute_Price_Mode__c='Unit Price' (e.g. PhishLabs rev 15B, tier 10-50B, Base 33050, mult 5.5)
- **Provenance:** SC-3393 / SC-3390

### D-06 — Attribute-Based Price decision-table adjustment (contracted vs catalog)  `P1`
- **Tests:** An attribute-based adjustment decision table applies for lines with ItemContractAttributePasId, gated to non-LastTransaction, non-derived, non-renewal
- **Proc mechanism:** Attribute-Based Price + Attribute Discount Entries; Attribute Pricing Filter (ItemContractAttributePasId IsNotNull AND ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND =false)
- **Expected:** Attribute_Based_Adjustment_Decision_Table applies adjustment to NetUnitPrice
- **Test setup:** Line with ItemContractAttributePasId set, DerivedPricingAttribute=false, non-renewal
- **Provenance:** none / catalog-derived

### D-07 — Volume / quantity-tiered discount (PriceAdjustmentTier step-down)  `P1`
- **Tests:** A qualifying-quantity non-contracted line receives a per-unit price that steps down by quantity band (1-100, 101-250, 251+) via PriceAdjustmentSchedule/Tier
- **Proc mechanism:** Volume Discount Entries; Volume Discounts ((IsContracted IsNull OR =false) AND ItemPricingSource NotEquals 'LastTransaction'); PriceAdjustmentSchedule/PriceAdjustmentTier keyed on Qty band
- **Expected:** Tier matching ordered qty applies (e.g. Qty=300 uses 251+ band, lower per-unit than 1-100 band)
- **Test setup:** Tripwire nodes perpetual, Qty=300, tiers 1-100=220k/node, 101-250 lower; IsContracted=false, New quote
- **Provenance:** SC-3390

### D-08 — Bundle-based adjustment / inclusive-price bundle  `P1`
- **Tests:** A bundle child/inclusive-price line receives bundle-based adjustment from the bundle decision table and its inclusive price flows to TotalLineAmount (bundle priced at discount to a-la-carte sum)
- **Proc mechanism:** Bundle Based Adjustment Entries (MainItemProduct/RootItemProduct + InclusivePrice); Assignment (InclusivePriceConstant -> TotalLineAmount); ListOperation97 (InclusivePrice Equals true)
- **Expected:** Bundle_Based_Adjustment_Decision_Table applies; inclusive bundle price set into TotalLineAmount
- **Test setup:** GoAnywhere Starter Bundle (15% off a-la-carte=17.064k) parent + inclusive-price children, InclusivePrice=true
- **Provenance:** SC-3346 (Tripwire bundle-format)

### D-09 — Attribute mode crossed with currency — Total-Price tier matrix in non-USD  `P1`
- **Tests:** A Total-Price-mode attribute line (Base_Price__c = exact matrix tier price) in a non-USD quote must read a currency-matched tier value, not a USD tier value then FX-multiply (which would double-apply or mismatch); ties D-02/D-05 attribute modes to G-03 currency-blind ABA/ATPS gap at the mode level
- **Proc mechanism:** Attribute Value Pricing - Total Price Mode (Base_Price__c -> InputUnitPrice) + CalculationMatrix PriceModelType='Total Price' keyed WITH CurrencyIsoCode; must not FX-convert an already-currency-native tier nor read USD tier
- **Expected:** Tier price read from the EUR/GBP matrix row directly (no FX double-apply); if only USD tier exists, surfaced as no-match/error not silent USD value
- **Test setup:** Alert Logic MDR 100-node Total-Price tier, EUR quote, verify net = EUR tier (not USD tier × 0.9346 and not raw USD)
- **Provenance:** SC-3384 / SC-3393 (completeness-gap cross)

### D-10 — Formula-Based pricing  `P2`
- **Tests:** A formula-priced product computes its unit price via the Formula Based Pricing step from a configured formula
- **Proc mechanism:** Formula Based Pricing; Formula Based Pricing 3
- **Expected:** Unit price computed from the configured formula
- **Test setup:** Product configured with a formula-based pricing rule
- **Provenance:** none / catalog-derived

## E. Deal / Customer Type  (8)

### E-01 — Direct sale - no partner discount (Fortra Originated)  `P0`
- **Tests:** A Fortra-Originated direct deal (Quote.AccountId=end customer, Bill_To=AccountId) is excluded from partner discount steps; list/attribute price flows, subject only to discount-approval thresholds
- **Proc mechanism:** Partner Discount (Deal_Type__c NotEquals 'Fortra Originated' gate fails -> skip); Partner Percent Resolved Filter excludes
- **Expected:** No partner discount applied; net stays at list/attribute price; AE approval matrix applies
- **Test setup:** Deal_Type__c='Fortra Originated'/'Direct', enterprise end customer, Cyber software perpetual, Qty=5
- **Provenance:** none / catalog-derived

### E-02 — Channel/Reseller/Distributor partner discount on standard line  `P0`
- **Tests:** A non-Fortra-Originated (partner) non-derived line receives the resolved partner discount percent from Partner_Pricing_Model__c, selected by product type and hierarchy (Solution Category->Group->Unit); discount-model uses billing partner only, guaranteed-margin stacks all partners
- **Proc mechanism:** Partner Discount (Deal_Type__c NotEquals 'Fortra Originated' AND (ItemIsDerived IsNull OR =false)); Resolve Partner Discount Percent; Partner Percent Resolved Filter (PartnerDiscountPercent IsNotNull AND >0)
- **Expected:** Discount model: Net = List x (1-BillingPartner%); Guaranteed Margin: Net = List x (1-A%) x (1-B%); net != list
- **Test setup:** Deal_Type__c='Channel Originated', reseller (Optiv Diamond 20% SW) or 2-tier distributor (M.Tech 40% SW), ItemIsDerived=false, Qty=3
- **Provenance:** SC-3359

### E-03 — Partner discount calculated but not applied on One-Time/Perpetual (SubscriptionPricing overwrite)  `P0`
- **Tests:** Partner discount % correctly written to NetUnitPrice by the Partner Discount step but the One-Time/Perpetual SubscriptionPricing branch re-reads un-discounted InputUnitPrice and overwrites net, losing the discount
- **Proc mechanism:** V9 SubscriptionPricing74 (One-Time branch, seq24) outputs InputUnitPrice->NetUnitPrice instead of preserving discounted net like TermDefined branch SubscriptionPricing80; PartnerDiscount22 (seq10) net writes overwritten
- **Expected:** One-Time line applies partner discount to final net: NetUnitPrice = InputUnitPrice x (1-PartnerDiscountPercent), persisted through subscription pricing
- **Test setup:** One-Time perpetual product, partner deal, 20% discount, list 2008, expect net 1706.8
- **Provenance:** SC-3359

### E-04 — Fortra-Originated partner discount band (Non_Orig_* percents)  `P1`
- **Tests:** A Deal_Type__c='Fortra Originated' partner deal pulls its discount from the Non_Orig_* columns (typically lower tier than channel-originated)
- **Proc mechanism:** Partner_Pricing_Model__c Non_Orig_Software_Pct__c / Non_Orig_Subscription_Pct__c etc.; Deal Origin picklist drives column set
- **Expected:** Net = List x (1 - Non_Orig_Discount%); lower discount than channel-originated (e.g. 12% vs 20%)
- **Test setup:** Partner A (20% channel orig / 12% fortra orig), Deal_Type='Fortra Originated' -> 12%
- **Provenance:** none / catalog-derived

### E-05 — MSP sale - single invoice, lines grouped per end customer  `P1`
- **Tests:** A Channel MSP deal where the MSP is Bill-To and Customer of Record produces a single order/invoice but lines internally grouped per end customer (via Quote Line Group + Hardware record); renewals propagate the grouping
- **Proc mechanism:** Quote.AccountId=MSP; Quote Line Group + Hardware record grouping; single Workday invoice; partner pricing per MSP account
- **Expected:** Single order/invoice to MSP; lines grouped per end customer; co-termed renewals keep grouping
- **Test setup:** Meridian IT (MSP), billing GBP, lines grouped per end-customer, Powertech renewals co-termed
- **Provenance:** none / catalog-derived

### E-06 — GSA (GSW=true) crossed with partner deal — no discount stacking  `P1`
- **Tests:** A line that is both GSW__c=true and on a partner Deal_Type must apply GSA 50% ONLY and must NOT also stack the partner discount (D-04 notes 'no partner stacking' but no scenario crosses GSW×partner explicitly)
- **Proc mechanism:** GSA Pricing (GSW=true) ListPrice*0.5 -> InputUnitPrice; Partner Discount must be gated off or its net write must not compound the GSA-halved price
- **Expected:** Net = ListPrice*0.5 (GSA); partner percent NOT additionally applied; net != 0.5*list*(1-partner%)
- **Test setup:** GSW__c=true line, Deal_Type__c='Channel Originated' partner present, Qty=2, expect net = list*0.5 only
- **Provenance:** none / completeness-gap

### E-07 — Order line-type FIXED AMOUNT vs BILLING ONLY on splits  `P1`
- **Tests:** The Workday line-type reverse-lookup must distinguish quantity-split children (same product) from LIC/MAINT subsplit children (different product) so a quantity-split parent stays FIXED AMOUNT and is not mis-stamped BILLING ONLY
- **Proc mechanism:** Fortra_OrderItem_Set_Workday_Contract_Line_Type V8 reverse-lookup compares child vs parent Product2; V9/V10 broke subsplit detection (always-true / undistinguished)
- **Expected:** Quantity-split parent (qty>1 -> N qty=1, same product) stays FIXED AMOUNT (revenue recognized); only LIC/MAINT subsplit parent (different products) -> BILLING ONLY
- **Test setup:** Order: 3x Perpetual @3675 (parent qty=3 + 3 children qty=1 same product), expect FIXED AMOUNT
- **Provenance:** SC-3210 / SC-3368 / SC-3347

### E-08 — Partner percent resolved zero/null - no discount applied  `P2`
- **Tests:** A partner deal where the resolved PartnerDiscountPercent is null or not >0 (incl. incomplete product hierarchy falling back to 0%) yields no discount
- **Proc mechanism:** Partner Percent Resolved Filter (PartnerDiscountPercent IsNotNull AND GreaterThan 0) negative branch; hierarchy fallback Solution Category->Group->Unit->0%
- **Expected:** No partner discount; net unchanged at list
- **Test setup:** Deal_Type__c='Partner Originated', PartnerDiscountPercent=0/null or product missing Solution_Category__c
- **Provenance:** SC-3359

## F. Transaction Type  (12)

### F-01 — New quote standard pricing (full waterfall)  `P0`
- **Tests:** A brand-new quote line (QuoteTypeText != Renewal, action Add/null) runs the full catalog + attribute + discount waterfall, stamps contributor base, and is eligible for services regional pricing; no asset inheritance, no COLA
- **Proc mechanism:** Manual Quote Level Discount (ItemSalesTransactionAction 'Add' OR IsNull) AND non-derived; Stamp Base Filter (QuoteTypeText NotEquals 'Renewal'); start-date defaulting rules
- **Expected:** Full pricing waterfall; contributor base stamped; full list applied; subject to new-sale approval matrix
- **Test setup:** QuoteTypeText='New', ItemSalesTransactionAction='Add', new customer (e.g. Terranova SAT 1000-user annual), Qty=5
- **Provenance:** none / catalog-derived

### F-02 — Renewal quote preserves prior net (no fresh contributor base)  `P0`
- **Tests:** A renewal line (QuoteAction.Type='Renew', QuoteTypeText='Renewal') preserves prior NetUnitPrice in the derived formula, is NOT reset to 0, and is excluded from non-renewal/base-stamp/partner-derived branches; renewal maintenance auto-created
- **Proc mechanism:** Derived Pricing Formula (IF QuoteTypeText='Renewal' then NetUnitPrice); NetUnitPrice Value Reset (IF Renewal then NetUnitPrice else 0); Stamp Base Filter & Partner Discount-Derived Maint exclude renewals
- **Expected:** Renewal carries prior net; NetUnitPrice not reset to 0; no fresh contributor base stamping; renewal maint SKU (RC_43000/43120) created
- **Test setup:** QuoteTypeText='Renewal', derived maintenance line, prior NetUnitPrice present
- **Provenance:** SC-3350 / SC-3346 (NetUnitPrice seed)

### F-03 — COLA uplift on renewal (LastTransaction + Renew action)  `P0`
- **Tests:** A LastTransaction-sourced renewal with SalesTransactionActionType='Renew' and COLA_Uplift_Percent set gets COLACalculatedPrice stamped to BOTH InputUnitPrice and NetUnitPrice; COLA applied to net (discounted Asset.Price) not list
- **Proc mechanism:** COLA Uplift on Renewal (ItemPricingSource='LastTransaction' AND DerivedPricingAttribute=false AND SalesTransactionActionType='Renew' AND COLA_Uplift_Percent__c IsNotNull); COLACalculatedPrice -> InputUnitPrice AND NetUnitPrice
- **Expected:** Both InputUnitPrice and NetUnitPrice uplifted by COLA%; renewal net = Asset.Price(net) x (1+COLA%); e.g. 40k net x 1.05 = 42k (not 50k list x 1.05)
- **Test setup:** Renewal, ItemPricingSource='LastTransaction', SalesTransactionActionType='Renew', COLA_Uplift_Percent set (category rate), DerivedPricingAttribute=false
- **Provenance:** SC-3350 / SC-3346 / COLA V16-V20

### F-04 — Renewal generation headless bypasses prehook chain (COLA + description null)  `P0`
- **Tests:** RLM Fortra_Create_Renewal_Quote creates renewal QLIs outside the pricing-procedure reprice context, so prehooks (COLAUpliftPrehook, QLDescriptionGeneratorPrehook) never fire, leaving COLA price and generated description null on all renewal lines
- **Proc mechanism:** initiateRenewal platform API creates QLIs outside reprice; COLAUpliftPrehook + QLDescriptionGeneratorPrehook (registered LAST) only fire during procedure execution; COLAUpliftHandler bails on empty/late QuoteActionId (~35s FK lag)
- **Expected:** Renewal flow must trigger Reprice-All so prehook chain fires, OR move COLA + description onto a post-create trigger/flow; all renewal QLIs get COLA'd UnitPrice and formatted LineItemDescription without manual reprice
- **Test setup:** Renewal quote generated headlessly, 4+ attributes populated, expect COLA'd UnitPrice + pipe-delimited description
- **Provenance:** SC-3354 / SC-3350 / SC-3349

### F-05 — Multi-asset contract COLA override per asset (keying bug)  `P0`
- **Tests:** Contract override COLA percents must apply per asset on a multi-asset contract; AssetContractQueryHelper keying by ContractId only collapses 3 of 4 assets to the CMDT default with a mislabeled source
- **Proc mechanism:** AssetContractQueryHelper.cls query groups by ContractId only, losing per-asset distinctness; prehook per-ACR keying unaffected; Contract_COLA_Override_Percent__c joined per asset
- **Expected:** Each asset uses its own Contract_COLA_Override_Percent__c, not collapsed to the first match -> 4 distinct UnitPrices
- **Test setup:** Contract with 4 related assets, each with a distinct override rate, COLA renewal quote for all 4
- **Provenance:** SC-3354

### F-06 — Renewal maintenance born-net via Renew QuoteAction link  `P0`
- **Tests:** Renewal maintenance lines require QuoteAction.Type='Renew' + SourceAsset at creation to commit derived net through the native contributor-resolution engine; reprice-time/posthook corrections cannot override after settlement; No-Change lines stay $0
- **Proc mechanism:** Native DerivedProductsRenewals (V16+, authoritative committer) gates on QuoteAction(Type='Renew').SourceAssetId + Map Products + Asset Discovery + SalesTransactionActionType='Renew'
- **Expected:** Line born with Renew QuoteAction commits derived net (COLA pre-applied, corrected partner discount); born without it stays $0/stale and requires line re-creation to heal; No-Change is no-op
- **Test setup:** Renewal quote (a) manual Renew QA->owned RNM asset commits 67.38; (b) No-Change QA->RNM asset commits $0 (locked)
- **Provenance:** SC-3346 / SC-3404 / SC-3350

### F-07 — Quote-to-Order convert (price lock + order-level reprice)  `P0`
- **Tests:** Order created from quote locks the final quote prices (list/discount/regional/COLA) onto OrderItems; an order-level Reprice-All re-runs the procedure on OrderItem context with the correct contributor base and term fields, producing identical results with no contextDefinition gack
- **Proc mechanism:** Convert flow copies quote lines; Stamp Contributor Base (Pre-Discount) + Stamp Base Filter; Pricing Effective Dates; whole procedure re-evaluated on OrderItem context
- **Expected:** OrderItem.UnitPrice matches final QuoteLineItem price; order reprice identical to quote; no contextDefinition gack; term fields populated
- **Test setup:** Convert close-won quote to order then Reprice-All, mixed lines
- **Provenance:** SC-3308 / SC-3371 / reprice contextDef

### F-08 — Quote->Order convert fails: Prior_* item-attributes missing from Order context  `P0`
- **Tests:** The DerivedPricingRenewals formula on the Order side reads item-level Prior_Partner_Discount__c / Prior_Discretionary_Discount__c; if those attributes are missing from OrderEntitiesMapping after a version republish the engine cannot hydrate the read tags and throws an 'Unable to fetch tags' gack
- **Proc mechanism:** OrderEntitiesMapping must declare every item-level attribute any active procedure version reads; V9 republish lost the Prior_* mappings; OrderItem.Prior_* must be mapped and hydrated before reprice
- **Expected:** Order reprice yields CompletedWithPricing, not 'Unable to fetch tags [-1631597440]'
- **Test setup:** Derived maintenance line, order reprice after a version republish
- **Provenance:** SC-3371

### F-09 — New TermDefined subscription crossed with partner + currency at convert (term fields + discount + FX carry to order)  `P1`
- **Tests:** A brand-new Term-Defined partner non-USD line must carry PricingTermCount, partner discount, and currency conversion identically from quote to OrderItem on convert; combines I-01/I-02 (PTC convert), E-02 (partner), G-01 (currency) which are only tested in isolation
- **Proc mechanism:** ProrationTermDefined PTC + Partner Discount + Currency Conversion all on quote, then whole proc re-run on OrderItem context after convert; OrderEntitiesMapping must hydrate PTC, partner %, and currency
- **Expected:** OrderItem net = currency-converted list × (1−partner%) with PTC and EndDate populated; order activates without REQUIRED_FIELD_MISSING; identical to quote
- **Test setup:** New TermDefined annual line, Channel partner 20%, EUR, convert + Reprice-All + Activate; verify net, PTC, EndDate carry
- **Provenance:** none / completeness-gap

### F-10 — Renewal generated under RLM Quote DML lock (initiateRenewal headless, no Apex Quote DML)  `P1`
- **Tests:** With RLM/Subscription Mgmt enabled, all Quote DML is platform-blocked; renewal QLI creation and COLA/description seeding must occur via the platform initiateRenewal API or event/trigger paths, NOT Apex Quote DML, or the seed silently fails; verifies the Quote-DML-lock constraint on the renewal seed path (F-04 covers prehook bypass but not the DML-lock root)
- **Proc mechanism:** RLM Quote DML lock (Apex==REST error); Fortra_Create_Renewal_Quote uses initiateRenewal; COLA/description must be applied via Reprice-All-triggered prehook or post-create platform-event flow, not Apex update on QuoteLineItem
- **Expected:** Renewal QLIs seeded with COLA + description without any Apex Quote DML; if a class attempts Quote DML it must be refactored to event/flow; no silent lock-swallow
- **Test setup:** Generate renewal headlessly with RLM enabled, confirm COLA + description applied without Apex Quote update; attempt Apex Quote DML expects platform block
- **Provenance:** none / completeness-gap (RLM Quote DML lock)

### F-11 — Amend / co-term line with correct partner band  `P1`
- **Tests:** An Amend line is included in the manual quote-level discount and amend-aware paths, honors co-term dates, and (if new-business maintenance) applies the new-business partner band, not the renewal band
- **Proc mechanism:** Manual Quote Level Discount (ItemSalesTransactionAction Equals 'Amend'); Partner discount table keyed on Fortra_Product_Type__c; procedure filter QuoteType NOT Renewal
- **Expected:** Amend line eligible for manual quote-level discount; co-term dates honored; new-maint partner band (e.g. 17%) applied not renewal band; mid-term add/remove prorated
- **Test setup:** ItemSalesTransactionAction='Amend', QuoteTypeText='Amendment', add 100 users mid-term co-termed, Fortra_Product_Type='New Maintenance' partner 17%
- **Provenance:** SC-3346

### F-12 — Amend mid-term REMOVE/downgrade produces prorated negative delta (not cancellation, not full credit)  `P1`
- **Tests:** An Amend that REMOVES seats/downgrades mid-term (ItemSalesTransactionAction='Amend', qty decrease) must compute a prorated negative delta for the unused remaining term, distinct from a full Qty=−1 cancellation (K-01) and distinct from an add-amend (F-11)
- **Proc mechanism:** Manual Quote Level Discount (Amend) + Term-Defined/Evergreen proration computing remaining-term fraction × removed-qty × net; not the CancelNetUnitPrice seed path
- **Expected:** Credit = removed qty × net × remaining-term fraction (e.g. remove 50 of 100 users at 6mo into 12mo term -> −(50×net×0.5)); not full-price, not full-term, not $0
- **Test setup:** ItemSalesTransactionAction='Amend', QuoteTypeText='Amendment', TermDefined annual, remove 50 users 6mo in, expect prorated negative delta
- **Provenance:** none / completeness-gap

## G. Multi-Currency / Regional  (8)

### G-01 — Non-USD currency conversion of unit/net/total/subtotal  `P0`
- **Tests:** A non-USD line applies its ISO-specific multiplier across net total/subtotal/total/unit (EUR 0.9346, GBP 0.7874, CAD 1.3889, AUD 1.5385, CHF 0.8850, ILS 3.6251, JPY 149.2537, NZD 1.6667, ARS 666.6667); reads currency-specific PBE
- **Proc mechanism:** Currency Conversion - Net Total / Subtotal / Net Unit Price / Total Line Amount / Unit Price Display (nested IF on STICurrencyIsoCode); currency-matched PricebookEntry; CURRENCYRATE() CMDT
- **Expected:** All currency outputs scaled by the per-ISO multiplier; order/invoice/Workday GL in that currency
- **Test setup:** STICurrencyIsoCode='EUR' (and one line per other ISO), Software, Qty=2; European customer Fortra International GmbH list 100k EUR
- **Provenance:** SC-3384

### G-02 — Configured pricing (ABA/tier/ATPS) ignores quote currency  `P0`
- **Tests:** Non-USD quote lines with attribute-based/tiered/server-type configured pricing read only USD rows because the decision tables and master data omit a CurrencyIsoCode key, producing USD base values or $0 no-match; auto-add maintenance can pick a wrong-currency PBE
- **Proc mechanism:** AttributeBasedAdjustment decision table (no CurrencyIsoCode key; 13,072 USD rows); AttributeVolumePricingPrehook SOQL omits CurrencyIsoCode; Attribute_Tier_Pricing_Storage__c (1,115 USD rows); Stamp_Source_List_Price resolves PBE without currency filter
- **Expected:** Pricing lookups must include CurrencyIsoCode in the composite key; non-USD ABA/ATPS rows + currency-matched PBE must be seeded; no currency-mismatch error
- **Test setup:** EUR quote with tiered/server-type configured product (e.g. AAMP, CLSAAS), expect net in EUR not USD; auto-add maintenance currency=EUR
- **Provenance:** SC-3384 / SC-3360

### G-03 — Partner discount on non-USD line (discount % vs converted base ordering)  `P0`
- **Tests:** A partner-deal line in non-USD must apply the partner percent and the currency multiplier in the correct order so net = (list × currencyMult) × (1−partner%); verifies Partner×non-USD cell (E-02 partner is USD, G-01 currency has no partner discount)
- **Proc mechanism:** Resolve Partner Discount Percent + Partner Percent Resolved Filter combined with Currency Conversion - Net Unit Price/Net Total nested-IF; ordering of discount vs FX multiply must not double-convert or convert the discount amount twice
- **Expected:** Net in target currency = currency-converted list × (1−partner%); single FX application; no USD partner% leakage
- **Test setup:** Deal_Type__c='Channel Originated' reseller 20%, EUR (0.9346) software list 100000 -> net 100000×0.9346×0.80; Qty=3
- **Provenance:** none / completeness-gap

### G-04 — Regional services country multiplier (AllowRegionalPricing, LIST channel only)  `P0`
- **Tests:** A services line with AllowRegionalPricing__c=true applies the country multiplier to the LIST channel (CEILING(List x mult /5)x5) while NET stays catalog, producing a structural TotalLineAmount != NetTotalPrice; applies on new quote + amendment, NOT renewal
- **Proc mechanism:** RegionalServicesPricingPrehook reads Services_Regional_Pricing__mdt (e.g. Italy 0.64, India 0.4, LATAM 0.5); RegionalServicesPrice27 assignment RegionalNetUnitPrice__c -> InputUnitPrice (list channel)
- **Expected:** List/TotalLineAmount scaled by regional multiplier and rounded to nearest 5; NetTotalPrice from catalog (structural list!=net) per documented design
- **Test setup:** Services line, AllowRegionalPricing__c=true, Italy (0.64) catalog 2400 -> 1540, or India 0.4 list 1000 -> 400; Qty=1, new/amend
- **Provenance:** SC-3374 / SC-3393 / regional services

### G-05 — USD line currency conversion no-op (multiplier 1.0)  `P1`
- **Tests:** A USD line falls through the IF chain to the 1.0 default, leaving unit/net/total/subtotal unchanged
- **Proc mechanism:** Currency Conversion steps default else 1.0; Opportunity.CurrencyIsoCode='USD' reads USD PBE, no conversion
- **Expected:** No scaling; USD values pass through unchanged; Workday posts USD
- **Test setup:** STICurrencyIsoCode='USD', domestic customer, Qty=3
- **Provenance:** SC-3384

### G-06 — Regional pricing disabled (AllowRegionalPricing=false) null-guard  `P1`
- **Tests:** A services line with AllowRegionalPricing__c=false/null does NOT get the country multiplier and never hydrates RegionalNetUnitPrice__c; the reconcile gate must null-guard so an add on a never-hydrated null US line does not fail
- **Proc mechanism:** Regional Services Price negative branch (AllowRegionalPricing__c=true gate fails); RegionalNetReconcileGate IsNotNull guard (V13)
- **Expected:** Standard catalog price; no regional scaling; no null-line failure on add
- **Test setup:** Services, AllowRegionalPricing__c=false, US country, Qty=1
- **Provenance:** SC-3393

### G-07 — Regional services line in non-USD currency (regional multiplier AND currency conversion together)  `P1`
- **Tests:** A Services line with AllowRegionalPricing__c=true in a non-USD currency must apply BOTH the country regional multiplier (LIST channel, rounded to 5) AND the currency conversion without one negating or double-applying the other; G-04 is USD-only regional, G-01 is currency-only
- **Proc mechanism:** RegionalServicesPricingPrehook (Services_Regional_Pricing__mdt country mult on LIST) + Currency Conversion steps; order: regional list adjust then FX, or FX then regional — must be defined so TotalLineAmount and NetTotalPrice both land in target currency
- **Expected:** TotalLineAmount = round5(catalogList × regionalMult) × currencyMult; NetTotalPrice = catalog × currencyMult; structural list!=net preserved in target currency; no double-FX
- **Test setup:** Services line AllowRegionalPricing=true, Italy 0.64, EUR (0.9346), catalog 2400, Qty=1; verify both adjustments land in EUR
- **Provenance:** SC-3374 / SC-3384 (completeness-gap cross)

### G-08 — FX rates / legal-entity dispatch on non-core currencies  `P2`
- **Tests:** Multi-currency reporting and invoicing rely on CurrencyType.ConversionRate (some non-core currencies at 1.0 instead of true rates) and Place->Fortra legal-entity mapping which gates currency, tax, decimal places, and the Workday invoice entity
- **Proc mechanism:** CurrencyType ConversionRate + DecimalPlaces (admin-maintained); Place.Default_Legal_Entity__c -> SalesRep -> default Fortra LLC; only 5 currencies (USD/EUR/GBP/AUD/CAD) in official scope
- **Expected:** Authorized currency rates maintained per Confluence table; reports/DocGen use CurrencyType.DecimalPlaces (JPY=0); correct legal entity drives currency/Workday ref (e.g. Japan->Fortra Japan KK JPY)
- **Test setup:** Check ConversionRate for ARS/CHF/ILS/JPY; Japan customer Place, Default_Legal_Entity=null -> Fortra Japan KK JPY COM071
- **Provenance:** SC-3384 / SC-3298 / BUG-MTC-388

## H. Discounts  (6)

### H-01 — Manual quote-level amount-based (line-level) discount  `P0`
- **Tests:** A manual fixed-amount discount entered at quote/line level reduces net for an eligible (non-LastTransaction, amend/add/null, non-derived) line; e.g. $5k off a $50k line
- **Proc mechanism:** Manual Quote Level Amount-Based (Line-Level); Manual Quote Level Discount gate (ItemPricingSource NotEquals 'LastTransaction' AND (Amend OR Add OR action IsNull) AND (ItemIsDerived IsNull OR =false))
- **Expected:** Net = list - entered amount; ItemNetTotalPrice recomputed
- **Test setup:** New/Amend non-derived line, ItemDiscountAmount/Manual_Discount_Amount set ($5k off $50k), Qty=2
- **Provenance:** none / catalog-derived

### H-02 — Manual quote-level percent (line-level) discount with approval gate  `P0`
- **Tests:** A manual percent discount reduces net for an eligible line and is flagged for approval if it exceeds the seller authority threshold (e.g. >25% perpetual exceeds AE authority)
- **Proc mechanism:** Manual Quote Level Percentage-Based (Line-Level); Discount Percent; same Manual Quote Level Discount gate; approval matrix on DiscountPercent
- **Expected:** Net = List x (1-percent); marked 'Sales Rule Broken' and routed for approval if authority exceeded
- **Test setup:** New non-derived line, 30% discount on Digital Guardian (exceeds AE 25%) -> routes to approval, Qty=4
- **Provenance:** none / catalog-derived

### H-03 — Manual discount on derived maintenance line  `P1`
- **Tests:** A derived maintenance line accepts a manual amount discount through its dedicated derived-maintenance manual path without breaking the contributor base
- **Proc mechanism:** Manual Discount - Derived Maintenance (AmountStringConstant + ItemDiscountAmount on derived line)
- **Expected:** Manual discount applied to derived net without breaking contributor base
- **Test setup:** Derived maintenance line, ItemIsDerived=true, ItemDiscountAmount set
- **Provenance:** SC-3346

### H-04 — Derived line excluded from standard manual + partner discount  `P1`
- **Tests:** A derived line must be excluded from the standard Manual Quote Level Discount and standard Partner Discount steps (handled only by the derived-maintenance variants) to avoid double-discounting
- **Proc mechanism:** Manual Quote Level Discount and Partner Discount ((ItemIsDerived IsNull OR =false)) negative branches; derived-maintenance discount paths apply instead
- **Expected:** Standard discount steps skip the derived line; only derived-maintenance manual/partner paths apply
- **Test setup:** Derived maintenance line, ItemIsDerived=true, partner deal
- **Provenance:** SC-3346 / SC-3359

### H-05 — Manual percent + volume-tier + partner discount stacking order on one line  `P1`
- **Tests:** A non-contracted partner line that also has a manual percent discount AND qualifies for a volume tier must apply the three discounts in a defined, non-double-counting order (volume tier -> partner% -> manual%) producing a deterministic net; no catalog scenario stacks manual + volume + partner together
- **Proc mechanism:** Volume Discounts (PriceAdjustmentTier) then Partner Discount (Resolve Partner Percent) then Manual Quote Level Percentage-Based; each writes net from the prior step's net, not from list
- **Expected:** Net = list × volumeTierFactor × (1−partner%) × (1−manual%) applied once each in order; no step re-reading list and clobbering a prior discount
- **Test setup:** Channel partner 20%, Qty=300 (251+ tier), manual 10%, non-contracted; verify deterministic stacked net
- **Provenance:** none / completeness-gap

### H-06 — Attribute discount entries  `P1`
- **Tests:** An attribute-driven discount applies via the attribute decision-table get to NetUnitPrice
- **Proc mechanism:** Attribute Discount Entries; Attribute-Based Price (Attribute_Based_Adjustment_Decision_Table)
- **Expected:** Attribute discount adjustment applied to NetUnitPrice
- **Test setup:** Line with a priced attribute + AttributeValue, non-renewal
- **Provenance:** none / catalog-derived

## I. Proration  (7)

### I-01 — Term-Defined line derives PricingTermCount via Proration step  `P0`
- **Tests:** A TermDefined line must derive its platform read-only PricingTermCount (and EndDate) via the Proration element; this writer was deleted in the V11->V12 rebuild leaving PTC null/unwritable across V12-V14, blocking convert/activation
- **Proc mechanism:** ProrationTermDefined element (input EffectiveFrom/To/PricingTermUnit/ItemSubscriptionTerm, filter SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND SubscriptionTerm IsNotNull) -> ProrationMultiplier -> PricingTermCount; ListOperationTermDefinedPTC
- **Expected:** Fresh reprice derives PricingTermCount=1 (or fractional) and EndDate automatically; both carry to OrderItem on convert; CalculationStatus=CompletedWithPricing
- **Test setup:** TermDefined product (e.g. ACTIDB/BESTSU, annual, ServiceDate set, PeriodBoundary=Anniversary, SubscriptionTerm=12 Months), reprice
- **Provenance:** SC-3420 / SC-3411 / SC-3406 / SC-3415

### I-02 — Quote->Order convert fails on null PricingTermCount/EndDate  `P0`
- **Tests:** Null PricingTermCount/EndDate on a TermDefined quote line propagates to the OrderItem at convert; native RLM blocks order activation of a termed line without EndDate + PTC; a root fix restores the Proration writer while the order-tier backstop only masks it
- **Proc mechanism:** createOrderFromQuote copies null PTC to OrderItem; native RLM REQUIRED_FIELD_MISSING ('PricingTermCount is required for Termed order products'); Fortra_OrderItem_Set_Dates V6 backstop stamps EndDate + PTC=1 on update only
- **Expected:** Root fix at quote tier so null never reaches order; convert succeeds and order activates without manual EndDate/PTC; backstop is emergency-only
- **Test setup:** TermDefined quote line with null PTC + null EndDate, convert via Fortra_Quote_to_Order_Conversion -> Activate
- **Provenance:** SC-3411 / SC-3415 / SC-3406

### I-03 — Mid-term Term-Defined proration (fractional PTC)  `P1`
- **Tests:** A TermDefined line with a mid-period start (ServiceDate/EffectiveFrom != subscription start) must prorate the period and compute a fractional PricingTermCount, pricing net proportionally; the TermDefined gate on the Proration action is currently missing
- **Proc mechanism:** Proration action (EffectiveFrom/To -> ProrationMultiplier -> PricingTermCount); TermDefined gate to be re-added; StartProrationPeriod handling
- **Expected:** Mid-term sale of an annual subscription computes fractional PricingTermCount (e.g. 0.5 for 6 months); net prorated; add/remove seats charged/refunded prorata
- **Test setup:** TermDefined line, EffectiveFrom=mid-year, SubscriptionTerm=12 Months, Anniversary; or add 100 users 6mo into 12mo term -> 6/12 x annual
- **Provenance:** SC-3420 / SC-3411

### I-04 — Evergreen anytime / partial-period proration (monthly, mid-month cancel)  `P1`
- **Tests:** An Evergreen line with partial periods + transient end date prorates the partial period; a mid-month cancel of a monthly product refunds prorated to the day; partial first/last periods on mid-month order starts
- **Proc mechanism:** Evergreen anytime proration filter (Line level); ListOperation83; daily rate = monthly/days-in-month
- **Expected:** Partial-period amount computed against end date (e.g. cancel day 15 of 30 of 4000 GBP -> 2000 refund; order 1/15 monthly -> first month prorated)
- **Test setup:** Evergreen monthly (Alert Logic MDR), cancel 15th; or order start 1/15 monthly term to 12/31
- **Provenance:** none / catalog-derived

### I-05 — Pricing effective dates resolution  `P1`
- **Tests:** The Pricing Effective Dates step resolves the correct PricingDate from EffectiveDate/contract/line start date for proration and price lookup, so a future-dated line reads the future-effective pricebook
- **Proc mechanism:** Pricing Effective Dates; Pricing Setting; Contacted Pricing (PricingDate seed); reads PBE as-of ServiceStartDate
- **Expected:** PricingDate correctly set; downstream proration/price-book uses the correct date (e.g. order 1/1, lines start 2/1 -> Feb pricebook)
- **Test setup:** Line with EffectiveDate/ServiceStartDate set, contract-attached, future start
- **Provenance:** none / catalog-derived

### I-06 — Co-termination proration to existing contract end-date (add aligns to anchor term-end)  `P1`
- **Tests:** A co-term add (amend) must prorate the new line from its start to the EXISTING contract/asset end-date (anchor), computing a fractional PricingTermCount to the co-term anchor rather than a fresh full term; F-11/E-05 mention co-term but no scenario validates the anchor-end proration math
- **Proc mechanism:** ProrationTermDefined with EffectiveTo = anchor contract end-date (not start+term); ProrationMultiplier from start-to-anchor; co-term date resolution feeding EffectiveTo
- **Expected:** PricingTermCount = (anchorEnd − start)/fullTerm; net prorated to the shared end-date; renewal then co-terms all lines together
- **Test setup:** Existing 12mo contract ending in 5mo, add line co-termed, SubscriptionTerm=12 Months -> expect PTC ≈ 5/12 and end-date = anchor end
- **Provenance:** none / completeness-gap

### I-07 — Full-period (no partial proration)  `P2`
- **Tests:** A line with AllowPartialProrationPeriods=false bills full periods with no fractional proration
- **Proc mechanism:** ListOperation91 (AllowPartialProrationPeriods=false OR itemTransientEndDate IsNull); StartProrationPeriod handling
- **Expected:** Full-period count used; no fractional proration
- **Test setup:** Evergreen/Term line, AllowPartialProrationPeriods=false
- **Provenance:** none / catalog-derived

## J. Derived / Maintenance Pricing  (14)

### J-01 — Derived non-renewal new-maintenance tier formula  `P0`
- **Tests:** A new (non-renewal) derived maintenance line computes net = tier-percent(AttributeValue) x contributor base (Source_List_Price__c / Base_Price__c) via the derived formula tiers; e.g. BoKS 355 x 20% = 71
- **Proc mechanism:** Derived Pricing Formula (IF QuoteTypeText != Renewal: tier % by Maintenance Type Defn AttributeValue * Source_List_Price__c); Derived Products - Non-Renewal; Stamp Contributor Base (Pre-Discount)
- **Expected:** Net = tierPct(AttributeValue) x base (Base_Price__c, else Pre_Partner_Price, else InputUnitPrice fallback)
- **Test setup:** New quote derived maintenance, license base present (e.g. PIA-PIA-NRPS-PIAP $355 + maint PIA-PIA-RNM-PIAMBK), AttributeValue='Standard' (0.20)
- **Provenance:** SC-3346 / SC-3410 / SC-3404 / NewMaint derivation

### J-02 — Derived formula tier percentages by support level (7-tier completeness)  `P0`
- **Tests:** Each Maintenance Type Defn AttributeValue maps to its correct derived percent (Expert .35, Premier .30, Express .30, Premium .24, Standard .20, Professional .20, Basic .15, else 0); products with no MTD must not silently fall to a $0 trailing branch (1,708 of 1,887 historically did)
- **Proc mechanism:** DerivedPricingFormula nested IF on AttributeValue x Source_List_Price__c (V16+ 7-tier); unknown/platinum/missing -> 0
- **Expected:** Correct tier percent per AttributeValue; missing MTD -> documented standard, not silent $0; formula must cover all 8 Maintenance_Rate__mdt tiers
- **Test setup:** New derived maintenance lines, one per AttributeValue tier (incl. Expert -> 0.35 x list; missing-MTD case)
- **Provenance:** SC-3346 / SC-3372 / NB-DERIVED-TIER

### J-03 — Derived renewal carries prior NetUnitPrice (no tier recompute) + reset on non-renewal  `P0`
- **Tests:** A renewal derived line keeps prior NetUnitPrice in the formula instead of recomputing from tier; a non-renewal derived line resets NetUnitPrice to 0 (clearing stale) before the formula re-seeds it
- **Proc mechanism:** Derived Pricing Formula (IF QuoteTypeText='Renewal' then NetUnitPrice); Derived Products - Renewals; Derived Pricing - NetUnitPrice Value Reset (IF Renewal then NetUnitPrice else 0)
- **Expected:** Renewal net = prior NetUnitPrice (tier recompute suppressed); non-renewal NetUnitPrice cleared to 0 then recomputed
- **Test setup:** QuoteTypeText='Renewal' derived line with prior NetUnitPrice; and a New derived line with stale NetUnitPrice
- **Provenance:** SC-3350 / SC-3346 (NetUnitPrice seed deletion)

### J-04 — COLA uplift on derived renewal net via prehook seed (commit, no $0)  `P0`
- **Tests:** A derived renewal line eligible for COLA gets COLACalculatedPrice stamped to both InputUnitPrice and NetUnitPrice, and the prehook seeds NetUnitPrice (guarded null/<=0) so the renewal commits the uplifted value rather than $0
- **Proc mechanism:** COLA Uplift on Renewal + COLA Uplift Net on Renewal (COLACalculatedPrice__c -> InputUnitPrice AND NetUnitPrice); COLAUpliftPrehook buildNetUnitPriceUpdate seeding NetUnitPrice via updateContextAttributes
- **Expected:** Renewal net = Asset.Price x (1+COLA%) (solution-category-matched from COLA_Uplift_Rules__mdt); both unit and net reflect uplift; no $0 commit
- **Test setup:** Derived/TermDefined renewal, COLA_Uplift_Percent set, SalesTransactionActionType='Renew', LastTransaction source, Solution_Category matched (e.g. Cybersecurity 7.85%)
- **Provenance:** SC-3350 / SC-3346 / COLA V16-V20

### J-05 — COLA renewal net oscillation / double-discount on partner maintenance  `P0`
- **Tests:** Renewal maintenance COLA net must NOT re-apply the partner discount already netted into the COLA base; the deferred partner-pricing path re-discounts, causing the net to oscillate between correct and double-discounted across reprices
- **Proc mechanism:** PartnerNetPricePosthook v1.4 buildRenewalMaintenanceColaUpdate returns null when procedureNet==colaNet then falls through to deferred partner path; v1.5 skips the deferred path when COLA-owned
- **Expected:** COLA renewal net stabilizes at correct value (e.g. base 71 x 1.0785 = 67.38 with prior 12% already netted), not oscillating 67.38<->60.64
- **Test setup:** Renewal RRM line, COLA base 71, 7.85% uplift, prior 12% discount, reprice multiple times
- **Provenance:** SC-3346 / SC-3404

### J-06 — Partner discount on derived maintenance (non-renewal, applied once)  `P0`
- **Tests:** A partner-deal derived maintenance non-renewal line gets a SEPARATE partner-discount path that applies the discount once and avoids the standard double-discount
- **Proc mechanism:** Partner Discount - Derived Maintenance (ItemIsDerived=true AND Deal_Type__c NotEquals 'Fortra Originated' AND ItemPricingSource NotEquals 'LastTransaction' AND QuoteTypeText NotEquals 'Renewal'); Stamp Partner Unit Price - Derived Maintenance; PartnerNetPricePosthook
- **Expected:** Partner discount applied once to derived net; no double discount
- **Test setup:** Derived maintenance line, Deal_Type='Partner Originated', New quote (not renewal), not LastTransaction
- **Provenance:** SC-3346 / SC-3359

### J-07 — New-maintenance net posthook fallback when procedure yields $0  `P0`
- **Tests:** New-maintenance lines where the procedure leaves NetUnitPrice null/$0 must be populated by the posthook fallback using Source_List_Price x MTD tier x partner/software factors
- **Proc mechanism:** PartnerNetPricePosthook (v1.4+) buildNewMaintenanceUpdate + loadNewMaintenanceLines; gates on NetUnitPrice null/<=0 AND Source_List_Price>0 AND Fortra_Product_Type='New Maintenance'
- **Expected:** Net = Source_List_Price x Maintenance_Rate(MTD tier) x (1-partner%) x (1-software%); posthook finalizes after procedure
- **Test setup:** New quote maintenance-only/derived line without a priced contributor, Source_List_Price=355, MTD Standard 0.20, no/12% partner
- **Provenance:** SC-3412 / SC-3410

### J-08 — Contributor base stamping (pre-discount) for non-derived non-renewal  `P0`
- **Tests:** A non-derived, non-renewal, non-LastTransaction line with NetUnitPrice>0 stamps Base_Price__c/Pre_Partner_Price__c from net so its derived children have a contributor base; multi-product asset renewals can anchor secondaries' maintenance on the primary
- **Proc mechanism:** Stamp Contributor Base (Pre-Discount); Stamp Base Filter ((ItemIsDerived IsNull OR =false) AND QuoteTypeText NotEquals 'Renewal' AND ItemPricingSource NotEquals 'LastTransaction' AND NetUnitPrice > 0); Stamp Base_Price and Pre_Partner from Net
- **Expected:** Base_Price__c/Pre_Partner_Price__c stamped from net for downstream derived lines
- **Test setup:** Non-derived license line, New quote, NetUnitPrice>0, not LastTransaction (e.g. bundle license anchoring add-on maint)
- **Provenance:** SC-3346 (contributor base)

### J-09 — Native derived pull requires contributing-product config (PBEDP)  `P0`
- **Tests:** An IsDerived PBE routes through the native DerivedProducts element which requires a PriceBookEntryDerivedPrice config row; a missing row hard-errors 'contributing products are missing' before the formula can price (incomplete rollout backfilled only 199/3453)
- **Proc mechanism:** Native RLM DerivedProducts/DerivedProductsRenewals element maps ContributingProduct<-ContributorProduct via PBEDP config; no row = hard-error; Derived Pricing Filter (ItemIsDerived=true)
- **Expected:** Backfill PBEDP rows for all IsDerived PBEs, or remove the native element after confirming the formula suffices; clear error not silent null
- **Test setup:** IsDerived maintenance line without PBEDP config row (e.g. GS-GSE-RNM-EFT8), reprice
- **Provenance:** SC-3372 / M5-PBEDP

### J-10 — Derived maintenance renewal crossed with partner AND COLA AND non-USD simultaneously (four-factor stack)  `P0`
- **Tests:** A single renewal maintenance line that is derived, partner-discounted, COLA-uplifted, AND non-USD must apply each factor exactly once in the correct order (prior-net base × COLA × partner-once × FX) without the J-05 oscillation/double-discount or G-02 currency-blind lookup; the maximal interaction cell is uncovered
- **Proc mechanism:** DerivedProductsRenewals committer + COLA Uplift Net on Renewal + PartnerNetPricePosthook v1.5 (skip deferred path when COLA-owned) + Currency Conversion Net Unit Price; PartnerNetPricePosthook must not re-discount already-netted COLA base; FX must apply to the final net once
- **Expected:** Net = priorAssetNet × (1+COLA%) × (1−partner% if not already in base) × currencyMult, applied once each; stable across multiple reprices; no oscillation, no double-discount, no USD-value leak
- **Test setup:** Renewal RRM maintenance line, ItemIsDerived=true, Deal_Type='Channel Originated' 12% prior-netted, COLA 7.85%, EUR (0.9346), reprice 3× and compare
- **Provenance:** SC-3346 / SC-3384 / SC-3359 (completeness-gap cross)

### J-11 — Zero-price contributing product -> $0 derived maintenance  `P1`
- **Tests:** When the contributing license has $0 list everywhere, the derived maintenance formula (tier% x Source_List_Price) returns $0 regardless of tier; the contributor must have a non-zero base or the formula must use an alternate base
- **Proc mechanism:** DerivedPricingFormula net = tier% x Source_List_Price__c; $0 license -> Source_List_Price stamped $0 -> $0 net
- **Expected:** Contributing license must have non-zero list in the relevant pricebook/currency, OR formula uses contract/prior/override base; explicit $0 with explanation if intended
- **Test setup:** Maintenance auto-add on a $0 license (e.g. GS-GSE-RNM-EFT8 derived from $0 GS-GSE-NRPS-E8CP), reprice
- **Provenance:** SC-3372

### J-12 — Native pull reads asset COLA/override priority order  `P1`
- **Tests:** Renewal automation reads Asset/Contract native fields to compute the COLA percent in priority order: line override -> contract override -> CMDT default per Solution Category
- **Proc mechanism:** Renewal batch: fetch Asset -> Asset.COLA_Uplift_Percent__c (line) -> Contract.COLA_Override_Percent__c -> COLA_Uplift_Rules__mdt default per Solution Category
- **Expected:** Configured COLA % applied in priority order (e.g. Asset line override 8% overrides CMDT default 5%)
- **Test setup:** Renewal quote, Asset.COLA_Uplift_Percent__c=8%, CMDT default 5%
- **Provenance:** none / catalog-derived

### J-13 — Derived maintenance net filter aggregation  `P1`
- **Tests:** Derived maintenance lines (ItemIsDerived=true) are filtered for net aggregation separately into the correct bucket
- **Proc mechanism:** Derived Maintenance Net Filter (ItemIsDerived Equals true)
- **Expected:** Derived maintenance net captured in the correct aggregate bucket
- **Test setup:** Derived maintenance line set, ItemIsDerived=true
- **Provenance:** SC-3346

### J-14 — Out-year / MyCAP multi-year COLA inert (design drift)  `P2`
- **Tests:** The spreadsheet model specifies multi-year compounding Y2/Y3 COLA totals, but the live Final_Year_COLA_Calculated_Price__c formula is broken and never feeds pricing; single-year per spec is the agreed scope
- **Proc mechanism:** Formula field Final_Year_COLA_Calculated_Price__c computes but has zero references in the procedure; branches use wrong bases + PricingTermCount exponent without unit guard
- **Expected:** Either wire Final_Year prices into the procedure for Y2/Y3 billing, or confirm out-year stays flat (single-year per spec, agreed out-of-scope)
- **Test setup:** Multi-year renewal (3-year term), COLA active, check whether Y2/Y3 reflected in line total
- **Provenance:** SC-3354 / RN-MULTIYEAR

## K. Edge Cases  (17)

### K-01 — Cancellation negative credit at asset NET (not $0)  `P0`
- **Tests:** A cancellation line (Qty=-1) must produce a NEGATIVE TotalPrice credit equal to the asset NET unit price (not list, not $0); the native waterfall seeds no NetUnitPrice for cancel lines so a custom seed supplies it
- **Proc mechanism:** CancelNetUnitPrice__c seed (from AssetActionSource/SourceAsset NetUnitPrice) + V18 seed step; CancelLineCreditPosthook writes NetUnitPrice/TotalPrice/Subtotal via field-API names; Quantity*Price; Null-Safe Line Adjustment
- **Expected:** NetUnitPrice=asset net (e.g. 3000); TotalPrice = NetUnitPrice x -1 = -3000; quote/order header rolls up the negative credit
- **Test setup:** Cancel quote/order, line Qty=-1, asset list 3000 no discount, CancelNetUnitPrice__c populated, expect -3000
- **Provenance:** SC-3441

### K-02 — No-priced-node / missing-contributor derived line surfaced  `P0`
- **Tests:** A derived line whose contributor parent has no priced node must not silently produce $0; the formula attempts fallbacks and the missing contributor is surfaced rather than masked
- **Proc mechanism:** Stamp Contributor Base + Derived Pricing Formula fallback (IF Base_Price__c>0 ... else Pre_Partner ... else InputUnitPrice ... else 0); MissingContributor handling
- **Expected:** Formula tries Pre_Partner/InputUnitPrice; if all 0, net=0 flagged as missing contributor (not silently accepted)
- **Test setup:** Derived maintenance line with parent license not priced (no contributor base)
- **Provenance:** SC-3346 (MissingContributor) / SC-3372

### K-03 — Large-order governor safety (30+ lines / high-qty Power)  `P0`
- **Tests:** The procedure handles a large order (many lines, high-qty Power, tiered matrices, PowerBranching splits) within CPU/SOQL/DML governor limits on Reprice-All and order completion
- **Proc mechanism:** Whole procedure on order context; Aggregate Price / List Operations bulk-safe; batched line creation; deprecated duplicate line-type subflow removed; Apex-stamp + flow-guard for high-qty Power
- **Expected:** Order reprice/complete succeeds; no SOQL:101, CPU limit, or 'too many DML' error
- **Test setup:** Order with 30+ lines incl. high-qty (150+) Power / 500+ node tiers, Reprice-All + complete
- **Provenance:** SC-3366 / SC-3447

### K-04 — Workday extendedAmount channel mismatch (list vs net)  `P0`
- **Tests:** When regional/partner/tiered pricing makes list != net, the Workday sync must not map the LIST channel (TotalLineAmount) as extendedAmount while the header uses NET; the channels must reconcile or the integration maps extendedAmount<-NetTotalPrice
- **Proc mechanism:** Procedure regional/COLA steps write InputUnitPrice/TotalLineAmount (list) while net stays catalog; MuleSoft maps OrderItem.TotalLineAmount->extendedAmount vs header NetTotalPrice/currentContractAmount; fix = extendedAmount<-NetTotalPrice
- **Expected:** extendedAmount == header contract amount (both net); line internally consistent OR Mule maps net-only; no 'Contract Amount and Contract Line Revenue Amount must be equal' error
- **Test setup:** Order with regional (Italy TotalLineAmount 1540 < NetTotalPrice 2400) or partner discount, Workday sync
- **Provenance:** SC-3374 / SC-3347 / SC-3143 (extendedAmount mapping)

### K-05 — Order-tier reprice BEFORE Activate vs Convert-with-auto-activate race (reprice ordering)  `P0`
- **Tests:** The order must be repriced at order context BEFORE activation; a Convert+Auto-Activate that activates before the order-level reprice produces INVALID_INPUT / wrong contributor base; verifies the order-tier reprice-ordering edge distinct from F-07 (happy convert) and the contextDef gack
- **Proc mechanism:** Convert flow must run Reprice-All on OrderItem context before native Activate; SC-3308 race = order activated before order-level reprice; fix=reprice before Activate
- **Expected:** Order-level reprice completes (CompletedWithPricing, contributor base + term fields stamped) BEFORE Activate; no INVALID_INPUT; auto-activate path waits for reprice
- **Test setup:** Convert close-won quote with Convert+Auto-Activate enabled, derived/termed lines, verify reprice precedes activation; repeat to flush intermittent race
- **Provenance:** SC-3308 / SC-3371 (completeness-gap, order-tier ordering)

### K-06 — Zero-dollar / null-missing pricing line safe handling  `P0`
- **Tests:** A $0 line (included component / bundled feature) and a line with no active PricebookEntry (legacy/retired SKU) must not fail the pricing engine or approval logic and must not throw a null-reference
- **Proc mechanism:** CalculationMatrix / pricing formula $0-safe; approval matrix does not block $0; missing-PBE falls back to $0 or graceful warning per design
- **Expected:** $0 line displays 0.00 with no validation error, included in order/invoice; missing-PBE warns 'No pricing found' or defaults $0, no exception
- **Test setup:** Bundled $0 item (e.g. NSS SNMP Trap Receiver in Powertech renewal); and a Legacy_Product='Yes' SKU with no current PBE
- **Provenance:** SC-3345 / SC-3347

### K-07 — Co-owned version churn drops logic deltas (V16 vs V20 reconcile)  `P0`
- **Tests:** Co-ownership of procedure versions causes logic deltas to be lost on republish; the V16->V20 currency rebuild omitted the Term-Defined proration sub-tree, the 7-tier derived reduction, and guards, so any alternate active version must be diffed against the prior version before activation
- **Proc mechanism:** ExpressionSetDefinition V20 (V16 + currency additions) missing Term-Defined-Proration (3 steps) + Derived 7-tier + guards; co-owned edits ping-pong (clobber/re-apply)
- **Expected:** Co-owned versions fully validated against the prior version's logic tree before activation; TermDefined/COLA/Derived branches verified end-to-end; always retrieve live before editing
- **Test setup:** Activate alternate procedure version after co-owner edits, diff V16 vs V20 logic trees, verify TermDefined/COLA/Derived branches
- **Provenance:** SC-3473 / COLA V16-V20

### K-08 — Cancellation of a derived/maintenance line credits derived asset NET (not list, not license net)  `P1`
- **Tests:** A Qty=−1 cancellation of a DERIVED maintenance asset must credit the maintenance asset's own NET (e.g. the 67.38 COLA'd derived value), not the parent license net and not list; K-01 covers a plain license cancel but not the derived-maintenance cancel where CancelNetUnitPrice must come from the maintenance asset
- **Proc mechanism:** CancelNetUnitPrice__c seed from the maintenance SourceAsset/AssetActionSource NetUnitPrice (the derived value) + V18 seed + CancelLineCreditPosthook; must not pull contributor/license base
- **Expected:** NetUnitPrice = maintenance asset net (e.g. 67.38); TotalPrice = −67.38; not −(license net) and not −(tier%×list at current catalog)
- **Test setup:** Cancel a derived maintenance line Qty=−1, maintenance asset net=67.38 (COLA'd), verify credit = −67.38
- **Provenance:** SC-3441 / SC-3346 (completeness-gap cross)

### K-09 — Stale category totals when group empty (Total_Services__c / Total_Software__c)  `P1`
- **Tests:** Conditional category-aggregate fields must reset to 0/null when their group becomes empty; the procedure currently leaves a stale prior value (phantom Services_Total on a quote with zero Services lines), and Subtotal(list) vs TotalPrice(net) divergence yields a phantom Discount%
- **Proc mechanism:** ExpressionSetDefinition category-total steps reset only if lines exist (no init to 0 on empty group); Subtotal aggregation uses list base, TotalPrice uses net, no unified base; rollup formulas cascade from diverged bases
- **Expected:** Empty category -> Total_X__c=0/null on every reprice; pick a unified base so Subtotal matches TotalPrice semantics; Discount% explicit not phantom
- **Test setup:** Quote with Total_Services=$500 then delete the line and reprice (expect 0); quote with mixed list!=net lines check Discount%
- **Provenance:** SC-3345 / Quote pricing rollups

### K-10 — Null-safe filter excludes negative/null qty from positive aggregation  `P1`
- **Tests:** The All Lines Null Safe Filter passes only LineItemQuantity >= 0 so null/negative-qty lines do not corrupt positive sums or throw an NPE
- **Proc mechanism:** All Lines Null Safe Filter (LineItemQuantity GreaterThanOrEquals 0); Null-Check for Line Adjustment; Null-Safe Line Adjustment
- **Expected:** Negative/null qty excluded from the null-safe aggregate; no NPE
- **Test setup:** Mixed quote: one line Qty=-1, one Qty=null, one Qty=5
- **Provenance:** SC-3441 / SC-3473

### K-11 — Qty=0 auto-add middle maintenance line ($0 but correct net)  `P1`
- **Tests:** An auto-added (ProductConfigurationRule) maintenance line born with Quantity=0 (StartQuantity=source asset) prices its net correctly but yields $0; normalizing StartQuantity to the source-asset qty (so qty>0) is the fix
- **Proc mechanism:** RenewalAssetQuantityHandler (before-insert, widened to Amend + New-Maintenance) normalizes StartQuantity=0 + Quantity=source-asset-qty; Quantity*Price (net x 0 = 0); All Lines Null Safe Filter (Qty>=0 includes 0)
- **Expected:** Line born with qty>0 so net unit correct and ItemNetTotalPrice = qty x net (not 0); line type (Amend new-biz / Renew renewal) matches quote action
- **Test setup:** Auto-add PCR maintenance line on Perpetual license, SourceAsset qty>0, Fortra_Product_Type='New Maintenance', derived net correct
- **Provenance:** SC-3346 / SC-3412 / SC-3410

### K-12 — Second-click stale-context on tiered/attribute line  `P1`
- **Tests:** A tiered/attribute-priced line must price correctly on the FIRST reprice, not require a second click (one-cycle stale-context lag on the Unit Quantity / IsPriceImpacting attribute)
- **Proc mechanism:** Attribute Value Pricing modes + IsPriceImpacting attribute sync (set true on tiered PADs); Sync InputUnitPrice from Net / for Discount Base
- **Expected:** Correct price after a single reprice; no one-cycle lag
- **Test setup:** Tiered PAD line, change Unit Quantity attribute, single reprice
- **Provenance:** SC-3390

### K-13 — Sync InputUnitPrice when null (discount-base safety)  `P1`
- **Tests:** When InputUnitPrice is null on a non-LastTransaction non-derived line it is synced from net so the discount base is non-null and discount math is safe
- **Proc mechanism:** Sync InputUnitPrice for Discount Base; ListOperation38 (InputUnitPrice IsNull AND ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute IsNotNull AND =false); Sync InputUnitPrice from Net
- **Expected:** InputUnitPrice hydrated from NetUnitPrice; discount math safe
- **Test setup:** Line with null InputUnitPrice, non-derived, non-LastTransaction
- **Provenance:** SC-3441 / SC-3393

### K-14 — Flow fault handler surfaces real RLM error (not 'unhandled fault')  `P1`
- **Tests:** The Order Submission/Update-Status flow must have fault connectors on all record-update elements so the real RLM error ('PricingTermCount required for termed products') is surfaced via {!$Flow.FaultMessage} instead of a generic 'unhandled fault'
- **Proc mechanism:** Fortra_Order_Submission_Check flow (V13/V14) Update_Order_Stage element needs a faultConnector; error screen shows $Flow.FaultMessage
- **Expected:** Activating a termed line with null PTC via Update Status shows a clear 'PricingTermCount required' message so the user can Reprice
- **Test setup:** Activate order with a termed line (null PTC), use Update Status quick action
- **Provenance:** SC-3411

### K-15 — Context-definition version parity quote vs order (shared SalesTransactionContextExt_v2)  `P1`
- **Tests:** The pricing and discovery procedures share one context definition; quote and order paths must use the same version and the ContextAttributeMapping field API names must match the persist schema (NetUnitPrice not ItemNetTotalPrice), else fields fail to hydrate/persist or throw 'Specify contextDefinitionName'
- **Proc mechanism:** SalesTransactionContextExt_v2 ContextAttribute mappings (QuoteEntitiesMapping / OrderEntitiesMapping); context version tracked in PricingActionParameters; in-place edits to a live active proc require re-syncing context
- **Expected:** Quote and converted order both use the same context version; field API names match schema; re-sync context if fields not hydrating; no contextDefinition gack
- **Test setup:** Price a quote and its converted order, verify both use SalesTransactionContextExt_v2 and fields hydrate
- **Provenance:** SC-3384 / reprice contextDef

### K-16 — Delete-group / sparse-context robustness (no proc-side NPE)  `P2`
- **Tests:** Procedure execution within a quote-group delete or sparse-context scenario must null-safe its filters and not NPE on a missing context node; the native RLM Map.get NPE is platform-side, not proc-side
- **Proc mechanism:** Null-Check for Line Adjustment; Null-Safe Line Adjustment; All Lines Null Safe Filter
- **Expected:** No procedure-side NPE on a missing context node; the 'Delete Group' Map.get NPE is platform-side (config/context edge), not fixable in the procedure
- **Test setup:** Quote group with a deleted group, reprice remaining lines
- **Provenance:** SC-3473

### K-17 — Inactive version delete blocked by PricingActionParameters reference  `P2`
- **Tests:** The platform rejects deletion of any inactive ExpressionSetVersion while PricingActionParameters rows reference it; the documented lifecycle is additive-only (deactivate, never delete)
- **Proc mechanism:** Native RLM referential-integrity check blocks ExpressionSetVersion delete when PricingActionParameters reference the version; keep the 2 context bindings
- **Expected:** Leave inactive versions Inactive (accepted clutter); to delete, coordinate Support to null PricingActionParameters.PricingProcedure first then re-create PAP rows
- **Test setup:** Attempt to delete an inactive V2-V8 version while PricingActionParameters reference Rev_Mgmt_Default_Pricing_Procedure
- **Provenance:** SC-3350

