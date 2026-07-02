# SC-3350 — Context / Docs Scope-Fork + Business Intent (CURRENT TRUTH)

**Ticket:** SC-3350 "COLA Pricing - Renewal quotes are not priced correctly"
**Date:** 2026-06-10 (read-only research). **Org:** FortraUAT.
**Stream:** Context/Docs scope-fork + business intent.
**Predecessor brief:** `Data/sc3354/SC-3354_Research_Brief.md` (08:13Z) — SC-3350 and SC-3354 are the SAME COLA-renewal work (3354 = rework ticket, 3350 = the defect ticket). Brief treated as possibly stale; deltas flagged in §6.

> **NB on ticket scoping:** SC-3350's two stated defects (#1 priced at list, #2 no Line Item Description) are the *symptoms*; SC-3354 is the rework owner-ticket. They share one codebase. This stream answers the **business-target / scope-fork** question only; the "why both defects happen" mechanism lives in the Apex/renewal-creation streams.

---

## 1. The scope-fork question, stated crisply

> **Is SC-3350 just "fix the two year-1 defects" (single-year `Asset.Price × (1+COLA%)` + populate the description), OR does it require wiring multi-year out-year compounding into ACTUAL pricing for license + maintenance?**

The fork exists because there are **two different "sources of truth"** that disagree on scope:

| Source | Model it mandates | Out-year compounding? | Maintenance line? |
|---|---|---|---|
| **COLA SDD v2.0** (Dec 2025) + **COLA Overview** Confluence + **Increase Table** Confluence | **Single-year**, gross-base, renewal-only, 3-tier override | **NO** — not mentioned anywhere | Not differentiated; "renewal quote lines" generically |
| **KB §5.3** (synthesis of the docs) | Single-year `UnitPrice = Asset.Price × (1+COLA%/100)` | NO | No differentiation |
| **Ticket spreadsheet** (Leah Guenther, "Perpetual Sales Calculations") | **Multi-year compounding**, year-1 rate ≠ out-year rate, applied to **both** license/base AND maintenance | **YES** (200→206→212.18; 140→144.20→148.53) | **YES** — license AND maintenance |
| **Live code/data (current)** | Year-1 single-year IS live & correct; **out-year compounding is COMPUTED but NEVER billed (INERT)** | Computed in a display-only formula field, fed to price **0×** | Maintenance handled by a separate derived-pricing path (Path B) |

**This is the whole decision.** Everything else (which Apex path, force-app packaging, test plan) is downstream of which target we are building to.

---

## 2. What the DOCS mandate (all three = single-year, no compounding)

### 2a. COLA Solution Design Document (`Data/sc3347/docs_txt/Fortra-Pricing-COLA-Solution-Design-Doc.txt`)
- **Exec summary (L11):** "automatic annual pricing adjustments for subscription renewal quotes ... using the **current Asset price as the base amount**." 20 Solution Categories, 0%–9.85%.
- **BR-002 (L74-76):** `UnitPrice = Asset.Price × (1 + COLA% / 100)`, preserve `Asset.Price` in `Pre_COLA_Price__c`. **Single multiplier. No year exponent. No out-year rate.**
- **6.3 Business Logic (L266):** worked example `$10,000 × 1.0785 = $10,785.00` — one year, one rate.
- **Three-tier override (BR-003, L77-79):** Line > Contract > CMDT. No MyCAP, no out-year tier.
- **A-005 (L132-133):** COLA applied **before** Regional Pricing; "Final Price = (Asset.Price × (1+COLA%/100)) × Regional Multiplier." (Compounds with *regional*, NOT with out-years. And per the procedure stream this regional claim is itself obsolete — regional is a Services-only MIN/floor.)
- **NOWHERE** in the SDD: "out-year", "MyCAP", "compound", "multi-year", "PricingTermCount", "maintenance line." The SDD is a **clean single-year spec.**

