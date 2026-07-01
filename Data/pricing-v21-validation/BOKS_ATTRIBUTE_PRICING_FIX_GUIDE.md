# BoKS Attribute-Based Pricing — Detailed Fix Guide

**Org:** FortraUAT · **Quote:** "Pricing Test 10 Nir" `0Q0WC000003GLTN0A4` (USD) · **Date:** 2026-07-01

## What is confirmed (proven by data, not assumed)

The BoKS **license line** `0QLWC000003lXek4AE` has everything needed to hit the attribute override, and it still prices at list:

| Fact | Value | Status |
|---|---|---|
| Attribute **Feature Options** | `100 Node Bundle`, `IsPriceImpacting = true` | ✅ matches the ABA row exactly |
| Product | Powertech IAM (BoKS) `01tWC00000DD1btYAD` | ✅ matches ABA `ProductId` |
| Selling model | **One Time** `0jPWC00000005yz2AA` | ✅ matches ABA `ProductSellingModelId` |
| ABA rule 00010533 | Feature Options `100 Node Bundle` → **Override 20000** | ✅ configured, active, USD |
| **Result** | `NetUnitPrice = 355` (list), `Has_Attribute_Adjustment__c = false` | ❌ override NOT applied |

The line also carries two **extra** attributes the single-attribute rule does not expect:
- **Unit Volume** = *(blank)*, `IsPriceImpacting = false`
- **Maintenance Type Defn** = `Standard`, `IsPriceImpacting = false`  ← the A-07 attribute, on a *license* line

The pricing-procedure attribute steps (**Attribute Pricing Filter**, **Attribute-Based Price**, **Attribute Discount Entries**) are **unchanged** by the recent currency/Portion-1 fixes — verified against the live metadata. So this is **not** a regression from those fixes; it is an attribute-**match** failure on a correctly-configured line.

There are exactly **two** possible sub-causes. **Step 1 tells you which**, because the fix is different for each — do not skip it.

---

## STEP 1 — Confirm which sub-cause (≈5 min)

Goal: find out whether the **extra non-price-impacting attributes** are what breaks the match.

**Do it on a throwaway clone so you don't disturb Nir's quote:**
1. Open Nir's quote `0Q0WC000003GLTN0A4` → **Clone** it (or add a fresh BoKS line to a new test quote and set **Feature Options = 100 Node Bundle**).
2. On the cloned BoKS license line, open the line's product **configurator / Edit Attributes** and **clear** the **Maintenance Type Defn** and **Unit Volume** attributes so the only attribute left is **Feature Options = 100 Node Bundle**. Save.
3. **Reprice** the quote (your "Reprice" / "Calculate Prices" action).
4. Read the line:
   ```
   sf data query -o FortraUAT -q "SELECT NetUnitPrice, Base_Price__c, Has_Attribute_Adjustment__c FROM QuoteLineItem WHERE Id='<clonedLineId>'"
   ```

