# V21 Round-2 Portion-1 — Canvas Walkthrough (click-level)

> UI note: exact button text varies by Revenue Cloud release. I give the element **type** + exact config; look for the closest control. Step **labels** are what the canvas shows; internal **names** (in parens) are for cross-checking against the metadata.

---

## PART A — E-04 data FIRST (no proc change, safe)

**A1.** App Launcher → **Partner Pricing Models** (`Partner_Pricing_Model__c`) → open **PPM-00028** ("AB Test Partner", Model Type = Discount).

**A2.** Edit these five fields (UI shows the *labels*; API names in parens). For a real load use the business schedule; to exercise the E-04 path use the test set shown:

| Field label | API name | Test value |
|---|---|---|
| Software Percent Fortra Orig. | `Non_Orig_Software_Pct__c` | 12 |
| Subscription Percent Fortra Orig. | `Non_Orig_Subscription_Pct__c` | 12 |
| New Maintenance Percent Fortra Orig. | `Non_Orig_New_Maint_Pct__c` | 12 |
| Renewal Maintenance Percent Fortra Orig. | `Non_Orig_Ren_Maint_Pct__c` | 12 |
| Services Percent Fortra Orig. | `Non_Orig_Services_Pct__c` | 15 |

**A3.** Save. **Do NOT swap the prehook yet** (Part C) — the swap only becomes safe once these are non-null.

Expected after full E-04: BoKS software line `355 × (1 − 12/100) = 312.40` (≠ current 301.75).

---

## PART B — the proc edits (ONE canvas session, ONE Activate)

> ⏸️ **HELD 2026-06-30 — B1, B2 (G-02) and B3 (F-09) are multi-currency; do NOT apply.** Deferred to a joint FX session with Marc. The earlier "seed from EUR PBE" formulas were wrong: seq39 `CurrencyConversionNetUnitPrice` always multiplies by the 0.9346 EUR rate, so native-EUR seeds double-convert. Only **B4 (H-01)** and **B5 (I-03)** are active — both are non-multi-currency.

**Open the procedure:** Setup → **Pricing Procedures** → **Revenue Management Default Pricing Procedure** → open version **21 (Active)**.
- Edit **in place**. Never "Save As" (that spawns V22).
- Do **B4 + B5 only**, then Save, then Activate (Part B-Final). Don't Save+Activate between each.

### B1 — G-02 gate the two ABA filters

There are **two** steps both labeled **"Attribute Pricing Filter."** Tell them apart by parent container + current logic:

**B1a — the one under "List Container" (seq 4), name `AttributePricingFilter`.** Its Filter Logic reads **`1 AND 2 AND 3 AND 4`** (criteria: ItemContractAttributePasId IsNotNull / ItemPricingSource ≠ 'LastTransaction' / DerivedPricingAttribute IsNotNull / DerivedPricingAttribute = false).
1. Open it → in the criteria/condition builder click **Add Condition**.
2. Set: **Field** = `CurrencyIsoCode` · **Operator** = Equals · **Value** = `USD` (it becomes criterion **5**).
3. Change **Filter Logic** from `1 AND 2 AND 3 AND 4` → **`1 AND 2 AND 3 AND 4 AND 5`**.
4. Save the step.

**B1b — the one under "List Container 7" (seq 5), name `AttributePricingFilter8`.** Its Filter Logic reads **`(1 OR 2) AND 3`** (IsContracted IsNull / IsContracted = false / ItemPricingSource ≠ 'LastTransaction').
1. Open it → **Add Condition**: **Field** = `CurrencyIsoCode` · **Operator** = Equals · **Value** = `USD` (criterion **4**).
2. Change **Filter Logic** `(1 OR 2) AND 3` → **`(1 OR 2) AND 3 AND 4`**.
3. Save.

