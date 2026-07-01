# V21 Round-2 Portion-1 — Canvas Application Guide (verified vs live FortraUAT, 2026-06-30)

**Mode:** prepare-only. You apply in the UI; I supply exact steps + do read-only verification. No org writes from me.
**Active proc:** `Rev_Mgmt_Default_Pricing_Procedure` V21 — ESDV `9QBWC0000000oWH4AY` (Active), runtime ESV `9QMWC00000025LN4AY`, context SalesTransactionContextExt_v2 (v23).
**Live retrieve:** `Data/pricing-v21-validation/round2/live_retrieve/…meta.xml` — V21 block = lines **110855–117766** (all 22 versions inline; V22 is Draft `9QBWC0000000ofx4AA` — do NOT touch).

## 0. How to apply (deploy reality — settles the spec's MDAPI recipe)
MDAPI deploy does **NOT** reach the V21 runtime (proven 3× in Round 1; `Status` isn't API-updateable). The **only** mechanism that recompiles the runtime is: **RLM canvas → edit step → Save *in-place* (not Save As) → close all canvas tabs → Activate V21 from Setup ▸ Pricing Procedures ▸ Versions list**. Batch all four proc edits (G-02, F-09, H-01, I-03) into ONE Save+Activate. After activating, tell me and I'll re-retrieve + reprice to verify (no clobber, no regression).

**Token caveat (applies to G-02 fallback, F-09, H-01 formulas):** in-formula currency references in V21 use `STICurrencyIsoCode`; `CurrencyIsoCode` appears only as a filter/BKM field. **Use whatever the canvas picker offers** — `STICurrencyIsoCode` inside a FormulaBasedPricing formula, `CurrencyIsoCode` inside an AdvancedListFilter (a line-SObject field). If a token doesn't resolve, every line silently takes the ELSE branch = regression, so confirm it resolves before Save.

---

## G-02 [P0] — ABA (configured) pricing currency-blind (SC-3384)  · gate + fallback
**Before (live):** EUR line `0QLWC000003kmG14AI` Net=1471.995 (=USD ABA 1575 × FX 0.9346); combo line `…G24AI` Net=**$0**. EUR PBE list 2943.99 ignored.
**Root cause:** two ABA container filters have no currency predicate, so the USD-only override in `Attribute_Based_Adjustment_Decision_Table` (`0lDa50000007BEuEAM`) is applied to non-USD lines. The ABA steps write **`NetUnitPrice` in place**; when gated out, non-USD lines get no net → $0.

### Edit 1 — gate `AttributePricingFilter` (parent `ListContainer` seq4, ~line 112004)
Add criterion **pos 5 = `CurrencyIsoCode` Equals `'USD'`**; conditionLogic `1 AND 2 AND 3 AND 4` → `1 AND 2 AND 3 AND 4 AND 5`.
### Edit 2 — gate `AttributePricingFilter8` (parent `ListContainer7` seq5, ~line 112038)
Add criterion **pos 4 = `CurrencyIsoCode` Equals `'USD'`**; conditionLogic `(1 OR 2) AND 3` → `(1 OR 2) AND 3 AND 4`.
New criterion mirrors the existing string-Literal criterion (`operator=Equals`, `sourceFieldName=CurrencyIsoCode`, `value=&apos;USD&apos;`, `valueType=Literal`).

### Edit 3 — NEW fallback group (the part missing in Round 1, why gate-only was reverted)
Non-USD ABA lines, now gated out, must land on the currency-matched EUR PBE net. `PriceBookEntries` (top-level seq2) already loads `ListPrice` = EUR PBE UnitPrice (2943.99), filtered by currency — that's the value to seed from.
Create a new **ListGroup** `ABACurrencyNetFallback` at **top-level seq 6** (immediately after `ListContainer7`/seq5, before `ListContainer5`/seq6 — push existing 6+ down one; sits before FX seq39 and before Sync seq13's consumers). Two children:
- **Guard** (`AdvancedListFilter`, `ABACurrencyNetFallbackFilter`), conditionLogic `1 AND 2 AND 3 AND (4 OR 5)`:
  1. `Has_Attribute_Adjustment__c` Equals `true`
  2. `CurrencyIsoCode` NotEquals `'USD'`
  3. `ItemPricingSource` NotEquals `'LastTransaction'`
  4. `NetUnitPrice` Equals `0`
  5. `NetUnitPrice` IsNull
- **Seed** (`FormulaBasedPricing`, `ABACurrencyNetFallbackSeed`, output `NetUnitPrice`), mirroring `ResetNettoPrePartnerBase`:
  ```
  IF ( Has_Attribute_Adjustment__c = true , IF ( NetUnitPrice > 0 , NetUnitPrice , ListPrice ) , NetUnitPrice )
  ```
The guard restricts to non-USD attribute lines with no net → USD ABA lines (stay 1575) and normal non-ABA lines are provably untouched.

### ⚠️ G-02 FX interaction — MUST verify empirically (double-FX / SC-3384 family)
The seq39 step `CurrencyConversionNetUnitPrice` multiplies `NetUnitPrice × 0.9346`. Today the EUR ABA line's 1471.995 = 1575 × 0.9346, so **the FX step DOES fire on ABA lines.** If you seed native-EUR `ListPrice` (2943.99) and FX still fires, the line double-converts to ~**2751**, not 2943.99. **After activating, reprice `…kmG14AI`:**
- If it reads **2943.99** → done.
- If it reads **~2751** → add an exclusion so the fallback population skips the seq39 FX multiply (criterion `Has_Attribute_Adjustment__c=true AND CurrencyIsoCode!='USD'` on the FX step's skip path). This overlaps the F-09 fix and the FX-config owner's area (G-08) — coordinate.

**Controls:** USD ABA `…l1tO4AQ` stays 1575; EUR `…G14AI` → 2943.99 (see FX check); combo `…G24AI` ≠ $0; J-10/G-01 FX paths unchanged.

---

## F-09 [P1] — non-USD partner net double-converted (SC-3384)
**Before (live):** `0Q0WC000003AaoT0AS` Cobalt EUR Net=4159.867 (=5900×0.92×0.82×0.9346); Pre_Partner_Price__c=5428. Target 4521.59 (=5514.14×0.82).
**Root cause:** step **`SyncInputUnitPricefromNet`** (AssignmentElement, container `SyncInputUnitPriceforDiscountBase` seq13, ~line 117066) copies `InputUnitPrice = NetUnitPrice` unconditionally. For non-USD, NetUnitPrice already carries the org-corporate-rate value, so the discount base is wrong.
**Edit:** change the step so the base is currency-matched list for non-USD (mirror sibling `ResetNettoPrePartnerBase` — swap the AssignmentElement to a FormulaBasedPricing carrying an IF, output `InputUnitPrice`):
```
InputUnitPrice = IF ( <currency>='USD' , NetUnitPrice , IF ( ListPrice > 0 , ListPrice , NetUnitPrice ) )
```
USD path byte-identical to today (protects E-02).
**Controls:** Cobalt → 4521.59; Adv Auth Modes → 2502.39; VM Analyst → 429.92; **USD partner E-02 `0Q0WC000003FO1u0AG` stays 301.75.**
> Note: F-09 and the G-02 FX check share the seq39 double-FX mechanism — verify both EUR nets together after activation.

---

## H-01 [P0] — manual amount discount compounds across reprices  · SPEC WAS WRONG about the step
**Before (live):** `0Q0WC000003Fs1Z0AS` DG Console list 50000, NetUnitPrice eroding 20000→15000→10000 per identical reprice.
**Correction:** H-01 does **NOT** share F-09's step. The amount-discount step `ManualQuoteLevelAmountBasedLineLevel` (container `ListContainer60` top-level seq21, child seq3) reads its base **live from `NetUnitPrice`** (`InputUnitPrice←NetUnitPrice`, line 114621) and writes `NetUnitPrice` back → compounds each reprice. Editing F-09's `SyncInputUnitPricefromNet` does nothing here.

**Edit — NEW re-seed step in `ListContainer60`, immediately before the amount step:**
- Name `ResetAmountBaseFromList`, label "Reset Amount Base to List (Pre-Amount)", parent `ListContainer60`, `FormulaBasedPricing`, output `NetUnitPrice`.
- **Partner-aware formula** (does not clobber the partner discount already applied at seq20):
  ```
  IF ( PartnerDiscountPercent > 0 , IF ( Pre_Partner_Price__c > 0 , Pre_Partner_Price__c , NetUnitPrice ) , ListPrice )
  ```
- **Scope filter** (fire on amount lines only — pure-percentage lines in the same container must be untouched), conditionLogic `1 AND 2`:
  1. `ItemDiscountAmount` IsNotNull
  2. `ItemDiscountAmount` NotEquals `0`
- **Renumber `ListContainer60` children:** `ManualQuoteLevelDiscount`=1 (filter), `NullCheckforLineAdjustment`=2, **`ResetAmountBaseFromList`=3 (NEW)**, `ManualQuoteLevelAmountBasedLineLevel`=**4** (was 3), `ManualQuoteLevelPercentageBasedLineLevel`=**5** (was 4).

**⚠️ Two things to confirm in the canvas picker before Save:**
1. **`ItemDiscountAmount` must be selectable as a filter `sourceFieldName`** (today it's only a ManualDiscount `AdjustmentValue`). If it is NOT selectable, use the fallback design instead: stamp a pre-amount base field once before partner (mirror `StampContributorBasePreDiscount`/`Pre_Partner_Price__c`) and repoint `ManualQuoteLevelAmountBasedLineLevel`'s `InputUnitPrice` at that stamped base — no reset step, no discriminator needed.
2. **Partner+amount stacking intent:** the formula above restores the *pre-partner* base for partner lines. If the business wants the amount to apply *on top of* the partner net, use `NetUnitPrice` in the partner branch instead of `Pre_Partner_Price__c` (still idempotent, since it re-reads a stable base once per reprice).

**Controls:** repro line → 15000/15000/15000 (reprice ≥3×). E-02 (percentage partner) stays 301.75. Pure USD percentage-only line unchanged. `ManualDiscountDerivedMaintenance` (container seq22, out of scope) unchanged.

---

## I-03 [P1] — mid-term Term-Defined net not prorated by PTC (SC-3420/3411)  · SPEC WAS WRONG ("stale data")
**Before (live):** `0QLWC000002LCwH4AW` PTC=0.7397 (correct) but NetTotalPrice=TotalLineAmount=**750** (target 554.79). A fresh UI line reproduces — it's a proc defect, not stale data.
**Root cause:** the only NET×PTC step (`SubscriptionPricing`, output `ItemNetTotalPrice`) is inside ListGroup `EvergreenanytimeprorationfilterLinelevel`, entered only when its filter **`ListOperation87`** (~line 114374) passes `SellingModelType='Evergreen'`. TermDefined lines fail it; the leg they can enter prorates only the LIST column, never NET.
**Edit — broaden `ListOperation87`:** add criterion **pos 4 = `SellingModelType` Equals `'TermDefined'`**; conditionLogic `1 AND 2 AND 3` → `(1 AND 2 AND 3) OR (4 AND 3)` (criterion 3 = `itemTransientEndDate IsNotNull` is shared, so only mid-term TermDefined with an end date enters; full-term is correctly excluded).
**Controls:** repro → 554.79 (250×3×0.7397). Evergreen anytime line unchanged. Full-term TermDefined → full list. One-Time/Perpetual unchanged. **Confirm the native Proration BKM re-derives PTC = the stamped 0.7397** (no disagreement).

---

## E-04 [P1] — Fortra-Originated deals get channel band, not Non_Orig  (headless, but you'll run it)
**Before (live):** `0Q0WC0000039bwH0AQ` BoKS Perpetual (PPM-00028, Deal_Type=Fortra Originated) Net=301.75 (=355×0.85 channel 15%). 0/30 Non_Orig set.
Field semantics: `*_Percent__c` = "Channel Orig.", `Non_Orig_*_Pct__c` = "**Fortra Orig.**".

### 🔴 ORDER MATTERS: do Part (b) data FIRST, then Part (a) swap.
`PartnerPricingPrehookV2` returns **0% → prices at LIST** on any null Non_Orig field (no fallback). Swapping before the data is loaded breaks ALL Fortra-Originated partner pricing.

### Part (b) — populate Non_Orig (you, in the UI)
On **PPM-00028** ("AB Test Partner", Model_Type = Discount), set the five fields (API names):
`Non_Orig_Software_Pct__c`, `Non_Orig_Subscription_Pct__c`, `Non_Orig_New_Maint_Pct__c`, `Non_Orig_Ren_Maint_Pct__c`, `Non_Orig_Services_Pct__c`.
- These are **real business discount terms** — the synthetic PPM rows can't be keyed to the authoritative schedule (`Fortra Discovery Documentation/Channel/Partner Discounts Data Lists/UAT Load Partner Discount Tech and Cyber.xlsx`, sheet `Data to Load C&T`, cols 16–20), and the values are NOT derivable from the channel columns. Use the real schedule value for PPM-00028 if you know which partner tier it represents.
- **To exercise the E-04 path as a test:** any Non_Orig_Software_Pct ≠ 15 makes the fix visible. Example: set all five to a Diamond-GM-style set (e.g. `12/12/12/12/15` = SW/Sub/NewM/RenM/Svc). Then BoKS software line expected **355 × (1 − 12/100) = 312.40** (≠ 301.75). This is a test value, not a business load.

### Part (a) — swap the prehook (you run; command ready)
Prehook lives on `ProcedurePlanOption 1FYWC0000002W3r4AE`, writable field `ApexClassId` (NOT the read-only `ApexClassName`):
```bash
# AFTER Part (b) is populated:
sf data update record -o FortraUAT --sobject ProcedurePlanOption --record-id 1FYWC0000002W3r4AE \
  --values "ApexClassId=01pWC000002TL37YAG"     # PartnerPricingPrehookV2
# rollback:
#   --values "ApexClassId=01pWC000001wAzNYAU"    # PartnerPricingPrehook (V1)
```
**Control after both parts:** `0QLWC000003eoAr4AI` Net = 355 × (1 − Non_Orig_Software_Pct/100), ≠ 301.75; `Partner_Pricing_Source__c` → 'System Calculated'.

---

## Verification runbook (you run reprices; I read results)
For each evidence record, Force-reprice then paste me the QLIs (or I'll SOQL-read after you ping):
```bash
cat > /tmp/body.json <<'JSON'
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"<QUOTE_ID>"}}}]}}
JSON
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "$(cat /tmp/body.json)"
```
Evidence quotes: G-02 `0Q0WC000003FcrF0AS` · H-01 `0Q0WC000003Fs1Z0AS` (reprice ≥3×) · F-09 `0Q0WC000003AaoT0AS` · E-04 `0Q0WC0000039bwH0AQ` · I-03 build a fresh mid-term TermDefined line (the two stale QLIs are on old quotes).
**Regression controls:** USD direct · USD partner E-02 `0Q0WC000003FO1u0AG`→301.75 · BoKS derived · previously-fixed K-01/F-12/G-01/J-06/J-10 (Activate can clobber siblings — re-retrieve V21 + re-verify).

## Recommended order
1. **E-04 data (Part b)** in UI — safe, no proc change.
2. **Batch all 4 proc edits** (G-02 gate+fallback, F-09, H-01, I-03) in the canvas → Save in-place → close tabs → Activate from Versions list. Ping me → I re-retrieve to confirm no clobber.
3. **E-04 swap (Part a)** command.
4. Reprice evidence + controls; check the **G-02/F-09 FX values** specifically (2943.99 vs ~2751). I verify + document.