**Interpret:**
- **NetUnitPrice → 20000, `Has_Attribute_Adjustment__c = true`** ⇒ **Sub-cause A** (the extra attributes break the match). Go to **Step 2A**.
- **Still 355 / false** ⇒ **Sub-cause B** (the decision table itself isn't matching BoKS). Go to **Step 2B**.

> Why a clone: the fix is a product/data change, not a per-quote edit — the clone is only to decide which branch.

---

## STEP 2A — Extra attributes break the match (most likely)

The **Maintenance Type Defn** attribute does not belong on the BoKS **license/Perpetual** product — it belongs on the **New-Maintenance** product. It is almost certainly a **side effect of the A-07 Maintenance-Type backfill** (which added that attribute to ~91 products). Remove it at the source.

**2A.1 — Find where the stray attribute comes from.** Check the Perpetual product's attribute definitions:
```
sf data query -o FortraUAT -q "SELECT Id, AttributeDefinition.Name, AttributeCategory FROM ProductAttributeDefinition WHERE Product2Id='01tWC00000DD1btYAD' ORDER BY AttributeDefinition.Name"
```
- If a **Maintenance Type Defn** row (`AttributeDefinitionId = 0tjWC000000096bYAA`) is present here → it was added to the license product in error. Delete that ProductAttributeDefinition row (Setup → the product → **Product Attributes** related list → remove that attribute), or via API on the returned Id.
- If it is **not** on the product directly, it is coming from a **Product Classification / bundle**. Find it:
  ```
  sf data query -o FortraUAT -q "SELECT Id, Name FROM ProductClassificationAttr WHERE AttributeDefinitionId='0tjWC000000096bYAA' AND ProductClassification.Products... " 
  ```
  (check the classification the BoKS Perpetual product is based on) and remove the Maintenance Type Defn attribute from that classification.

**2A.2 — Fix the blast radius (the other A-07-backfilled products).** The A-07 backfill moved 186 → 277 (≈91 products). Any of those that are **non-maintenance** products carrying attribute-based **Override** rules (like BoKS Feature Options) have the same break. List them:
```
sf data query -o FortraUAT -q "SELECT Product2Id, Product2.Name, Product2.Fortra_Product_Type__c FROM ProductAttributeDefinition WHERE AttributeDefinitionId='0tjWC000000096bYAA' AND Product2.Fortra_Product_Type__c != 'New Maintenance'"
```
Remove the Maintenance Type Defn attribute from every product returned that is **not** a New-Maintenance product.

**2A.3 — (Belt-and-suspenders, procedure) Make the match ignore non-price-impacting attributes.**
The **Attribute-Based Price** and **Attribute Discount Entries** steps should key only on `IsPriceImpacting = true` attributes. Confirm that behavior on the cloned line from Step 1: if clearing the non-impacting attributes changed the result, the match is **not** honoring `IsPriceImpacting` and the durable fix is 2A.1/2A.2 (keep stray attributes off the product). Do **not** try to hand-edit the native ABA hashing — fix the data.

---

## STEP 2B — Decision table not matching BoKS (if Step 1 stayed at 355)

If a clean single-attribute line still doesn't price, the **Attribute-Based Adjustment decision table** (`Attribute_Based_Adjustment_Decision_Table`, `0lDa50000007BEuEAM`) does not contain / is out of sync with the BoKS Override rows.

**2B.1 — Re-publish the Attribute-Based Adjustments** so the decision table regenerates from the live ABA records:
- Setup → **Pricing** / **Attribute-Based Adjustments** for the BoKS product → **re-activate / re-publish** the adjustment (this recomputes each row's `AttributeAdjConditionsHash` and rebuilds the decision-table dataset).
- Confirm the 3 BoKS rows (00010531/532/533) are present after publish.

**2B.2 — Verify the DT dataset picked them up** (their `LastModifiedDate` on `AttributeBasedAdjustment` should advance after the publish).

---

## STEP 3 — Verify (general case, not just happy path)

Reprice a BoKS quote and confirm each Feature value resolves to its override:
```
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body '{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<quoteId>"}}}]}}'
sf data query -o FortraUAT -q "SELECT Product2.Name, NetUnitPrice, Has_Attribute_Adjustment__c FROM QuoteLineItem WHERE QuoteId='<quoteId>'"
```
Expected:
- Feature Options **100 Node Bundle → 20000**
- Feature Options **Standard → 355**
- Feature Options **Entry → 250**
- `Has_Attribute_Adjustment__c = true` on each
- **beSECURE** and other attribute products still price correctly (no regression)

## Reference IDs
- BoKS Perpetual product `01tWC00000DD1btYAD` · BoKS New-Maint product `01tWC00000DD1bsYAD`
- BoKS ABA rows: `00010531` (Standard→355) `00010532` (Entry→250) `00010533` (100 Node Bundle→20000), all `SellingModelType=OneTime`, `CurrencyIsoCode=USD`
- Maintenance Type Defn attribute def `0tjWC000000096bYAA` · Feature Options attribute def `0tjWC000000096ZYAQ`
- Decision table `0lDa50000007BEuEAM`
- Nir's quote `0Q0WC000003GLTN0A4`, BoKS license line `0QLWC000003lXek4AE`