> If `CurrencyIsoCode` is NOT offered in the field picker for these filters, stop and tell me — that's the "over-gate to zero" risk and we'd surface currency differently. (It should appear — it's a standard line field, and the `PriceBookEntries` step already uses it.)

### B2 — G-02 fallback group (the part missing in Round 1)

Create a NEW container that runs **right after "List Container 7" (seq 5)** and before "List Container 5" (seq 6).

1. Select **List Container 7** (or the canvas root) → **Add Step / Add Element** → type **List Group**. Name/label it **`ABACurrencyNetFallback`**. Drag it so it sits **immediately below List Container 7** (it must evaluate after the ABA groups but before the FX step).

2. Inside it add child #1 — **Advanced List Filter**, label **`ABACurrencyNetFallbackFilter`**. Add these conditions:
   | # | Field | Operator | Value |
   |---|---|---|---|
   | 1 | `Has_Attribute_Adjustment__c` | Equals | true |
   | 2 | `CurrencyIsoCode` | Not Equals | USD |
   | 3 | `ItemPricingSource` | Not Equals | LastTransaction |
   | 4 | `NetUnitPrice` | Equals | 0 |
   | 5 | `NetUnitPrice` | Is Null | — |

   **Filter Logic:** `1 AND 2 AND 3 AND (4 OR 5)`

3. Inside it add child #2 — **Business Knowledge Model** with **Action Type = Formula Based Pricing**, label **`ABACurrencyNetFallbackSeed`**. Sequence it **after** the filter.
   - **Formula:**
     ```
     IF( Has_Attribute_Adjustment__c = true, IF( NetUnitPrice > 0, NetUnitPrice, ListPrice), NetUnitPrice)
     ```
   - **Output** the result to **`NetUnitPrice`**.
   - (This mirrors the existing "Reset Net to Pre-Partner Base" step — open that one as a shape reference if the input/output mapping panel is unfamiliar.)

### B3 — F-09 fix the discount base for non-USD

1. Find step **"Sync InputUnitPrice from Net"** (`SyncInputUnitPricefromNet`), inside container **"Sync InputUnitPrice for Discount Base"** (seq 13). Today it's a plain **Assignment** (`InputUnitPrice = NetUnitPrice`).
2. Change it to a **Formula Based Pricing** step (same label) so it can hold an IF, **Output = `InputUnitPrice`**, **Formula:**
   ```
   IF( STICurrencyIsoCode = 'USD', NetUnitPrice, IF( ListPrice > 0, ListPrice, NetUnitPrice))
   ```
   - **Currency token:** in a *formula* editor use whatever resolves — existing formulas use **`STICurrencyIsoCode`**. If the picker only offers `CurrencyIsoCode`, use that. If neither resolves, tell me (silent ELSE-branch = regression).
3. Save. (USD path is unchanged, so E-02 stays 301.75.)

### B4 — H-01 stop the amount-discount compounding

Work inside container **"List Container 60"** (seq 21). Its children in order: `ManualQuoteLevelDiscount` (filter, 1) · `NullCheckforLineAdjustment` (2) · **`ManualQuoteLevelAmountBasedLineLevel`** (amount discount, 3) · `ManualQuoteLevelPercentageBasedLineLevel` (percentage, 4).

1. Add a NEW **Business Knowledge Model / Formula Based Pricing** step, label **`ResetAmountBaseFromList`**, as a child of **List Container 60**, positioned **immediately before the amount-discount step** (new sequence 3; the amount step becomes 4, percentage becomes 5 — the canvas should renumber when you drag it into place; verify the order visually).
2. **Scope filter** on this step (amount lines only, and USD-only while multi-currency is on hold) — add its conditions:
   | # | Field | Operator | Value |
   |---|---|---|---|
   | 1 | `ItemDiscountAmount` | Is Not Null | — |
   | 2 | `ItemDiscountAmount` | Not Equals | 0 |
   | 3 | `CurrencyIsoCode` | Equals | USD |

   **Filter Logic:** `1 AND 2 AND 3`
   - Condition 3 confines the fix to USD amount lines — the confirmed defect — and keeps it clear of the deferred multi-currency/FX work (a non-USD reset to `ListPrice` would interact with the seq39 FX step).
   - ⚠️ If `ItemDiscountAmount` is NOT selectable as a condition field here, STOP and tell me — we switch to the alternative (stamp a pre-amount base field, repoint the amount step's input). Don't leave the reset unscoped.
3. **Formula** (partner-aware so it doesn't wipe a partner discount), **Output = `NetUnitPrice`:**
   ```
   IF( PartnerDiscountPercent > 0, IF( Pre_Partner_Price__c > 0, Pre_Partner_Price__c, NetUnitPrice), ListPrice)
   ```
4. Save.

### B5 — I-03 prorate mid-term Term-Defined nets

1. Find the filter step **`ListOperation87`** (label "List Operation") inside the group **"Evergreen anytime proration filter Line level"** (`EvergreenanytimeprorationfilterLinelevel`). Current Filter Logic: **`1 AND 2 AND 3`** (SellingModelType = 'Evergreen' / AllowPartialProrationPeriods = true / itemTransientEndDate IsNotNull).
2. **Add Condition:** **Field** = `SellingModelType` · **Operator** = Equals · **Value** = `TermDefined` (criterion **4**).
3. Change **Filter Logic** `1 AND 2 AND 3` → **`(1 AND 2 AND 3) OR (4 AND 3)`**.
4. Save.

### B-Final — Save + Activate (the load-bearing step)

1. **Save the version in place** (not Save As).
2. **Close ALL Pricing Procedure canvas tabs.** Open a fresh browser tab.
3. Setup → Pricing Procedures → the procedure → **Versions list** → **Activate version 21** (status flip). Do NOT activate from inside a canvas editor; do NOT "Reactivate all dependencies."
4. **Ping me.** I'll re-retrieve V21 and diff to confirm nothing reverted/clobbered before we reprice.

---

## PART C — E-04 prehook swap (after Part A data is saved)

Run (this is safe now that Non_Orig is populated):
```bash
sf data update record -o FortraUAT --sobject ProcedurePlanOption --record-id 1FYWC0000002W3r4AE \
  --values "ApexClassId=01pWC000002TL37YAG"     # PartnerPricingPrehookV2
# rollback if needed:
#   --values "ApexClassId=01pWC000001wAzNYAU"    # V1
```

---

## PART D — verify (you reprice, I read)

Force-reprice each and ping me — I'll SOQL-read and document before/after:
```bash
cat > /tmp/body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<QUOTE_ID>"}}}]}}
JSON
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "$(cat /tmp/body.json)"
```
| Defect | Quote | Expect |
|---|---|---|
| G-02 | `0Q0WC000003FcrF0AS` | EUR `…kmG14AI` = **2943.99** (if ~2751 → FX-exclusion needed); combo `…G24AI` ≠ $0; USD `…l1tO4AQ` = 1575 |
| H-01 | `0Q0WC000003Fs1Z0AS` | reprice **3×** → 15000 / 15000 / 15000 |
| F-09 | `0Q0WC000003AaoT0AS` | Cobalt **4521.59**, AdvAuth 2502.39, VM 429.92 |
| E-04 | `0Q0WC0000039bwH0AQ` | BoKS ≠ 301.75 (e.g. 312.40); Partner_Pricing_Source__c = 'System Calculated' |
| I-03 | new fresh mid-term TermDefined line | NetTotalPrice **554.79** |

**Regression controls:** USD partner E-02 `0Q0WC000003FO1u0AG` = 301.75 · BoKS derived · prior fixes K-01/F-12/G-01/J-06/J-10.