### 2b. COLA Uplift Feature — Solution Design Overview (Confluence, `Document Version: 2.0 | December 2025`)
- Same single-year formula: "Calculates the new price: `UnitPrice = Asset.Price x (1 + COLA%/100)`."
- 9 QLI fields listed — **`COLA_Outyear_Uplift_Percent__c` and `Final_Year_COLA_Calculated_Price__c` are NOT among them.** The out-year fields are **not in the design doc at all** — they are an undocumented later addition.
- Test cases TC-001..TC-007: all single-year. No multi-year/out-year test case.
- Relationship chain: `QuoteLineItem → QuoteAction → Asset → Product2 → ProductCategory`.

### 2c. Cola Increase Table (Confluence, "FORTRA Review Complete 10.10.2025")
- This is the **canonical CMDT rate table** (the source for the 22 live `COLA_Uplift_Rules__mdt` records). Columns: Unit | Solution Group | Solution Category | Solution | **Default COLA Percentage**.
- **Functional Summary is explicitly single-year and single-rate:** "Each renewal quote line will include a COLA Uplift % field ... `Final Price = Base Renewal Price × (1 + COLA_Uplift_Percent__c / 100)`." **No out-year row, no second rate, no compounding.**
- **CRITICAL per-product exceptions the CMDT can't represent** (KB §5.3 flags this as D8):
  - **Systems Management** splits: `MessengerConsole / MessengerPlus / PeekPlus = 12.00%` vs **7.85%** for all other Systems Management products.
  - **Cybersecurity** splits: `SecureCare / Single Sign On Managed Services - IBM i = 4.70%` vs **7.85%** for all other Cybersecurity products.
  - The live `COLA_Uplift_Rules__mdt` is keyed only on `Solution_Category__c`, so it **cannot** hold two rates for one category → these product-level exceptions are **not representable** without a product-level override. (Relevant to defect #1 correctness on those SKUs, independent of the out-year fork.)

**Doc verdict:** all three design artifacts mandate ONLY the single-year model. The two stated SC-3350 defects (priced at list; no description) are **failures to deliver the documented single-year behavior** — i.e., the docs scope SC-3350 as the *small* fork.

---

## 3. What the SPREADSHEET mandates (multi-year compounding, license + maintenance)

Leah Guenther's "Perpetual Sales Calculations" tab (described in the prompt + brief §3; the .xlsx itself is **not in the repo** — only its numbers are on record, so the cell-level detail below is **medium confidence**, sourced from the brief/prompt rather than a fresh open of the file):

- **Base Price + Cola:** `200 → 206 → 212.18` across years (×1.03/yr after the year-1 uplift).
- **Renewal Maintenance Total:** `140 → 144.20 → 148.53` (×1.03/yr) — i.e., **maintenance is uplifted too**, not just the license/base line.
- **Year-1 rate is distinct from the out-year rate:** year-1 uses the **CMDT Solution-Category rate** (4.7%–12%); out-years use a flat **3% MyCAP**.
- Compounding is **geometric per year** on BOTH lines.

**Spreadsheet verdict:** the real business target is **richer than the docs** — multi-year compounding on license *and* maintenance, with two distinct rates. This is the *large* fork.

---

## 4. What the LIVE org actually does (the tie-breaker: out-year is COMPUTED but INERT)

The live implementation is **Marc's half-finished attempt to satisfy the spreadsheet on top of the single-year doc spec.** Verified against current UAT:

### 4a. Year-1 single-year path — LIVE & faithful to the docs
- Handler + prehook compute `COLACalculatedPrice__c = Pre_COLA_Price__c × (1+COLA%/100)`; Path A of the procedure writes `COLACalculatedPrice__c → InputUnitPrice` (procedure stream `live_procedure_v10.md` §3). This is exactly BR-002. **Year-1 works** (brief §3 verified to the penny on audit quote `0Q0WC000003671t0AA`).

### 4b. Out-year RATE field — POPULATED by today's live Apex
The out-year machinery is NOT just a dangling field; it is actively populated:
- **Live `MyCAP_Rules__mdt`** (SOQL, FortraUAT): 1 record `Global`, `Default_Out_Year_Uplift_Percent__c = 3`, `Is_Active__c = true`.
- **TODAY's live `COLAUpliftHandler`** (Marc 16:29Z; `Data/sc3350/research/live_today/COLAUpliftHandler.cls:139-154`): for renewal lines with `COLA_Source ∈ {CMDT Lookup, MyCAP Default}` AND `PricingTermCount > 1` AND `COLA_Outyear_Uplift_Percent__c == null`, it stamps `COLA_Outyear_Uplift_Percent__c = MyCAP_Rules__mdt('Global').Default_Out_Year_Uplift_Percent__c (else 3)`.
- **`COLA_Outyear_Uplift_Percent__c` field** (`Data/cola-renewal-review/live/.../COLA_Outyear_Uplift_Percent__c.field-meta.xml`): description = "applied to out-years (years 2+) ... Defaults to MyCAP_Rules__mdt Global value when COLA Source is MyCAP Default."

### 4c. Out-year COMPOUNDED PRICE — computed in a display-only formula field
- **`Final_Year_COLA_Calculated_Price__c`** (live field-meta, `Data/cola-renewal-review/live/.../Final_Year_COLA_Calculated_Price__c.field-meta.xml`) is a **Currency FORMULA field** (read-only by definition). It compounds:
  - Primary branch: `ROUND( COLACalculatedPrice__c × EXP( LN(1+COLA_Outyear%/100) × (PricingTermCount − 1) ), 2)` when `PricingTermCount>1 AND COLACalculatedPrice>0 AND COLA_Outyear%>0`.
  - Fallback branch: `ROUND( Pre_COLA_Price__c × EXP( LN(1+COLA_Uplift%/100) × PricingTermCount ), 2)`.
  - Else: `COLACalculatedPrice__c` (single-year passthrough).

### 4d. …but the compounded price is NEVER FED TO PRICE (INERT) — re-confirmed today
- **In the procedure (V10, active, byte-identical since 03:22Z republish):** `Final_Year_COLA_Calculated_Price__c` referenced **0×**; `COLA_Outyear_Uplift_Percent__c` **0×**; `MyCAP` **0×** (procedure stream `live_procedure_v10.md` §6).
- **In the live Apex:** `grep Final_Year_COLA_Calculated_Price__c` over `Data/sc3350/live/unpackaged/classes/*` + `live_today/` → the ONLY two hits are **comments** (`COLAUpliftPrehook.cls:437,453`), no read/write of the field.
- **Net:** the system **defaults the out-year rate, and computes the compounded multi-year price, then bills the single-year price anyway.** The spreadsheet's Y2/Y3 totals exist as numbers on the record but **never reach `InputUnitPrice`/`NetUnitPrice`.** This is brief bug **B3 (out-year inert)**, re-confirmed against current V10 + today's Apex.

### 4e. The `Final_Year` formula is also BROKEN if/when activated (brief B4 — confirmed verbatim)
- **Primary branch compounds the WRONG base:** it compounds `COLACalculatedPrice__c` (already year-1-uplifted) rather than the pre-COLA base — and uses exponent `(PricingTermCount − 1)`. That's "year-1 CMDT uplift, then (n−1) out-years of MyCAP" — which is *closer* to the spreadsheet intent, but it compounds off the post-COLA price (a base-choice question for Marc).
- **Fallback branch is wrong twice:** exponent is `PricingTermCount` (no `−1`), so it applies the year-1 rate to ALL years including year 1's already-applied uplift (double-counts year 1); and `PricingTermCount` is a **count of pricing terms (months on many configs)** with **no `PricingTermUnit` guard** — using months as a years exponent. The two branches are mutually inconsistent.
- **Conclusion:** wiring out-years into price is NOT a one-line change — it requires fixing the base + exponent + unit-guard FIRST.

### 4f. Maintenance line — handled by a SEPARATE path, also single-year
- Path B (`DerivedPricingRenewals`, procedure stream §4) handles MDT/maintenance-derived renewal lines: `(Base_Price − Prior_Partner_Discount − Prior_Discretionary_Discount) × (1+COLA%/100) → NetUnitPrice`. **Single-year, and uses a DIFFERENT base (nets prior discounts) than Path A (raw Asset.Price).** So maintenance COLA exists but (a) is single-year and (b) is inconsistent with the license base. The spreadsheet wants maintenance compounded over out-years too → **not implemented.**

---

## 5. Framing the decision for Marc / German (crisp)

**Option A — "Fix the two year-1 defects" (small fork, matches the DOCS).**
- Deliver the documented single-year behavior reliably: (#1) every renewal line gets `Asset.Price × (1+COLA%)` instead of list; (#2) every renewal line gets a Line Item Description.
- Mechanism is the renewal-creation/prehook fix (other streams). **Does NOT touch out-year compounding, the `Final_Year` formula, or maintenance compounding.**
- Leaves the spreadsheet's Y2/Y3 expectation **unmet**, and leaves the out-year machinery (rate defaulting + formula field) as live-but-inert tech debt.
- Also leaves the Increase-Table per-product rate exceptions (Messenger* 12% / SecureCare-SSO 4.70%) **mispriced** unless separately addressed (these are year-1 correctness, in-scope for "priced correctly" even under Option A).

**Option B — "Finish the spreadsheet" (large fork, matches the SPREADSHEET).**
- A + wire `Final_Year_COLA_Calculated_Price__c` (or a corrected out-year price) into the pricing procedure for **license AND maintenance**, with year-1 = CMDT rate and out-years = MyCAP 3%.
- **Prerequisite work before this is safe:** fix the `Final_Year` formula base/exponent/unit bug (§4e); reconcile Path A vs Path B bases (§4f); add an out-year element to the procedure (procedure change → re-sync context); decide maintenance compounding; resolve the per-product rate exceptions.
- Touches the procedure, maintenance derivation, context sync, and regional interaction — materially larger blast radius and test surface.

**Recommended framing question to put to Marc/German (single decision that unblocks everything):**
> *"Does 'priced correctly' in SC-3350 mean (A) the documented single-year `Asset.Price × (1+COLA%)` applied reliably on every renewal line + the missing description — i.e. the SDD/Increase-Table spec — or (B) the spreadsheet's multi-year compounded model (year-1 CMDT rate, out-years 3% MyCAP, on BOTH license and maintenance)? The out-year rate is already defaulted and the compounded price is already computed in `Final_Year_COLA_Calculated_Price__c`, but it is referenced 0× by the live procedure and 0× by live Apex — so today the system computes the multi-year number and bills the single-year one. If B, the `Final_Year` formula's base+exponent+term-unit are wrong and must be fixed before wiring."*

**My read of the evidence (medium confidence):** the **docs scope SC-3350 as Option A**, and the two stated defects are single-year failures. The spreadsheet is the *aspirational* model someone (Marc) started building toward (out-year fields + formula + MyCAP CMDT) but never finished or wired. **Absent an explicit owner decision, the defensible default is Option A** (deliver the documented single-year behavior + description), and to **raise the out-year compounding as a separate, explicitly-scoped follow-up** rather than smuggle a half-built multi-year repricing into a "fix the renewal price" ticket. **This is a business-owner call, not an engineering one — needs Marc/German to choose.**

---

## 6. Deltas vs the 08:13Z SC-3354 brief

1. **Out-year is now KNOWN to be actively populated, not just a dangling field.** Today's live `COLAUpliftHandler` (Marc 16:29Z) stamps `COLA_Outyear_Uplift_Percent__c` from `MyCAP_Rules__mdt('Global')=3` on multi-year renewal lines (`Handler.cls:139-154`), and the prehook runs MyCAP defaulting/eligibility (`COLAUpliftPrehook.cls:75-88`). The brief framed out-year as "computed into a display-only formula but never fed to price"; that is still true for the *price*, but the **rate-defaulting half is alive and well in today's Apex.** Refines B3: it's not "dead code," it's "live machinery whose OUTPUT (the compounded price) is never consumed."
2. **`Final_Year` formula B4 confirmed verbatim against the live field-meta** (primary branch compounds `COLACalculatedPrice__c` with `(PricingTermCount−1)`; fallback uses `PricingTermCount` with no unit guard). Not stale.
3. **Procedure is NOT stale** (separate stream): V10 active, byte-identical since 03:22Z; `Final_Year`/`Outyear`/`MyCAP` all 0× in the procedure. Marc's later-today edits (14:00–16:58Z) were **Apex-only**.
4. **Increase-Table per-product exceptions surfaced as a year-1 correctness item** (Messenger* 12% / SecureCare-SSO 4.70%) that the category-keyed CMDT cannot represent — relevant to "priced correctly" even under Option A. (Brief flagged as D8; this stream confirms it's in the canonical Increase Table doc, not invented.)
5. **MyCAP CMDT field name correction:** the rate field is `MyCAP_Rules__mdt.Default_Out_Year_Uplift_Percent__c` (=3), NOT a "Global_Outyear_Percent__c" (which does not exist — query errored). The brief's "Global out-year 3 / min 3" should be read against this actual field; no `Minimum_Outyear_Percent__c` was queryable in this stream (not verified — see open questions).
6. **Spreadsheet is not in the repo.** Only its numbers (from prompt/brief) are on record; the cell-level claims (206→212.18, 144.20→148.53, year-1≠out-year, license+maintenance) are **medium confidence** — they should be re-verified against the actual attachment before committing to Option B.

---

## 7. Evidence index

- **SDD:** `Data/sc3347/docs_txt/Fortra-Pricing-COLA-Solution-Design-Doc.txt` — Exec L11; BR-002 L74-76; 6.3 L266; A-005 L132-133.
- **Overview (Confluence):** `Confluence/COLA+Uplift+Feature+-+Solution+Design+Overview .doc` (decoded) — v2.0 Dec 2025; 9 fields (no out-year); single-year formula; TC-001..007.
- **Increase Table (Confluence):** `Confluence/Cola+Increase+Table.doc` (decoded) — single-year formula; per-product exceptions Systems Management 12.00 (Messenger*) vs 7.85; Cybersecurity 4.70 (SecureCare/SSO) vs 7.85; IPP/Fortra Platform 0.
- **KB:** `FORTRA_KNOWLEDGE_BASE.md:240-269` (§5.3, single-year + the per-product exception callout).
- **Live `Final_Year` formula:** `Data/cola-renewal-review/live/objects/QuoteLineItem/fields/Final_Year_COLA_Calculated_Price__c.field-meta.xml:5-30`.
- **Live out-year rate field:** `Data/cola-renewal-review/live/objects/QuoteLineItem/fields/COLA_Outyear_Uplift_Percent__c.field-meta.xml:4`.
- **Today's live handler out-year write:** `Data/sc3350/research/live_today/COLAUpliftHandler.cls:139-154`.
- **Live prehook MyCAP machinery:** `Data/sc3350/live/unpackaged/classes/COLAUpliftPrehook.cls:75-88`; Final_Year only in comments L437,453.
- **MyCAP CMDT (SOQL FortraUAT):** `SELECT DeveloperName, Default_Out_Year_Uplift_Percent__c, Is_Active__c FROM MyCAP_Rules__mdt` → `Global | 3 | true` (1 row).
- **Procedure inert-out-year:** sibling stream `Data/sc3350/research/live_procedure_v10.md` §6 (0 refs to Final_Year/Outyear/MyCAP in active V10).
- **SC-3350 ticket folder:** `*Jira/Task/sc3350 | COLA Pricing - Renewal quotes are not priced correctly/` — contains only an empty `evidence/` dir (no description/spreadsheet attached locally).
