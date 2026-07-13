-- F3 CORRECTNESS COVERAGE GATE (FortraUAT) — frozen 2026-07-10. Read-only.
-- Constants: Annual TermDefined PSM = 0jPWC000000060b2AA ; OneTime PSM = 0jPWC00000005yz2AA
--            Fortra Price Book = 01sWC0000022GHFYA2 ; Standard Price Book = 01sa5000001vuxlAAA
-- Validate coverage on PSMO/PBE existence, never on UnitPrice (IsDerived PBE = $0 placeholder).

-- G0  Denominator: active New-Maintenance SKUs  (baseline 1683)
SELECT COUNT() FROM Product2
WHERE IsActive=true AND Fortra_Product_Type__c='New Maintenance';

-- G1  STRUCTURAL GAP — SKUs that HAVE an Annual TermDefined PSMO (baseline 122; all Annual, 0 non-annual).
--     LACK-count = G0 - G1 = 1561 (the primary structural coverage gap).
SELECT COUNT_DISTINCT(Product2Id) FROM ProductSellingModelOption
WHERE Product2.IsActive=true AND Product2.Fortra_Product_Type__c='New Maintenance'
  AND ProductSellingModelId='0jPWC000000060b2AA';

-- G1b guard: any New-Maint TermDefined PSMO that is NOT Annual (baseline 0 — confirms all 122 are Annual)
SELECT COUNT_DISTINCT(Product2Id) FROM ProductSellingModelOption
WHERE Product2.IsActive=true AND Product2.Fortra_Product_Type__c='New Maintenance'
  AND ProductSellingModel.SellingModelType='TermDefined'
  AND ProductSellingModelId!='0jPWC000000060b2AA';

-- G2  DEMAND cells — active OneTime PBEs on the PSMO-holders (product|book|currency). Pull, diff in code.
SELECT Product2Id, Pricebook2Id, CurrencyIsoCode, IsDerived FROM PricebookEntry
WHERE IsActive=true AND ProductSellingModel.SellingModelType='OneTime'
  AND Product2Id IN (:the122AnnualHolders);

-- G3  SUPPLY cells — active TermDefined PBEs on the PSMO-holders (baseline 2440 = 2249 nonderived + 191 derived).
SELECT Product2Id, Pricebook2Id, CurrencyIsoCode, IsDerived, ProductSellingModelId FROM PricebookEntry
WHERE IsActive=true AND ProductSellingModel.SellingModelType='TermDefined'
  AND Product2Id IN (:the122AnnualHolders);

-- GATE RULE: a (product,book,currency) OneTime demand cell is COVERED iff there exists an
--   IsActive=true, IsDerived=false, ProductSellingModelId=0jPWC000000060b2AA (Annual) PBE for the same cell.
--   A derived (IsDerived=true) Annual PBE does NOT satisfy the gate ($0 placeholder → SC-3346 vector).

-- G4  DERIVED-SIBLING count — active derived Annual TermDefined PBEs on active New-Maint (baseline 191, ALL USD).
SELECT CurrencyIsoCode, COUNT(Id) FROM PricebookEntry
WHERE IsActive=true AND IsDerived=true AND Product2.IsActive=true
  AND Product2.Fortra_Product_Type__c='New Maintenance'
  AND ProductSellingModel.SellingModelType='TermDefined'
GROUP BY CurrencyIsoCode;

-- G5  Live currency set (baseline 10: ARS AUD CAD CHF EUR GBP ILS JPY NZD USD)
SELECT CurrencyIsoCode, COUNT(Id) FROM PricebookEntry
WHERE IsActive=true AND Product2.IsActive=true AND Product2.Fortra_Product_Type__c='New Maintenance'
  AND ProductSellingModel.SellingModelType='OneTime'
GROUP BY CurrencyIsoCode;

-- G6  07-10 additive scale-out audit (baseline: 1494 IsDerived=false + 166 IsDerived=true = 1660)
SELECT IsDerived, COUNT(Id) FROM PricebookEntry
WHERE Product2.Fortra_Product_Type__c='New Maintenance'
  AND ProductSellingModel.SellingModelType='TermDefined'
  AND CreatedDate>=2026-07-10T00:00:00Z
GROUP BY IsDerived;
